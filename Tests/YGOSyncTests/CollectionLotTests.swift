import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOSync

/// A lot is identical copies acquired together. What separates two lots of the
/// same card is what genuinely differs about them: condition, and the purchase
/// they came from.
@Suite("Collection lots")
struct CollectionLotTests {
    private static let bought = Date(timeIntervalSince1970: 1_700_000_000)

    private func rig() throws -> (CollectionFixture.Rig, CardIdentifier, Int64) {
        let rig = try CollectionFixture.seeded()
        let (cardID, printings) = try CollectionFixture.cardWithPrintings(1, in: rig)
        return (rig, CardIdentifier(cardID), printings[0])
    }

    /// Evidence for R2.AC2: what a copy cost and when it arrived both survive.
    @Test func storesWhatACopyCostAndWhenItWasAcquired() async throws {
        let (rig, card, printID) = try rig()

        try await rig.collection.recordPurchase(
            cardID: card, printID: printID, condition: .nearMint,
            quantity: 2, pricePerCopy: 3.5, acquiredAt: Self.bought,
            notes: "Comprata in negozio")

        let entry = try #require(try await rig.collection.entries(forCard: card).first)
        #expect(entry.purchasePrice == 3.5)
        #expect(entry.quantity == 2)
        #expect(entry.notes == "Comprata in negozio")
        let acquired = try #require(entry.acquiredAt)
        #expect(abs(acquired.timeIntervalSince(Self.bought)) < 1)

        // The price is per copy, so the lot cost twice it.
        #expect(entry.lotCost == 7.0)

        // And it survives being read back from storage rather than from memory.
        let reread = try #require(try await rig.collection.entries().first)
        #expect(reread.purchasePrice == 3.5)
    }

    /// Evidence for R2.AC3: most of a collection was never priced, and that is
    /// a normal state rather than a gap to fill with zero.
    @Test func storesALotWithNeitherPriceNorDate() async throws {
        let (rig, card, printID) = try rig()

        try await rig.collection.addCopy(cardID: card, printID: printID)

        let entry = try #require(try await rig.collection.entries(forCard: card).first)
        #expect(entry.purchasePrice == nil, "prezzo non registrato non è prezzo zero")
        #expect(entry.acquiredAt == nil)
        #expect(entry.lotCost == nil)
        #expect(entry.quantity == 1)
    }

    /// Evidence for R2.AC4: editing one thing changes one thing.
    @Test func editingOneFieldLeavesTheOthersAlone() async throws {
        let (rig, card, printID) = try rig()
        let id = try await rig.collection.recordPurchase(
            cardID: card, printID: printID, condition: .nearMint,
            quantity: 1, pricePerCopy: 2.0, acquiredAt: Self.bought, notes: "prima")

        try await rig.collection.updateEntry(id, condition: .lightlyPlayed)
        var entry = try #require(try await rig.collection.entries().first { $0.id == id })
        #expect(entry.condition == .lightlyPlayed)
        #expect(entry.purchasePrice == 2.0)
        #expect(entry.notes == "prima")

        try await rig.collection.updateEntry(id, purchasePrice: 9.0)
        entry = try #require(try await rig.collection.entries().first { $0.id == id })
        #expect(entry.purchasePrice == 9.0)
        #expect(entry.condition == .lightlyPlayed, "il campo precedente non deve tornare indietro")
        #expect(entry.notes == "prima")

        try await rig.collection.updateEntry(id, notes: "dopo")
        entry = try #require(try await rig.collection.entries().first { $0.id == id })
        #expect(entry.notes == "dopo")
        #expect(entry.purchasePrice == 9.0)
    }

    /// Evidence for R2.AC5: a played copy and a mint one are not
    /// interchangeable, so they are not one row.
    @Test func keepsDifferentConditionsAsSeparateLots() async throws {
        let (rig, card, printID) = try rig()

        try await rig.collection.addCopy(cardID: card, printID: printID, condition: .nearMint)
        try await rig.collection.addCopy(cardID: card, printID: printID, condition: .nearMint)
        try await rig.collection.addCopy(cardID: card, printID: printID, condition: .damaged)

        let entries = try await rig.collection.entries(forCard: card)
        #expect(entries.count == 2, "due condizioni, due lotti")
        #expect(Set(entries.map(\.condition)) == [.nearMint, .damaged])
        #expect(entries.first { $0.condition == .nearMint }?.quantity == 2)
        #expect(entries.first { $0.condition == .damaged }?.quantity == 1)

        // The card's total spans them.
        #expect(try await rig.collection.copiesHeld(ofCard: card) == 3)
    }

    /// Evidence for R2.AC6: the total is what was recorded, multiplied out,
    /// and an unpriced lot adds nothing rather than dragging the figure down.
    @Test func totalSpendMultipliesPricePerCopyAndSkipsUnpricedLots() async throws {
        let rig = try CollectionFixture.seeded()
        let (cardID, printings) = try CollectionFixture.cardWithPrintings(2, in: rig)
        let card = CardIdentifier(cardID)

        try await rig.collection.recordPurchase(
            cardID: card, printID: printings[0], condition: .nearMint,
            quantity: 3, pricePerCopy: 2.0, acquiredAt: Self.bought)
        try await rig.collection.recordPurchase(
            cardID: card, printID: printings[1], condition: .lightlyPlayed,
            quantity: 2, pricePerCopy: 5.5, acquiredAt: nil)
        // Inherited, traded for, or simply never noted.
        try await rig.collection.addCopy(cardID: card, printID: printings[0], condition: .damaged)

        let totals = try await rig.collection.totals()
        #expect(totals.totalCopies == 6)
        #expect(totals.distinctCards == 1)
        #expect(abs(totals.recordedSpend - (3 * 2.0 + 2 * 5.5)) < 0.001,
                "atteso 17.0, ricevuto \(totals.recordedSpend)")
    }
}
