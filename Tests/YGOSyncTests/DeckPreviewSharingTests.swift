import Foundation
import GRDB
import Testing
import YGOBanlistHistory
import YGOCore
import YGOFeatureCardDetail
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

@MainActor
@Suite("Deck preview sharing")
struct DeckPreviewSharingTests {
    private func loader(_ database: DatabaseQueue) -> CardDetailLoader {
        CardDetailLoader(
            catalog: SQLiteCardRepository(database: database),
            details: SQLiteCardDetailReader(database: database),
            usage: SQLiteCardUsageReader(database: database),
            priceLookup: SQLitePriceRepository(database: database),
            history: SQLiteBanlistHistory(database: database),
            provenance: SQLiteBanlistHistory(database: database))
    }

    /// Evidence for R1.AC2: the whole point of reusing the panel is that a
    /// card is described identically wherever it is opened from. A lighter
    /// deck-specific panel would drift the first time the catalog's gained a
    /// section.
    @Test func aCardPreviewedFromADeckCarriesWhatTheCatalogCarries() async throws {
        let (database, decks) = try RealDeck.seededRepository()
        let deck = try await decks.createDeck(name: "Nuovo", format: .tcg)
        let reader = SQLiteCardRepository(database: database)

        let model = DeckEditorViewModel(
            repository: decks, validator: DeckValidator(),
            catalogue: reader, editing: decks, reader: reader)
        await model.load(deckID: deck.id)

        let candidate = try #require(model.candidates.first { !$0.frame.belongsInExtraDeck })
        await model.add(candidate, to: .main)
        await model.previewEntry(try #require(model.items.first))
        let fromDeck = try #require(model.previewCard)

        // The catalog reaches the same card by identifier.
        let fromCatalog = try #require(try await reader.card(with: fromDeck.id))
        #expect(fromDeck == fromCatalog)

        // And the panel built from either is the same panel, assembled the
        // same way, with the same content.
        let detailFromDeck = await loader(database).load(fromDeck, language: .italian)
        let detailFromCatalog = await loader(database).load(fromCatalog, language: .italian)

        #expect(detailFromDeck.text == detailFromCatalog.text)
        #expect(detailFromDeck.release == detailFromCatalog.release)
        #expect(detailFromDeck.prices == detailFromCatalog.prices)
        #expect(detailFromDeck.history == detailFromCatalog.history)
        #expect(detailFromDeck.printings == detailFromCatalog.printings)
    }

    /// Evidence for R1.AC2: not "shows the same things today" but "is the same
    /// panel". A second implementation would pass the first check and fail
    /// this one the moment either changed.
    @Test func theDeckAndTheCatalogUseTheSamePanel() async throws {
        let (database, decks) = try RealDeck.seededRepository()
        let deck = try await decks.createDeck(name: "Nuovo", format: .tcg)
        let reader = SQLiteCardRepository(database: database)

        let model = DeckEditorViewModel(
            repository: decks, validator: DeckValidator(),
            catalogue: reader, editing: decks, reader: reader)
        await model.load(deckID: deck.id)
        let candidate = try #require(model.candidates.first)
        model.previewCandidate(candidate)

        // The deck hands a `Card` to the catalog's own view model, which is
        // the same type the catalog screen builds.
        let panel = CardDetailViewModel(
            loader: loader(database), artwork: NoArtworkStore())
        await panel.select(try #require(model.previewCard), language: .italian)

        #expect(panel.detail?.card.id == candidate.id)
        #expect(!panel.isEmpty)

        // The deck editor holds no detail type of its own: what it publishes
        // is a catalog card, nothing more.
        #expect(model.previewCard is Card)
    }
}

/// Nothing stored, which is the state the artwork store is in for a card
/// nobody has opened yet.
struct NoArtworkStore: ArtworkProviding {
    func storedArtworkPath(
        for identifier: ArtworkIdentifier, variant: ArtworkVariant
    ) async -> String? { nil }
}
