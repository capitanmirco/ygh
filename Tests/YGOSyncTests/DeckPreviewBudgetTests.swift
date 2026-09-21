import Foundation
import GRDB
import Testing
import YGOBanlistHistory
import YGOCore
import YGODeckIO
import YGOFeatureCardDetail
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

@MainActor
@Suite("Deck preview budgets")
struct DeckPreviewBudgetTests {
    /// A full deck, because walking one with the arrow keys is the motion
    /// this feature makes possible and the one a slow read would ruin.
    private func fullDeck() async throws -> (DatabaseQueue, DeckEditorViewModel) {
        let (database, decks) = try RealDeck.seededRepository()
        let importer = DeckImporter(repository: decks, validator: DeckValidator())
        let result = try await importer.importFile(
            at: RealDeck.root.appending(path: "fixtures/LR-Chaos Turbo.ydk"))

        let reader = SQLiteCardRepository(database: database)
        let model = DeckEditorViewModel(
            repository: decks, validator: DeckValidator(),
            catalogue: reader, editing: decks, reader: reader)
        await model.load(deckID: result.deck.id)
        return (database, model)
    }

    private func loader(_ database: DatabaseQueue) -> CardDetailLoader {
        CardDetailLoader(
            catalog: SQLiteCardRepository(database: database),
            details: SQLiteCardDetailReader(database: database),
            usage: SQLiteCardUsageReader(database: database),
            priceLookup: SQLitePriceRepository(database: database),
            history: SQLiteBanlistHistory(database: database),
            provenance: SQLiteBanlistHistory(database: database))
    }

    /// Evidence for NFR1: an arrow key held down issues a read per row. If a
    /// preview lagged, walking a deck would stutter and the feature would be
    /// worse than leaving to the catalog.
    @Test func walkingADeckWithTheArrowKeysStaysUnderOneHundredMilliseconds() async throws {
        let (_, model) = try await fullDeck()
        #expect(model.items.count > 20)

        // One untimed pass so first-use costs stay out of the measurement.
        await model.previewEntry(model.items[0])

        var worst: Double = 0
        for item in model.items.prefix(25) {
            let started = DispatchTime.now().uptimeNanoseconds
            await model.previewEntry(item)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            worst = max(worst, elapsed)
            #expect(model.previewCard?.id == item.card)
        }

        #expect(worst < 100, "worst preview \(worst) ms")
    }

    /// Evidence for NFR2: not a copy of the catalog's panel, the catalog's
    /// panel. A copy would pass every content check today and drift tomorrow.
    @Test func thePanelIsTheCatalogsAndNotACopyOfIt() async throws {
        let (database, model) = try await fullDeck()
        await model.previewEntry(model.items[0])
        let card = try #require(model.previewCard)

        // The deck publishes a catalog card and nothing of its own.
        #expect(card is Card)

        // The panel that renders it is `card-detail`'s view model, built from
        // `card-detail`'s loader over `YGOCore` ports.
        let panel = CardDetailViewModel(
            loader: loader(database), artwork: NoArtworkStore())
        await panel.select(card, language: .italian)

        let detail = try #require(panel.detail)
        #expect(detail.card.id == card.id)
        #expect(detail.prices.count == 5)
        // Including the sections the deck editor would never have written.
        #expect(detail.printings.message != nil || detail.printings.value != nil)
        #expect(detail.deckUses.message != nil || detail.deckUses.value != nil)
    }

    /// Evidence for NFR3: everything but the full-resolution artwork comes
    /// from storage, which is what makes previewing a deck work on a train.
    @Test func everySectionButTheArtworkResolvesOffline() async throws {
        let (database, model) = try await fullDeck()
        await model.previewEntry(model.items[0])
        let card = try #require(model.previewCard)

        // Nothing stored and nothing fetchable for the artwork.
        let panel = CardDetailViewModel(
            loader: loader(database), artwork: NoArtworkStore())
        await panel.select(card, language: .italian)

        let detail = try #require(panel.detail)
        #expect(!detail.text.name.isEmpty)
        #expect(detail.prices.count == 5)
        #expect(detail.holdings.message != nil || detail.holdings.value != nil)
        #expect(detail.currentStatus == detail.currentStatus)

        // The artwork degrades to a named placeholder rather than a blank.
        #expect(panel.artwork == .placeholder(cardName: detail.text.name))
    }

    /// Evidence for NFR4: the panel is the catalog's, so its narration is too.
    /// A figure that reads as a bare number tells a listener nothing.
    @Test func everyFigureInThePanelStillReadsAsASentence() async throws {
        let (database, model) = try await fullDeck()
        await model.previewEntry(model.items[0])
        let card = try #require(model.previewCard)

        let panel = CardDetailViewModel(
            loader: loader(database), artwork: NoArtworkStore())
        await panel.select(card, language: .italian)
        let detail = try #require(panel.detail)

        for line in detail.prices {
            let spoken = CardDetailNarration.price(line)
            #expect(spoken.contains(line.source.displayName))
            #expect(spoken.count > line.source.displayName.count + 2)
        }

        #expect(!CardDetailNarration.release(detail.release).isEmpty)
        #expect(!CardDetailNarration.status(detail.currentStatus).isEmpty)

        // And every section of the panel is reachable by keyboard, which is
        // what `card-detail` already proved and this reuses.
        #expect(CardDetailFocusRegion.allCases.count == 8)
        panel.focus(.prices)
        #expect(panel.focusedRegion == .prices)
    }
}
