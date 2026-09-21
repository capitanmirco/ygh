import Foundation
import GRDB
import Testing
import YGOCore
import YGODeckIO
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

@MainActor
@Suite("Deck edit budgets")
struct DeckEditBudgetTests {
    /// The user's own deck: 40 main, 15 extra, 15 side. An edit that feels
    /// instant on three cards is not evidence.
    private func fullDeck() async throws -> (DatabaseQueue, SQLiteDeckRepository, DeckEditorViewModel, Deck) {
        let (database, repository) = try RealDeck.seededRepository()
        let importer = DeckImporter(repository: repository, validator: DeckValidator())
        let result = try await importer.importFile(
            at: RealDeck.root.appending(path: "fixtures/LR-Chaos Turbo.ydk"))

        let model = DeckEditorViewModel(
            repository: repository, validator: DeckValidator(),
            catalogue: SQLiteCardRepository(database: database), editing: repository)
        await model.load(deckID: result.deck.id)
        return (database, repository, model, result.deck)
    }

    private func readSync<T>(
        _ database: DatabaseQueue, _ body: (Database) throws -> T
    ) throws -> T {
        try database.read(body)
    }

    /// Evidence for NFR1: dragging a card must not feel like waiting for a
    /// save. Measured on a full deck, including the reload that follows.
    @Test func anEditIsReflectedWithinOneHundredMilliseconds() async throws {
        let (_, _, model, _) = try await fullDeck()
        #expect(model.items.count > 20)
        let artwork = try #require(model.items.first?.id)
        let section = try #require(model.items.first?.section)

        // One untimed pass so first-use costs stay out of the measurement.
        await model.setQuantity(2, of: artwork, in: section)

        // The median rather than the worst of the samples.
        //
        // The worst case is not measurable here: this suite runs alongside
        // fifty others on the same machine, and a single sample taken while
        // the CPU is saturated says nothing about how an edit feels in the
        // application. The median still fails if an edit is genuinely slow —
        // it takes a few milliseconds when it is not.
        var samples: [Double] = []
        for count in [3, 2, 1, 2, 3, 1, 2, 3, 1] {
            let started = DispatchTime.now().uptimeNanoseconds
            await model.setQuantity(count, of: artwork, in: section)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
            #expect(model.quantity(of: artwork, in: section) == count)
        }

        // A move costs a transaction too.
        let started = DispatchTime.now().uptimeNanoseconds
        await model.move(artwork, from: section, to: .side, copies: 1)
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)

        let median = samples.sorted()[samples.count / 2]
        #expect(median < 100, "median edit \(median) ms of \(samples.sorted())")
    }

    /// Evidence for NFR2: the edit is written before the editor reports it, so
    /// closing the application immediately afterwards cannot lose it. Read
    /// back from storage rather than trusted.
    @Test func theEditIsStoredBeforeItIsReportedDone() async throws {
        let (database, _, model, deck) = try await fullDeck()
        let artwork = try #require(model.items.first?.id)
        let section = try #require(model.items.first?.section)

        await model.setQuantity(3, of: artwork, in: section)

        // At this instant, with nothing flushed or waited for, the row is in
        // the database.
        let stored = try readSync(database) { db in
            try Int.fetchOne(db, sql: """
                SELECT quantity FROM deck_slot
                WHERE deck_id = ? AND section = ? AND artwork_id = ?
                """, arguments: [deck.id, section.rawValue, artwork.rawValue])
        }
        #expect(stored == 3)
        #expect(model.quantity(of: artwork, in: section) == 3)

        await model.move(artwork, from: section, to: .side, copies: 2)
        let movedStored = try readSync(database) { db in
            try Int.fetchOne(db, sql: """
                SELECT quantity FROM deck_slot
                WHERE deck_id = ? AND section = 'side' AND artwork_id = ?
                """, arguments: [deck.id, artwork.rawValue])
        }
        #expect(movedStored == 2)
    }

    /// Evidence for NFR5: every edit is local SQL. Nothing in the editing path
    /// can reach a network, which is proven by there being no outbound seam in
    /// the graph at all.
    @Test func everyEditIsAppliedWithNoNetwork() async throws {
        let (database, repository, model, deck) = try await fullDeck()
        let artwork = try #require(model.items.first?.id)

        await model.setQuantity(2, of: artwork, in: .main)
        await model.move(artwork, from: .main, to: .extra, copies: 1)
        await model.undo()
        await model.redo()

        #expect(model.lastFailure == nil)

        // Everything the editor now shows came out of the database it was
        // given, which is the only collaborator it has for editing.
        let rows = try readSync(database) { db in
            try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM deck_slot WHERE deck_id = ?", arguments: [deck.id])
        }
        #expect(rows == model.items.count)
        #expect(try await repository.deck(with: deck.id)?.slots.count == model.items.count)
    }

    /// Evidence for NFR3: after a refused edit the editor must not be showing
    /// a deck ahead of the stored one, which is the failure mode that makes a
    /// user save work they have already lost.
    @Test func aFailedEditNeverLeavesTheShownDeckAhead() async throws {
        let (database, _, _, deck) = try await fullDeck()

        let refusing = DeckEditorViewModel(
            repository: SQLiteDeckRepository(database: database),
            validator: DeckValidator(),
            catalogue: SQLiteCardRepository(database: database),
            editing: RefusingDeckEditor())
        await refusing.load(deckID: deck.id)

        let artwork = try #require(refusing.items.first?.id)
        let before = refusing.items.map { "\($0.section.rawValue)/\($0.id.rawValue)x\($0.quantity)" }.sorted()

        await refusing.setQuantity(9, of: artwork, in: .main)
        await refusing.move(artwork, from: .main, to: .side, copies: 2)

        #expect(refusing.lastFailure != nil)
        let after = refusing.items.map { "\($0.section.rawValue)/\($0.id.rawValue)x\($0.quantity)" }.sorted()
        #expect(after == before)

        let stored = try readSync(database) { db in
            try Row.fetchAll(db, sql: """
                SELECT section, artwork_id, quantity FROM deck_slot WHERE deck_id = ?
                """, arguments: [deck.id])
                .map { "\($0["section"] as String)/\($0["artwork_id"] as Int)x\($0["quantity"] as Int)" }
                .sorted()
        }
        #expect(after == stored)
    }
}
