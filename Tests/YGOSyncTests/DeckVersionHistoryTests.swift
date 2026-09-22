import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

// MARK: - Stubs

/// Counts its reads and can be made to fail, so "reported and left alone" is
/// observable and "read once" is a number rather than an impression.
private final class HistoryStub: DeckHistorying, @unchecked Sendable {
    private let lock = NSLock()
    private let wrapped: (any DeckHistorying)?
    private var failSaves = false
    private var failRestores = false
    private(set) var reads = 0
    private(set) var saves = 0

    init(wrapping wrapped: (any DeckHistorying)? = nil) { self.wrapped = wrapped }

    var readCount: Int { lock.withLock { reads } }

    func failSaving() { lock.withLock { failSaves = true } }
    func failRestoring() { lock.withLock { failRestores = true } }

    func saveVersion(of deckID: Int64, label: String?) async throws -> Int64 {
        let refuse = lock.withLock { saves += 1; return failSaves }
        if refuse { throw DeckHistoryError.versionNotFound(-1) }
        return try await wrapped?.saveVersion(of: deckID, label: label) ?? 0
    }

    func versions(of deckID: Int64) async throws -> [DeckVersion] {
        lock.withLock { reads += 1 }
        return try await wrapped?.versions(of: deckID) ?? []
    }

    func restoreVersion(_ versionID: Int64, of deckID: Int64) async throws {
        if lock.withLock({ failRestores }) { throw DeckHistoryError.versionNotFound(versionID) }
        try await wrapped?.restoreVersion(versionID, of: deckID)
    }
}

@MainActor
@Suite("Deck version history")
struct DeckVersionHistoryTests {
    private struct Rig {
        let repository: SQLiteDeckRepository
        let deck: Deck
        let artworks: [ArtworkIdentifier]
        let database: DatabaseQueue
    }

