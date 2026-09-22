import Foundation
import GRDB
import Testing
import YGOCore
@testable import YGOPersistence

@Suite("Deck version storage")
struct DeckVersionStorageTests {
    /// Two decks, each holding cards, so a restore into the wrong one would be
    /// visible rather than theoretical.
    private struct Rig {
        let database: DatabaseQueue
        let repository: SQLiteDeckRepository
        let mine: Int64
        let theirs: Int64
    }

    private func makeRig() async throws -> Rig {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)
        try await queue.write { db in
            for id in 1...4 {
                try db.execute(sql: """
                    INSERT INTO card (id, name_en, desc_en, type, frame_type, human_readable_type)
                    VALUES (?, ?, 'effect text', 'Spell Card', 'spell', 'Spell Card')
                    """, arguments: [id, "Card \(id)"])
                try db.execute(sql: """
                    INSERT INTO card_artwork (artwork_id, card_id, ordinal) VALUES (?, ?, 0)
                    """, arguments: [id, id])
            }
        }

        let repository = SQLiteDeckRepository(database: queue)
        let mine = try await repository.createDeck(name: "Mio", format: .tcg)
        let theirs = try await repository.createDeck(name: "Altrui", format: .tcg)

        try await repository.addCard(artwork: ArtworkIdentifier(1), section: .main, to: mine.id)
        try await repository.addCard(artwork: ArtworkIdentifier(2), section: .main, to: mine.id)
        try await repository.addCard(artwork: ArtworkIdentifier(3), section: .main, to: theirs.id)

