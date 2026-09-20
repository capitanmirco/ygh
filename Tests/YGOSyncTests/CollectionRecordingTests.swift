import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOSync

@Suite("Collection recording")
struct CollectionRecordingTests {
    /// Evidence for R1.AC1: a copy lands on the printing it was recorded
    /// against and nowhere else.
    @Test func recordingAPrintingRaisesOnlyItsOwnCount() async throws {
        let rig = try CollectionFixture.seeded()
        let (cardID, printings) = try CollectionFixture.cardWithPrintings(2, in: rig)
        let first = printings[0]
        let second = printings[1]

        for _ in 0..<3 {
            try await rig.collection.addCopy(cardID: CardIdentifier(cardID), printID: first)
        }

        #expect(try await rig.collection.copiesHeld(ofPrinting: first) == 3)
        #expect(try await rig.collection.copiesHeld(ofPrinting: second) == 0)

        // Three copies of one printing are one lot, not three rows.
        let entries = try await rig.collection.entries(forCard: CardIdentifier(cardID))
        #expect(entries.count == 1)
        #expect(entries[0].quantity == 3)
    }

    /// Evidence for R1.AC2: the last copy takes its lot with it.
    @Test func removingTheLastCopyDropsTheEntry() async throws {
        let rig = try CollectionFixture.seeded()
        let (cardID, printings) = try CollectionFixture.cardWithPrintings(1, in: rig)
        let printID = printings[0]

        try await rig.collection.addCopy(cardID: CardIdentifier(cardID), printID: printID)
        try await rig.collection.addCopy(cardID: CardIdentifier(cardID), printID: printID)
        try await rig.collection.removeCopy(cardID: CardIdentifier(cardID), printID: printID)

        #expect(try await rig.collection.copiesHeld(ofPrinting: printID) == 1)

        try await rig.collection.removeCopy(cardID: CardIdentifier(cardID), printID: printID)
        #expect(try await rig.collection.entries().isEmpty,
                "l'ultima copia deve togliere il lotto, non lasciarlo a zero")

        // Removing what is not held changes nothing.
        try await rig.collection.removeCopy(cardID: CardIdentifier(cardID), printID: printID)
        #expect(try await rig.collection.entries().isEmpty)
    }

    /// Evidence for R1.AC3: a count can be stated outright, and zero means gone.
    @Test func settingACountStoresItAndZeroRemovesTheEntry() async throws {
        let rig = try CollectionFixture.seeded()
        let (cardID, printings) = try CollectionFixture.cardWithPrintings(1, in: rig)
        let printID = printings[0]

        try await rig.collection.addCopy(cardID: CardIdentifier(cardID), printID: printID)
        try await rig.collection.setQuantity(4, cardID: CardIdentifier(cardID), printID: printID)
        #expect(try await rig.collection.copiesHeld(ofPrinting: printID) == 4)

        // Setting a count where nothing was held creates the lot. A second
        // printing of the same card is deliberately used: the two lots must
        // not interfere with each other.
        let secondPrinting = try #require(
            try CollectionFixture.cardWithPrintings(2, in: rig).1.dropFirst().first)
        try await rig.collection.setQuantity(
            2, cardID: CardIdentifier(cardID), printID: secondPrinting)
        #expect(try await rig.collection.copiesHeld(ofPrinting: secondPrinting) == 2)

        // Zeroing one lot removes that lot and leaves the other standing.
        try await rig.collection.setQuantity(0, cardID: CardIdentifier(cardID), printID: printID)
        #expect(try await rig.collection.copiesHeld(ofPrinting: printID) == 0)
        #expect(try await rig.collection.copiesHeld(ofPrinting: secondPrinting) == 2)
        #expect(try await rig.collection.copiesHeld(ofCard: CardIdentifier(cardID)) == 2)
    }

    /// Evidence for R1.AC6: a printing the catalog does not hold cannot enter
    /// the collection, so a recorded copy always points at something real.
    @Test func refusesAPrintingTheCatalogDoesNotHold() async throws {
        let rig = try CollectionFixture.seeded()
        let (cardID, _) = try CollectionFixture.cardWithPrintings(1, in: rig)

        await #expect(throws: CollectionError.printingNotInCatalog(999_999)) {
            try await rig.collection.addCopy(
                cardID: CardIdentifier(cardID), printID: 999_999)
        }

        await #expect(throws: CollectionError.cardNotInCatalog(CardIdentifier(999_999_999))) {
            try await rig.collection.addCopy(
                cardID: CardIdentifier(999_999_999), printID: nil)
        }

        #expect(try await rig.collection.entries().isEmpty)
    }

    /// Evidence for R1.AC4: the 552 cards with no printing are still ownable.
    @Test func recordsACardThatHasNoPrintingInTheCatalog() async throws {
        let rig = try CollectionFixture.seeded()
        // Any card, recorded against no printing at all.
        let cardID = CardIdentifier(rig.cards[0].id)

        try await rig.collection.addCopy(cardID: cardID, printID: nil)
        try await rig.collection.addCopy(cardID: cardID, printID: nil)

        let entries = try await rig.collection.entries(forCard: cardID)
        #expect(entries.count == 1)
        #expect(entries[0].printID == nil)
        #expect(entries[0].quantity == 2)
        #expect(try await rig.collection.copiesHeld(ofCard: cardID) == 2)
    }

    /// Evidence for R1.AC5: a card's total spans every printing it was
    /// recorded under, including copies recorded against no printing.
    @Test func countsACardsCopiesAcrossAllOfItsPrintings() async throws {
        let rig = try CollectionFixture.seeded()
        let (cardID, printings) = try CollectionFixture.cardWithPrintings(2, in: rig)
        let card = CardIdentifier(cardID)

        try await rig.collection.addCopy(cardID: card, printID: printings[0])
        try await rig.collection.addCopy(cardID: card, printID: printings[0])
        try await rig.collection.addCopy(cardID: card, printID: printings[1])
        try await rig.collection.addCopy(cardID: card, printID: nil)

        #expect(try await rig.collection.copiesHeld(ofCard: card) == 4)
        #expect(try await rig.collection.copiesHeld(ofPrinting: printings[0]) == 2)
        #expect(try await rig.collection.copiesHeld(ofPrinting: printings[1]) == 1)

        let byCard = try await rig.collection.copiesByCard()
        #expect(byCard[card] == 4)
    }
}
