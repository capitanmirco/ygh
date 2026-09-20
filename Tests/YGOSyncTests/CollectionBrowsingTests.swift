import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOSync

@Suite("Collection browsing")
struct CollectionBrowsingTests {
    /// Evidence for R4.AC1: distinct cards and total copies are different
    /// numbers, and a collector cares about both.
    @Test func reportsDistinctCardsAndTotalCopies() async throws {
        let rig = try CollectionFixture.seeded()
        let (firstCard, firstPrintings) = try CollectionFixture.cardWithPrintings(1, in: rig)
        let second = try #require(rig.cards.first { $0.id != firstCard })
        let secondPrintings = try CollectionFixture.printings(of: second.id, in: rig.database)

        #expect(try await rig.collection.totals().isEmpty)

        for _ in 0..<3 {
            try await rig.collection.addCopy(
                cardID: CardIdentifier(firstCard), printID: firstPrintings[0])
        }
        try await rig.collection.addCopy(
            cardID: CardIdentifier(second.id), printID: secondPrintings.first)

        let totals = try await rig.collection.totals()
        #expect(totals.distinctCards == 2)
        #expect(totals.totalCopies == 4)
        #expect(!totals.isEmpty)
    }

    /// Evidence for R4.AC2: this searches the collection, not the catalog.
    /// A card that exists but is not owned must not appear.
    @Test func searchReturnsOwnedCardsOnly() async throws {
        let rig = try CollectionFixture.seeded()
        let (ownedID, printings) = try CollectionFixture.cardWithPrintings(1, in: rig)
        let owned = try #require(rig.cards.first { $0.id == ownedID })
        let unowned = try #require(rig.cards.first { $0.id != ownedID })

        try await rig.collection.addCopy(cardID: CardIdentifier(ownedID), printID: printings[0])

        let all = try await rig.collection.ownedCards()
        #expect(all.map(\.card) == [CardIdentifier(ownedID)])
        #expect(all[0].copies == 1)

        // Searching by a distinctive part of the owned card's name finds it.
        let word = try #require(owned.name.split(separator: " ")
            .map(String.init).max(by: { $0.count < $1.count }))
        let found = try await rig.collection.ownedCards(named: word)
        #expect(found.contains { $0.card == CardIdentifier(ownedID) })

        // The unowned card is in the catalog and still must not come back.
        let unownedWord = try #require(unowned.name.split(separator: " ")
            .map(String.init).max(by: { $0.count < $1.count }))
        let missing = try await rig.collection.ownedCards(named: unownedWord)
        #expect(!missing.contains { $0.card == CardIdentifier(unowned.id) },
                "una carta non posseduta non deve comparire nella collezione")

        // A name full of wildcards must not match everything.
        #expect(try await rig.collection.ownedCards(named: "%").isEmpty)
    }

    /// Evidence for R4.AC5: nothing recorded and nothing matching are
    /// different answers, and neither is a count the interface has to read.
    @Test func emptyCollectionIsDistinctFromAFilterMatchingNothing() async throws {
        let rig = try CollectionFixture.seeded()
        var filters = CollectionFilters()

        #expect(try await rig.collection.listing(matching: filters) == .empty)

        let (cardID, printings) = try CollectionFixture.cardWithPrintings(1, in: rig)
        try await rig.collection.addCopy(
            cardID: CardIdentifier(cardID), printID: printings[0], condition: .nearMint)

        // Now something is recorded, so an unmatched filter is a different case.
        filters.conditions = [.damaged]
        #expect(try await rig.collection.listing(matching: filters) == .noMatches)

        filters.conditions = [.nearMint]
        let listing = try await rig.collection.listing(matching: filters)
        guard case .entries(let entries) = listing else {
            Issue.record("attese voci, ricevuto \(listing)"); return
        }
        #expect(entries.count == 1)
    }
}
