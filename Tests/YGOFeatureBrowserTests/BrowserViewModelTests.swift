import Foundation
import Testing
import YGOCore
@testable import YGOFeatureBrowser

@MainActor
@Suite("Browser view model")
struct BrowserViewModelTests {
    private func makeModel(
        artwork: any ArtworkProviding = NoArtworkAvailable()
    ) -> (BrowserViewModel, CountingSearchRepository) {
        let cards = SampleCards.make()
        let repository = CountingSearchRepository(cards: cards)
        var banProvider = StubBanStatusProvider()
        banProvider.cards = cards
        banProvider.statuses = [CardIdentifier(55144522): .forbidden]

        return (BrowserViewModel(
            repository: repository,
            counter: repository,
            artwork: artwork,
            banStatusProvider: banProvider,
            language: .italian), repository)
    }

    /// Evidence for R3.AC5: switching language re-reads what is already held.
    /// Both languages live on every card, so this costs no query and therefore
    /// works with no network.
    @Test func languageSwitchRePresentsTextWithoutAnyRequest() async throws {
        let (model, repository) = makeModel()
        await model.search()

        let queriesAfterSearch = await repository.searchCount
        #expect(queriesAfterSearch == 1)

        let italianTitles = model.items.map(\.title)
        #expect(italianTitles.contains("Anfora dell'Avidità"))
        #expect(italianTitles.contains("Mago Nero"))
        // The untranslated card reads in English even while Italian is chosen.
        #expect(italianTitles.contains("Blue-Eyes White Dragon"))

        model.setLanguage(.english)

        let englishTitles = model.items.map(\.title)
        #expect(englishTitles.contains("Pot of Greed"))
        #expect(englishTitles.contains("Dark Magician"))
        #expect(!englishTitles.contains("Anfora dell'Avidità"))

        // The decisive part: no further query was issued.
        let queriesAfterSwitch = await repository.searchCount
        #expect(queriesAfterSwitch == 1)

        // And switching back restores the Italian reading.
        model.setLanguage(.italian)
        #expect(model.items.map(\.title).contains("Anfora dell'Avidità"))
        let queriesAtEnd = await repository.searchCount
        #expect(queriesAtEnd == 1)
    }

    /// A card with no artwork shows a named placeholder, and that name has to
    /// follow the chosen language like any other title.
    @Test func placeholderNameFollowsTheChosenLanguage() async throws {
        let (model, _) = makeModel()
        await model.search()

        let italianItem = try #require(model.items.first { $0.id == CardIdentifier(55144522) })
        #expect(italianItem.artwork == .placeholder(cardName: "Anfora dell'Avidità"))

        model.setLanguage(.english)

        let englishItem = try #require(model.items.first { $0.id == CardIdentifier(55144522) })
        #expect(englishItem.artwork == .placeholder(cardName: "Pot of Greed"))
    }

    /// Stored artwork is used as-is and is not re-resolved by a language change.
    @Test func usesStoredArtworkWhenAvailable() async throws {
        let provider = StubArtworkProvider(
            paths: [ArtworkIdentifier(46986414): "/tmp/ygo/46986414.jpg"])
        let (model, _) = makeModel(artwork: provider)
        await model.search()

        let item = try #require(model.items.first { $0.id == CardIdentifier(46986414) })
        #expect(item.artwork == .stored(path: "/tmp/ygo/46986414.jpg"))

        model.setLanguage(.english)
        let afterSwitch = try #require(model.items.first { $0.id == CardIdentifier(46986414) })
        #expect(afterSwitch.artwork == .stored(path: "/tmp/ygo/46986414.jpg"))
    }

    /// Nothing found and still searching are separate states, so an empty grid
    /// is never mistaken for one that has not filled yet.
    @Test func reportsNoMatchesDistinctlyFromSearching() async throws {
        let repository = CountingSearchRepository(cards: [])
        let model = BrowserViewModel(
            repository: repository,
            counter: repository,
            artwork: NoArtworkAvailable(),
            banStatusProvider: StubBanStatusProvider())

        #expect(model.state == .idle)
        await model.search()
        #expect(model.state == .noMatches)
        #expect(model.items.isEmpty)
    }
}