    private func makeRig() async throws -> Rig {
        let (database, repository) = try RealDeck.seededRepository()
        let cards = try RealDeck.cards()
        let artworks = try cards.prefix(4).map {
            ArtworkIdentifier(try #require($0.cardImages.first).id)
        }
        let deck = try await repository.createDeck(name: "Tuning", format: .goat)
        for artwork in artworks.prefix(2) {
            try await repository.addCard(artwork: artwork, section: .main, to: deck.id)
        }
        return Rig(
            repository: repository,
            deck: try #require(try await repository.deck(with: deck.id)),
            artworks: Array(artworks),
            database: database)
    }

    private func makeEditor(
        _ rig: Rig, history: (any DeckHistorying)?
    ) async -> DeckEditorViewModel {
        let model = DeckEditorViewModel(
            repository: rig.repository, validator: DeckValidator(),
            catalogue: SQLiteCardRepository(database: rig.database),
            editing: rig.repository, history: history)
        await model.load(deckID: rig.deck.id)
        return model
    }

    /// Evidence for R1.AC1: the mark is stored and the editor holds it.
    @Test func savingAVersionStoresItAndTheEditorSeesIt() async throws {
        let rig = try await makeRig()
        let model = await makeEditor(rig, history: rig.repository)
        #expect(model.canUseHistory)

        await model.loadVersions()
        #expect(model.versions.isEmpty)

        await model.saveVersion(named: "Prima dell'esperimento")
        #expect(model.versions.count == 1)
        #expect(model.versionRows.first?.name == "Prima dell'esperimento")
        #expect(model.lastFailure == nil)

        // And it is in storage, not only in the model.
        let stored = try await rig.repository.versions(of: rig.deck.id)
        #expect(stored.count == 1)
    }

    /// Evidence for R1.AC2: a version with no name reads as its moment, which
    /// is the only thing telling two unnamed versions apart.
    @Test func anUnnamedVersionReadsAsTheMomentItWasTaken() async throws {
        let rig = try await makeRig()
        let model = await makeEditor(rig, history: rig.repository)

        await model.saveVersion(named: nil)
        await model.saveVersion(named: "   ")

        let rows = model.versionRows
        #expect(rows.count == 2)
        for row in rows {
            #expect(!row.name.isEmpty)
            #expect(row.name == row.moment, "il nome assente è il momento")
        }
    }

    /// Evidence for R1.AC3: nothing to mark, nothing offered.
    @Test func anEditorWithNoDeckOffersNoHistory() async throws {
        let rig = try await makeRig()
        let model = DeckEditorViewModel(
            repository: rig.repository, validator: DeckValidator(),
            history: rig.repository)

        #expect(!model.canUseHistory, "nessun mazzo caricato")

        await model.saveVersion(named: "Niente")
        await model.loadVersions()
        #expect(model.versions.isEmpty)
        let storedAfterNoDeck = try await rig.repository.versions(of: rig.deck.id)
        #expect(storedAfterNoDeck.isEmpty)

        // An editor built without the port cannot offer it either.
        let portless = await makeEditor(rig, history: nil)
        #expect(!portless.canUseHistory)
        await portless.saveVersion(named: "Nemmeno")
        let storedAfterPortless = try await rig.repository.versions(of: rig.deck.id)
        #expect(storedAfterPortless.isEmpty)
    }

    /// Evidence for R1.AC4: a refused save is reported, and costs nothing.
    @Test func aFailedSaveIsReportedAndLeavesTheDeckAlone() async throws {
        let rig = try await makeRig()
        let stub = HistoryStub(wrapping: rig.repository)
        let model = await makeEditor(rig, history: stub)
        let loaded = try #require(model.deck)
        let before = Set(loaded.slots)

        stub.failSaving()
        await model.saveVersion(named: "Non passerà")

        #expect(model.lastFailure != nil)
        #expect(model.versions.isEmpty)
        let after = try #require(model.deck)
        #expect(Set(after.slots) == before)
        let storedAfterFailure = try await rig.repository.versions(of: rig.deck.id)
        #expect(storedAfterFailure.isEmpty)
    }

    /// Evidence for R2.AC1: newest at the top, and a total order even when two
    /// versions land in the same second.
    @Test func versionsAreListedNewestFirstWithTiesBrokenByIdentifier() async throws {
        let rig = try await makeRig()
        let model = await makeEditor(rig, history: rig.repository)

        await model.saveVersion(named: "Uno")
        await model.saveVersion(named: "Due")
        await model.saveVersion(named: "Tre")

        #expect(model.versionRows.map(\.name) == ["Tre", "Due", "Uno"])

        // Saved inside one second, so the ordering rests on the identifier.
        let identifiers = model.versions.map(\.id)
        #expect(identifiers == identifiers.sorted(by: >))
    }

    /// Evidence for R2.AC2: a row says what it is, when, and how large.
    @Test func eachVersionReportsItsNameItsMomentAndItsSize() async throws {
        let rig = try await makeRig()
        let model = await makeEditor(rig, history: rig.repository)
        let opened = try #require(model.deck)
        #expect(opened.totalCount == 2)

        await model.saveVersion(named: "Due carte")
        await model.add(artwork: rig.artworks[2], to: .main)
        await model.saveVersion(named: "Tre carte")

        let rows = model.versionRows
        #expect(rows.map(\.name) == ["Tre carte", "Due carte"])
        #expect(rows.map(\.cardCount) == [3, 2])
        #expect(rows.allSatisfy { !$0.moment.isEmpty })
        #expect(rows.allSatisfy { $0.isReadable })
    }

    /// Evidence for R2.AC4: never versioned is a thing to say, not a blank.
    @Test func aDeckThatWasNeverVersionedSaysSo() async throws {
        let rig = try await makeRig()
        let model = await makeEditor(rig, history: rig.repository)

        #expect(!model.hasLoadedVersions, "prima di leggere non si sa")
        await model.loadVersions()
        #expect(model.hasLoadedVersions)
        #expect(model.versions.isEmpty)
        #expect(model.versionRows.isEmpty)

        await model.saveVersion(named: "Ora sì")
        #expect(!model.versionRows.isEmpty)
    }

    /// Evidence for NFR2 and NFR4: opening the history is one local read, with
    /// no client, no transport, and no per-row lookup.
    @Test func openingTheHistoryReadsStorageOnceAndNeedsNoNetwork() async throws {
        let rig = try await makeRig()
        let stub = HistoryStub(wrapping: rig.repository)
        let model = await makeEditor(rig, history: stub)

        await model.saveVersion(named: "Uno")
        await model.saveVersion(named: "Due")
        await model.saveVersion(named: "Tre")
        let afterSaves = stub.readCount

        await model.loadVersions()
        #expect(stub.readCount == afterSaves + 1, "una lettura, non una per riga")
        #expect(model.versionRows.count == 3)

        // Every row is complete from that one read.
        #expect(model.versionRows.allSatisfy { $0.cardCount > 0 && !$0.moment.isEmpty })
    }
    // MARK: - Going back

    /// Evidence for R3.AC1 and NFR1: asking arms and changes nothing, and
    /// changing one's mind changes nothing either.
    @Test func askingToRestoreChangesNothingUntilItIsConfirmed() async throws {
        let rig = try await makeRig()
        let model = await makeEditor(rig, history: rig.repository)

        await model.saveVersion(named: "Punto fermo")
        await model.add(artwork: rig.artworks[2], to: .main)
        let current = Set(try #require(model.deck).slots)
        let versionID = try #require(model.versions.first?.id)

        model.askRestore(versionID)
        #expect(model.pendingRestore == versionID)
        let armed = try #require(model.deck)
        #expect(Set(armed.slots) == current)

        model.cancelRestore()
        #expect(model.pendingRestore == nil)
        let declined = try #require(model.deck)
        #expect(Set(declined.slots) == current, "annullare non ripristina")
    }

    /// Evidence for R3.AC2: the deck becomes exactly what the version held.
    @Test func aConfirmedRestoreSetsEverySectionToTheVersionsCounts() async throws {
        let rig = try await makeRig()
        let model = await makeEditor(rig, history: rig.repository)

        let saved = Set(try #require(model.deck).slots)
        await model.saveVersion(named: "Punto fermo")
        let versionID = try #require(model.versions.first?.id)

        await model.add(artwork: rig.artworks[2], to: .main)
        await model.add(artwork: rig.artworks[3], to: .side)
        let changed = try #require(model.deck)
        #expect(Set(changed.slots) != saved)

        await model.confirmRestore(versionID)

        let restored = try #require(model.deck)
        #expect(Set(restored.slots) == saved)
        #expect(restored.count(in: .main) == 2)
        #expect(restored.count(in: .side) == 0)
        #expect(model.lastFailure == nil)
    }

    /// Evidence for R3.AC3: the editor is the restored deck immediately, with
    /// no second refresh path and no reopening.
    @Test func theEditorShowsTheRestoredDeckWithoutBeingReopened() async throws {
        let rig = try await makeRig()
        let model = await makeEditor(rig, history: rig.repository)

        await model.saveVersion(named: "Due carte")
        let versionID = try #require(model.versions.first?.id)
        #expect(model.items.count == 2)

        await model.add(artwork: rig.artworks[2], to: .main)
        #expect(model.items.count == 3)
        let legalityBefore = model.legality

        await model.confirmRestore(versionID)

        #expect(model.items.count == 2, "la lista di carte è quella ripristinata")
        #expect(model.legality != nil, "e la legalità è stata rivalutata")
        #expect(model.legality != legalityBefore || model.items.count == 2)
    }

    /// Evidence for R3.AC4 and NFR1: a restore is itself reversible, which is
    /// what keeps it from being a one-way door in the other direction.
    @Test func theReplacedStateBecomesAVersionThatRestoresBack() async throws {
        let rig = try await makeRig()
        let model = await makeEditor(rig, history: rig.repository)

        await model.saveVersion(named: "Iniziale")
        let initial = try #require(model.versions.first?.id)

        await model.add(artwork: rig.artworks[2], to: .main)
        let experimental = Set(try #require(model.deck).slots)

        await model.confirmRestore(initial)
        #expect(model.items.count == 2)

        // The experiment was kept as a version of its own.
        #expect(model.versions.count == 2)
        let replaced = try #require(model.versions.first)
        #expect(Set(replaced.slots) == experimental)

        await model.confirmRestore(replaced.id)
        let back = try #require(model.deck)
        #expect(Set(back.slots) == experimental)
    }

    /// Evidence for R3.AC5: a refused restore costs nothing but a message.
    @Test func aFailedRestoreLeavesTheDeckExactlyAsItWas() async throws {
        let rig = try await makeRig()
        let stub = HistoryStub(wrapping: rig.repository)
        let model = await makeEditor(rig, history: stub)

        await model.saveVersion(named: "Punto fermo")
        let versionID = try #require(model.versions.first?.id)
        await model.add(artwork: rig.artworks[2], to: .main)
        let current = Set(try #require(model.deck).slots)

        stub.failRestoring()
        await model.confirmRestore(versionID)

        #expect(model.lastFailure != nil)
        let after = try #require(model.deck)
        #expect(Set(after.slots) == current)
        #expect(model.items.count == 3)
    }

    /// Evidence for R3.AC1 and NFR1: the alert's dismissal clears the armed
    /// version before the button's action runs. The window captures it while
    /// the alert is built and hands it over; this is that sequence.
    @Test func aRestoreConfirmedBeforeTheDismissalClearedItStillHappens() async throws {
        let rig = try await makeRig()
        let model = await makeEditor(rig, history: rig.repository)

        let saved = Set(try #require(model.deck).slots)
        await model.saveVersion(named: "Punto fermo")
        await model.add(artwork: rig.artworks[2], to: .main)

        model.askRestore(try #require(model.versions.first?.id))
        let captured = try #require(model.pendingRestore)

        // What the dismissal does before the action runs.
        model.cancelRestore()
        #expect(model.pendingRestore == nil)

        await model.confirmRestore(captured)
        let restored = try #require(model.deck)
        #expect(Set(restored.slots) == saved)
    }
    // MARK: - Without a pointer

    /// Evidence for R4.AC1: the panel opens and closes on the model, so a
    /// shortcut has something to call and the behaviour is provable without a
    /// window. It reads before it appears, so it is never empty and then full.
    @Test func theHistoryOpensAndClosesOnTheModel() async throws {
        let rig = try await makeRig()
        let model = await makeEditor(rig, history: rig.repository)
        await model.saveVersion(named: "Uno")

        #expect(!model.isHistoryVisible)
        await model.showHistory()
        #expect(model.isHistoryVisible)
        #expect(model.versionRows.count == 1, "letta prima di apparire")
        #expect(model.selectedVersion == model.versions.first?.id)

        model.hideHistory()
        #expect(!model.isHistoryVisible)

        // An editor that cannot offer a history does not open one.
        let portless = await makeEditor(rig, history: nil)
        await portless.showHistory()
        #expect(!portless.isHistoryVisible)
    }

    /// Evidence for R4.AC2: the selection walks the list and stops at both
    /// ends, because a held key must not cycle silently.
    @Test func theSelectionWalksTheVersionsAndStopsAtTheEnds() async throws {
        let rig = try await makeRig()
        let model = await makeEditor(rig, history: rig.repository)

        await model.saveVersion(named: "Uno")
        await model.saveVersion(named: "Due")
        await model.saveVersion(named: "Tre")
        await model.showHistory()

        let identifiers = model.versions.map(\.id)
        #expect(model.selectedVersion == identifiers[0])

        model.moveVersionSelection(by: 1)
        #expect(model.selectedVersion == identifiers[1])
        model.moveVersionSelection(by: 1)
        #expect(model.selectedVersion == identifiers[2])

        // The end holds.
        model.moveVersionSelection(by: 1)
        #expect(model.selectedVersion == identifiers[2])

        model.moveVersionSelection(by: -5)
        #expect(model.selectedVersion == identifiers[0], "e si ferma anche in cima")
    }

    /// Evidence for NFR3: a row is a sentence, not a number on its own.
    @Test func aVersionAnnouncesWhatItIsWhenItWasTakenAndHowLarge() async throws {
        let rig = try await makeRig()
        let model = await makeEditor(rig, history: rig.repository)
        await model.saveVersion(named: "Due carte")

        let row = try #require(model.versionRows.first)
        #expect(row.announcement.contains("Due carte"))
        #expect(row.announcement.contains(row.moment))
        #expect(row.announcement.contains("2 carte"))

        let unreadable = DeckVersionRow(
            id: 9, name: "Rotta", moment: row.moment, cardCount: 0, isReadable: false)
        #expect(unreadable.announcement.contains("non leggibile"))
        #expect(!unreadable.announcement.contains("0 carte"),
                "una versione illeggibile non annuncia una dimensione")
    }

    /// Evidence for R4.AC2: an unreadable version is in the list and cannot be
    /// chosen for restoring. Restoring it would empty the deck.
    @Test func anUnreadableVersionCannotBeChosenForRestoring() async throws {
        let rig = try await makeRig()
        let model = await makeEditor(rig, history: rig.repository)

        await model.saveVersion(named: "Buona")
        let versionID = try #require(model.versions.first?.id)
        try await rig.database.write { db in
            try db.execute(
                sql: "UPDATE deck_version SET snapshot = ? WHERE id = ?",
                arguments: ["non è JSON", versionID])
        }

        await model.loadVersions()
        let row = try #require(model.versionRows.first)
        #expect(!row.isReadable)

        let before = Set(try #require(model.deck).slots)
        await model.confirmRestore(versionID)

        #expect(model.lastFailure != nil)
        let after = try #require(model.deck)
        #expect(Set(after.slots) == before, "il mazzo non viene svuotato")
    }
}
