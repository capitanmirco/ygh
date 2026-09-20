import Foundation
import Testing
@testable import YGOCore

@Suite("Collection model")
struct CollectionModelTests {
    /// Evidence for R2.AC1: the grades offered are the ones the market prices
    /// against, not a scale this application invented.
    @Test func offersTheFiveMarketConditionGrades() {
        #expect(CardCondition.allCases.count == 5)
        #expect(Set(CardCondition.allCases) == [
            .nearMint, .lightlyPlayed, .moderatelyPlayed, .heavilyPlayed, .damaged,
        ])

        // Ordered best first, which is how a collector reads them.
        #expect(CardCondition.byQuality.first == .nearMint)
        #expect(CardCondition.byQuality.last == .damaged)
        #expect(Set(CardCondition.byQuality) == Set(CardCondition.allCases))

        // Each carries the abbreviation a shop would use.
        #expect(CardCondition.nearMint.abbreviation == "NM")
        #expect(CardCondition.damaged.abbreviation == "DMG")
        #expect(Set(CardCondition.allCases.map(\.abbreviation)).count == 5)
        #expect(CardCondition.allCases.allSatisfy { !$0.italianName.isEmpty })
    }

    /// The stored form is what the database checks against, so a grade that
    /// cannot round-trip could not be read back after a restart.
    @Test func conditionRoundTripsThroughItsStoredForm() {
        for condition in CardCondition.allCases {
            #expect(CardCondition(rawValue: condition.rawValue) == condition)
        }
        #expect(CardCondition(rawValue: "mint") == nil)
        #expect(CardCondition.moderatelyPlayed.rawValue == "moderately_played")
    }

    /// A lot's cost is per copy multiplied out, and an unrecorded price stays
    /// unrecorded rather than becoming zero.
    @Test func lotCostMultipliesPricePerCopy() {
        let priced = CollectionEntry(
            id: 1, card: CardIdentifier(1), printID: 10,
            condition: .nearMint, quantity: 3, purchasePrice: 2.5)
        #expect(priced.lotCost == 7.5)

        let unpriced = CollectionEntry(
            id: 2, card: CardIdentifier(1), printID: 10,
            condition: .nearMint, quantity: 3)
        #expect(unpriced.lotCost == nil, "prezzo non registrato non è prezzo zero")
    }

    /// A card with no printing in the catalog is still a card someone owns.
    @Test func entryMayHaveNoPrinting() {
        let entry = CollectionEntry(
            id: 1, card: CardIdentifier(42), printID: nil,
            condition: .lightlyPlayed, quantity: 1)
        #expect(entry.printID == nil)
        #expect(entry.quantity == 1)
    }
}
