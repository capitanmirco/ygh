import Foundation
import GRDB
import Testing
import YGOCore
import YGODeckIO
import YGOFeatureCollection
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOPricing
import YGOValidation
@testable import YGOSync

/// The screens were built on engines that were already proven, but the
/// affordances themselves - searching the catalog, recording a copy, changing
/// a count, adding to a deck - were new code and are covered here.
@MainActor
@Suite("Editing affordances")
struct EditingAffordanceTests {
    /// Adding to a deck from the catalog places the card by its frame, so a
    /// card the editor puts somewhere is never then reported for being there.
    @Test func addingFromTheCatalogPlacesACardWhereTheValidatorExpects() async throws {
        let rig = try CollectionFixture.seeded()
        let deck = try await rig.decks.createDeck(name: "Nuovo", format: .goat)

        let model = DeckEditorViewModel(
            repository: rig.decks, validator: DeckValidator(),
            catalogue: SQLiteCardRepository(database: rig.database))
        await model.load(deckID: deck.id)
        #expect(model.canAddCards)
        #expect(model.items.isEmpty)

        // Search finds cards, and an empty query finds none.
        model.catalogueQuery = "  "
        await model.searchCatalogue()
        #expect(model.candidates.isEmpty)

        let fusion = try #require(rig.cards.first { $0.frameType == "fusion" })
        model.catalogueQuery = try #require(fusion.name.split(separator: " ")
            .map(String.init).max(by: { $0.count < $1.count }))
        await model.searchCatalogue()
        #expect(!model.candidates.isEmpty)

        let card = try #require(model.candidates.first { $0.frame.belongsInExtraDeck })
        await model.add(card)

        let loaded = try #require(try await rig.decks.deck(with: deck.id))
        #expect(loaded.count(in: .extra) == 1, "una Fusione va nell'Extra Deck")
        #expect(loaded.count(in: .main) == 0)

        // And the validator agrees it belongs there.
        let violations = DeckValidator().violations(
            in: loaded, using: try await rig.decks.cardIndex(for: loaded))
        #expect(!violations.contains {
            if case .misplacedCard = $0 { return true } else { return false }
        }, "la carta collocata dall'editor non deve poi risultare fuori posto")

        // A main-deck card lands in the main section.
        if let mainDeckCard = model.candidates.first(where: { !$0.frame.belongsInExtraDeck }) {
            await model.add(mainDeckCard)
            let after = try #require(try await rig.decks.deck(with: deck.id))
            #expect(after.count(in: .main) == 1, "una carta non-Extra va nel deck principale")
            #expect(after.totalCount == 2)
        }
    }

    /// Recording, adjusting and removing copies from the collection screen.
    @Test func recordingAndAdjustingCopiesFromTheCollectionScreen() async throws {
        let rig = try CollectionFixture.seeded()
        let model = CollectionViewModel(
            reader: rig.collection, writer: rig.collection,
            catalogue: SQLiteCardRepository(database: rig.database))

        await model.reload()
        #expect(model.canEdit)
        #expect(model.items.isEmpty)

        let card = try #require(rig.cards.first)
        model.catalogueQuery = try #require(card.name.split(separator: " ")
            .map(String.init).max(by: { $0.count < $1.count }))
        await model.searchCatalogue()
        #expect(!model.candidates.isEmpty)

        let chosen = try #require(model.candidates.first)
        await model.recordCopy(of: chosen.id)
        await model.recordCopy(of: chosen.id)

        #expect(model.items.count == 1)
        #expect(model.items[0].copies == 2)
        #expect(model.totals?.totalCopies == 2)

        // A count can be set outright, and zero removes the lot.
        await model.setCopies(5, of: chosen.id)
        #expect(model.items.first?.copies == 5)
        await model.setCopies(0, of: chosen.id)
        #expect(model.items.isEmpty)
    }

    /// Removal asks before it acts, because hand-entered copies are recoverable
    /// from nowhere.
    @Test func removingCopiesRequiresConfirmationFirst() async throws {
        let rig = try CollectionFixture.seeded()
        let model = CollectionViewModel(
            reader: rig.collection, writer: rig.collection,
            catalogue: SQLiteCardRepository(database: rig.database))

        let card = CardIdentifier(try #require(rig.cards.first).id)
        await model.recordCopy(of: card)
        await model.recordCopy(of: card)
        #expect(model.items.first?.copies == 2)

        // Asking does not remove.
        model.requestRemoval(of: card)
        #expect(model.pendingRemoval == card)
        await model.reload()
        #expect(model.items.first?.copies == 2)

        // Changing one's mind does not remove either.
        model.cancelRemoval()
        await model.removeConfirmedCard()
        await model.reload()
        #expect(model.items.first?.copies == 2, "annullare non deve cancellare")

        // Only a confirmed removal does.
        model.requestRemoval(of: card)
        await model.removeConfirmedCard()
        #expect(model.items.isEmpty)
        #expect(model.pendingRemoval == nil)
    }

    /// A read-only collection screen cannot change anything, which is what the
    /// optional writer is for.
    @Test func aReadOnlyScreenCannotChangeTheCollection() async throws {
        let rig = try CollectionFixture.seeded()
        let card = CardIdentifier(try #require(rig.cards.first).id)
        try await rig.collection.addCopy(cardID: card, printID: nil)

        let readOnly = CollectionViewModel(reader: rig.collection)
        await readOnly.reload()
        #expect(!readOnly.canEdit)
        #expect(readOnly.items.count == 1)

        await readOnly.recordCopy(of: card)
        await readOnly.setCopies(99, of: card)
        readOnly.requestRemoval(of: card)
        await readOnly.removeConfirmedCard()

        await readOnly.reload()
        #expect(readOnly.items.first?.copies == 1, "senza writer nulla deve cambiare")

        // And it cannot search for cards to add either.
        readOnly.catalogueQuery = "dragon"
        await readOnly.searchCatalogue()
        #expect(readOnly.candidates.isEmpty)
    }

    /// The valuation reads rarity from the printing and the binder from the
    /// location, which is what makes its breakdowns non-empty.
    @Test func valuationRowsCarryRarityAndLocation() async throws {
        let rig = try CollectionFixture.seeded()
        let (cardID, printings) = try CollectionFixture.cardWithPrintings(1, in: rig)
        let binder = try await rig.collection.createLocation(named: "Raccoglitore A")

        try await rig.collection.addCopy(
            cardID: CardIdentifier(cardID), printID: printings[0], locationID: binder)
        try await rig.collection.addCopy(cardID: CardIdentifier(cardID), printID: nil)

        let rows = try await rig.collection.valuationRows()
        #expect(rows.count == 2)

        let withPrinting = try #require(rows.first { $0.location != nil })
        #expect(withPrinting.rarity != nil, "la rarità deve arrivare dalla stampa")
        #expect(withPrinting.location == "Raccoglitore A")

        let without = try #require(rows.first { $0.location == nil })
        #expect(without.rarity == nil, "una copia senza stampa non ha rarità")

        // Names come through for labelling.
        let names = try await rig.collection.cardNames(for: [CardIdentifier(cardID)])
        #expect(names[CardIdentifier(cardID)]?.isEmpty == false)
    }
}
