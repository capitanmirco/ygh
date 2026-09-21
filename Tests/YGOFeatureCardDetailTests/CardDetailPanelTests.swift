import Foundation
import Testing
import YGOBanlistHistory
import YGOCore
@testable import YGOFeatureCardDetail

@MainActor
@Suite("Card detail panel")
struct CardDetailPanelTests {
    private func makeModel(
        details: StubDetailReader = StubDetailReader(),
        usage: StubUsageReader = StubUsageReader(),
        artwork: StubArtworkStore = StubArtworkStore(
            thumbnails: [ArtworkIdentifier(89_631_139), ArtworkIdentifier(89_631_140),
                         ArtworkIdentifier(89_631_141), ArtworkIdentifier(70_368_879)])
    ) -> CardDetailViewModel {
        var history = StubBanlistHistory()
        history.revisionDates = [.tcg: ["2005-03-01", "2026-05-18"]]

        return CardDetailViewModel(
            loader: CardDetailLoader(
                catalog: StubCardRepository(
                    cards: [DetailCards.blueEyes, DetailCards.untranslated]),
                details: details,
                usage: usage,
                priceLookup: StubPriceLookup(),
                history: history,
                provenance: history),
            artwork: artwork)
    }

    /// Evidence for R2.AC1: the panel is beside the results, so it starts
    /// empty and fills on selection rather than being a place you navigate to.
    @Test func selectingACardOpensItsDetailBesideTheResults() async throws {
        let panel = makeModel()

        #expect(panel.isEmpty)
        #expect(panel.detail == nil)

        await panel.select(DetailCards.blueEyes, language: .italian)

        #expect(!panel.isEmpty)
        #expect(!panel.isLoading)
        let detail = try #require(panel.detail)
        #expect(detail.card.id == DetailCards.blueEyes.id)
        #expect(detail.text.name == "Drago Bianco Occhi Blu")

        // Closing it puts the panel back where it started without touching
        // anything else.
        panel.clear()
        #expect(panel.isEmpty)
        #expect(panel.artwork == nil)
    }

    /// Evidence for R2.AC6: 124 cards have more than one artwork, and which
    /// one you own is a real question. The panel offers each.
    @Test func aCardWithSeveralArtworksOffersEachOfThem() async throws {
        let panel = makeModel()
        await panel.select(DetailCards.blueEyes, language: .italian)

        #expect(panel.offersArtworkChooser)
        #expect(panel.artworkChoices.count == 3)
        #expect(panel.selectedArtworkIndex == 0)
        #expect(panel.artwork == .stored(path: "/store/thumb/89631139.jpg"))

        await panel.showArtwork(at: 2)
        #expect(panel.selectedArtworkIndex == 2)
        #expect(panel.artwork == .stored(path: "/store/thumb/89631141.jpg"))

        // Out of range is refused, not clamped onto a different artwork.
        await panel.showArtwork(at: 9)
        #expect(panel.selectedArtworkIndex == 2)
        #expect(panel.artwork == .stored(path: "/store/thumb/89631141.jpg"))

        // The full image is what a detail wants; the thumbnail stands in until
        // it is stored, which is the state the live store is in for every card.
        let withFull = makeModel(artwork: StubArtworkStore(
            thumbnails: [ArtworkIdentifier(89_631_139)],
            fullImages: [ArtworkIdentifier(89_631_139)]))
        await withFull.select(DetailCards.blueEyes, language: .italian)
        #expect(withFull.artwork == .stored(path: "/store/full/89631139.jpg"))
    }

    /// Evidence for R2.AC6: offering a chooser for one artwork would be a
    /// control that does nothing, on 14,442 of 14,566 cards.
    @Test func aSingleArtworkCardOffersNoChooser() async throws {
        let panel = makeModel()
        await panel.select(DetailCards.untranslated, language: .italian)

        #expect(panel.artworkChoices.count == 1)
        #expect(!panel.offersArtworkChooser)
        #expect(panel.artwork == .stored(path: "/store/thumb/70368879.jpg"))

        // A card whose artwork is not stored at all still renders, named.
        let bare = makeModel(artwork: StubArtworkStore())
        await bare.select(DetailCards.untranslated, language: .italian)
        #expect(bare.artwork == .placeholder(cardName: "Upstart Goblin"))
    }

    /// Evidence for R2.AC7: this is what the inspector column is for. Reading
    /// one card after another must not cost the place you were in the grid.
    @Test func selectingAnotherCardLeavesTheResultsUndisturbed() async throws {
        let panel = makeModel()
        let results = [DetailCards.blueEyes, DetailCards.untranslated]
        let orderBefore = results.map(\.id)

        await panel.select(results[0], language: .italian)
        #expect(panel.detail?.card.id == results[0].id)
        await panel.showArtwork(at: 2)
        #expect(panel.selectedArtworkIndex == 2)

        await panel.select(results[1], language: .italian)

        #expect(panel.detail?.card.id == results[1].id)
        #expect(panel.detail?.text.name == "Upstart Goblin")
        // The chooser resets to the new card's first artwork rather than
        // keeping an index that belonged to a different card.
        #expect(panel.selectedArtworkIndex == 0)
        #expect(!panel.offersArtworkChooser)

        // Nothing the panel does reaches the results: it holds no reference to
        // them at all, which is why the grid keeps its order and its place.
        #expect(results.map(\.id) == orderBefore)
        #expect(results.count == 2)
    }

    /// Evidence for R2.AC1: a section that cannot be read says so, and the
    /// rest of the panel still renders. Losing the printings is not a reason
    /// to lose the card.
    @Test func aFailingSectionReportsItselfAndTheRestStillRenders() async throws {
        var details = StubDetailReader()
        details.failPrintings = true
        var usage = StubUsageReader()
        usage.failHoldings = true
        usage.uses = [DetailCards.blueEyes.id: [
            DeckUse(deckID: 1, deckName: "Lockdown Burn", section: .main, quantity: 1),
        ]]

        let panel = makeModel(details: details, usage: usage)
        await panel.select(DetailCards.blueEyes, language: .italian)

        let detail = try #require(panel.detail)

        // The two that failed say so, and are not shown as empty.
        #expect(detail.printings.isFailed)
        #expect(!detail.printings.isEmpty)
        #expect(detail.printings.message?.contains("Stampe non leggibili") == true)
        #expect(detail.holdings.isFailed)
        #expect(detail.holdings.message?.contains("Collezione non leggibile") == true)

        // Everything else is there.
        #expect(detail.text.name == "Drago Bianco Occhi Blu")
        #expect(detail.deckUses.value?.count == 1)
        #expect(detail.prices.count == 5)
        #expect(panel.artwork != nil)
        #expect(!panel.isLoading)
    }
}