        return Rig(database: queue, repository: repository, mine: mine.id, theirs: theirs.id)
    }

    private func slots(_ rig: Rig, _ deckID: Int64) async throws -> Set<DeckSlot> {
        Set(try #require(try await rig.repository.deck(with: deckID)).slots)
    }

    /// Evidence for R2.AC3: the port answers for one deck and not for another,
    /// which is what a panel showing "this deck's history" rests on.
    @Test func theRepositoryAnswersTheHistoryPortForOneDeckOnly() async throws {
        let rig = try await makeRig()
        let history: any DeckHistorying = rig.repository

        try await history.saveVersion(of: rig.mine, label: "Primo")
        try await history.saveVersion(of: rig.mine, label: "Secondo")
        try await history.saveVersion(of: rig.theirs, label: "Loro")

        let mine = try await history.versions(of: rig.mine)
        #expect(mine.count == 2)
        #expect(mine.map(\.label) == ["Primo", "Secondo"])
        #expect(mine.allSatisfy { $0.deckID == rig.mine })

        let theirs = try await history.versions(of: rig.theirs)
        #expect(theirs.map(\.label) == ["Loro"])

        // And the size travels with the version rather than being recomputed.
        #expect(mine.first?.cardCount == 2)
        #expect(theirs.first?.cardCount == 1)
    }

    /// Evidence for R2.AC5: a version nobody can read is not a version of an
    /// empty deck, and offering to restore it would empty the deck instead.
    @Test func anUndecodableSnapshotIsMarkedUnreadableRatherThanEmpty() async throws {
        let rig = try await makeRig()
        let versionID = try await rig.repository.saveVersion(of: rig.mine, label: "Buona")

        try await rig.database.write { db in
            try db.execute(
                sql: "UPDATE deck_version SET snapshot = ? WHERE id = ?",
                arguments: ["questo non è JSON", versionID])
        }

        let versions = try await rig.repository.versions(of: rig.mine)
        let broken = try #require(versions.first)
        #expect(broken.isReadable == false)
        #expect(broken.slots.isEmpty)
        #expect(broken.cardCount == 0)
        #expect(broken.label == "Buona", "il resto della riga resta leggibile")

        // A readable version of a genuinely empty deck is the other case, and
        // it must not look the same.
        let empty = try await rig.repository.createDeck(name: "Vuoto", format: .tcg)
        try await rig.repository.saveVersion(of: empty.id, label: "Niente")
        let emptyVersion = try #require(try await rig.repository.versions(of: empty.id).first)
        #expect(emptyVersion.isReadable)
        #expect(emptyVersion.slots.isEmpty)
    }

    /// Evidence for R2.AC5: one corrupt row must not take the history with it.
    @Test func oneCorruptVersionDoesNotHideTheOthers() async throws {
        let rig = try await makeRig()
        let first = try await rig.repository.saveVersion(of: rig.mine, label: "Uno")
        try await rig.repository.addCard(artwork: ArtworkIdentifier(4), section: .main, to: rig.mine)
        try await rig.repository.saveVersion(of: rig.mine, label: "Due")

        try await rig.database.write { db in
            try db.execute(
                sql: "UPDATE deck_version SET snapshot = ? WHERE id = ?",
                arguments: ["{ rotto", first])
        }

        let versions = try await rig.repository.versions(of: rig.mine)
        #expect(versions.count == 2)
        #expect(versions.map(\.isReadable) == [false, true])
        #expect(versions.last?.cardCount == 3, "la versione sana conta ancora le sue carte")
    }

    /// Evidence for R3.AC6: the guard refuses before anything is deleted.
    @Test func restoringAVersionOfAnotherDeckIsRefused() async throws {
        let rig = try await makeRig()
        let theirVersion = try await rig.repository.saveVersion(of: rig.theirs, label: "Loro")

        await #expect(throws: DeckHistoryError.self) {
            try await rig.repository.restoreVersion(theirVersion, of: rig.mine)
        }

        // An identifier belonging to nothing is refused too.
        await #expect(throws: DeckHistoryError.self) {
            try await rig.repository.restoreVersion(9_999, of: rig.mine)
        }
    }

    /// Evidence for R3.AC6: refusing is not the same as refusing afterwards.
    /// The unguarded call would have rewritten the other deck.
    @Test func aRefusedRestoreLeavesBothDecksUntouched() async throws {
        let rig = try await makeRig()

        // Their version holds one card; since saving it, their deck grew.
        let theirVersion = try await rig.repository.saveVersion(of: rig.theirs, label: "Loro")
        try await rig.repository.addCard(artwork: ArtworkIdentifier(4), section: .main, to: rig.theirs)

        let mineBefore = try await slots(rig, rig.mine)
        let theirsBefore = try await slots(rig, rig.theirs)
        let versionsBefore = try await rig.repository.versions(of: rig.theirs).count

        await #expect(throws: DeckHistoryError.self) {
            try await rig.repository.restoreVersion(theirVersion, of: rig.mine)
        }

        #expect(try await slots(rig, rig.mine) == mineBefore)
        #expect(try await slots(rig, rig.theirs) == theirsBefore, "nemmeno il mazzo che la possiede")
        #expect(try await rig.repository.versions(of: rig.theirs).count == versionsBefore,
                "e nessuna versione di salvaguardia è stata scritta")
    }

    /// Evidence for R3.AC6: the guard lets through what it should, and the
    /// restore is the one that already existed rather than a second one.
    @Test func theGuardedRestoreAppliesAVersionOfItsOwnDeck() async throws {
        let rig = try await makeRig()
        let saved = try await slots(rig, rig.mine)
        let versionID = try await rig.repository.saveVersion(of: rig.mine, label: "Punto fermo")

        try await rig.repository.addCard(artwork: ArtworkIdentifier(4), section: .main, to: rig.mine)
        #expect(try await slots(rig, rig.mine) != saved)

        try await rig.repository.restoreVersion(versionID, of: rig.mine)
        #expect(try await slots(rig, rig.mine) == saved)

        // The replaced state was kept, which is what makes a restore reversible.
        let versions = try await rig.repository.versions(of: rig.mine)
        #expect(versions.count == 2)
        #expect(versions.last?.cardCount == 3)
    }
}
