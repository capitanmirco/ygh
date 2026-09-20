import Foundation
import GRDB
import Testing
import YGOCore
import YGODeckIO
import YGOFeatureCollection
import YGOPersistence
import YGOValidation
@testable import YGOSync

@Suite(.serialized)
struct CollectionBudgetTests {
    /// Evidence for NFR1: recording a copy is something a collector does
    /// hundreds of times in a sitting, so it has to stay instant when the
    /// collection is large.
    @Test func recordingACopyUpdatesTotalsUnderFiftyMilliseconds() async throws {
        let rig = try CollectionFixture.seeded()
        let (cardID, printings) = try CollectionFixture.cardWithPrintings(1, in: rig)

        // Ten thousand copies, inserted directly so the measurement is of
        // recording rather than of building the fixture.
        try await rig.database.write { db in
            let statement = try db.makeStatement(sql: """
                INSERT INTO collection_entry (card_id, print_id, condition, quantity)
                VALUES (?, ?, 'near_mint', 1)
                """)
            let prints = try Int64.fetchAll(db, sql: "SELECT id FROM card_print LIMIT 2000")
            var inserted = 0
            while inserted < 10_000 {
                for printID in prints where inserted < 10_000 {
                    let owner = try Int.fetchOne(db, sql:
                        "SELECT card_id FROM card_print WHERE id = ?", arguments: [printID])
                    try statement.execute(arguments: [owner, printID])
                    inserted += 1
                }
            }
        }

        let seeded = try await rig.collection.totals()
        #expect(seeded.totalCopies >= 10_000, "servono diecimila copie perché la misura conti")

        // One untimed pass so first-use costs stay out of it.
        try await rig.collection.addCopy(
            cardID: CardIdentifier(cardID), printID: printings[0])
        _ = try await rig.collection.totals()

        var samples: [Double] = []
        for _ in 0..<40 {
            let started = ContinuousClock.now
            try await rig.collection.addCopy(
                cardID: CardIdentifier(cardID), printID: printings[0])
            _ = try await rig.collection.totals()
            samples.append(Double(started.duration(to: .now).components.attoseconds) / 1e15)
        }

        samples.sort()
        let p95 = samples[Int(Double(samples.count) * 0.95)]
        #expect(p95 < 50, "p95 \(String(format: "%.1f", p95)) ms sopra il budget di 50 ms")
    }

    /// Evidence for NFR2: nothing here loses a hand-entered copy by itself.
    @Test @MainActor func noRemovalOrImportLosesCopiesWithoutConfirmation() async throws {
        let rig = try CollectionFixture.seeded()
        let (cardID, printings) = try CollectionFixture.cardWithPrintings(1, in: rig)
        try await rig.collection.addCopy(cardID: CardIdentifier(cardID), printID: printings[0])
        let before = try await rig.collection.backupRows()

        // Clearing refuses without confirmation.
        await #expect(throws: CollectionError.removalNotConfirmed) {
            try await rig.collection.clearCollection(confirmed: false)
        }
        #expect(try await rig.collection.backupRows() == before)

        // Deleting one lot refuses too.
        let entry = try #require(try await rig.collection.entries().first)
        await #expect(throws: CollectionError.removalNotConfirmed) {
            try await rig.collection.deleteEntry(entry.id, confirmed: false)
        }
        #expect(try await rig.collection.backupRows() == before)

        // The view model asks rather than acts.
        let model = CollectionViewModel(reader: rig.collection)
        model.requestRemoval(of: CardIdentifier(cardID))
        #expect(model.pendingRemoval == CardIdentifier(cardID))
        model.cancelRemoval()
        #expect(model.pendingRemoval == nil)
        #expect(try await rig.collection.backupRows() == before)

        // A corrupt import leaves everything where it was.
        await #expect(throws: CollectionBackupError.self) {
            _ = try await rig.collection.importCSV("non,un,backup", replacingExisting: true)
        }
        #expect(try await rig.collection.backupRows() == before)
    }

    /// Evidence for NFR3: the collection reads stored data and the user's own
    /// records, so there is no network seam in this feature at all.
    @Test @MainActor func everyCollectionBehaviourAnswersOffline() async throws {
        let rig = try CollectionFixture.seeded()
        let (cardID, printings) = try CollectionFixture.cardWithPrintings(2, in: rig)
        let binder = try await rig.collection.createLocation(named: "Raccoglitore")

        try await rig.collection.addCopy(
            cardID: CardIdentifier(cardID), printID: printings[0], locationID: binder)
        try await rig.collection.addCopy(cardID: CardIdentifier(cardID), printID: printings[1])

        // Recording, totalling, searching, filtering, locating, exporting and
        // reporting a shortfall all answer with nothing stubbed out, because
        // there is nothing to stub.
        #expect(try await rig.collection.totals().totalCopies == 2)
        #expect(try await rig.collection.ownedCards().count == 1)
        #expect(try await rig.collection.whereabouts(of: CardIdentifier(cardID)).count == 2)
        #expect(try await rig.collection.listing(matching: CollectionFilters()).entries.count == 2)
        #expect(!(try await rig.collection.exportCSV()).isEmpty)
        #expect(try await rig.collection.copiesByRarity().values.reduce(0, +) == 2)

        let model = CollectionViewModel(reader: rig.collection)
        await model.reload()
        #expect(model.items.count == 1)
        #expect(model.totals?.totalCopies == 2)
    }

    /// Evidence for NFR4: the two counts answer different questions and must
    /// not disagree about the part they share, which is that copies are summed
    /// across every section of a deck and every printing in a collection.
    @Test @MainActor func shortfallAndDeckValidationAgreeOnCopyCounts() async throws {
        let rig = try CollectionFixture.seeded()
        let importer = DeckImporter(repository: rig.decks, validator: DeckValidator())
        let result = try await importer.importFile(
            at: RealDeck.root.appending(path: "fixtures/Lockdown Burn.ydk"))

        // The deck's own per-card counts, as the shortfall reads them.
        let required = ShortfallCalculator.required(in: result.deck)

        // The same figures, summed straight off the deck's slots.
        var direct: [CardIdentifier: Int] = [:]
        for slot in result.deck.slots { direct[slot.card, default: 0] += slot.quantity }
        #expect(required == direct)

        // And they account for every card in the deck, across all sections.
        #expect(required.values.reduce(0, +) == result.deck.totalCount)

        // Owning exactly what the deck asks for leaves nothing missing.
        for (card, count) in required {
            try await rig.collection.setQuantity(
                count, cardID: card, printID: nil)
        }
        let owned = try await rig.collection.copiesByCard()
        let shortfall = ShortfallCalculator.shortfall(
            deck: result.deck, names: [:], owned: owned)
        #expect(shortfall.isEmpty, "posseduto esattamente quanto serve: \(shortfall.map(\.sentence))")

        // Removing one copy of one card makes exactly one card short by one.
        let victim = try #require(required.keys.sorted { $0.rawValue < $1.rawValue }.first)
        try await rig.collection.setQuantity(
            required[victim]! - 1, cardID: victim, printID: nil)
        let afterRemoval = ShortfallCalculator.shortfall(
            deck: result.deck, names: [:],
            owned: try await rig.collection.copiesByCard())
        #expect(afterRemoval.count == 1)
        #expect(afterRemoval[0].missing == 1)
    }
}
