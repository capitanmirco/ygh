import Foundation
import Testing
import YGOCore
@testable import YGOFeatureBrowser

/// These assert the contract the view binds to - the labels it applies and the
/// focus moves it forwards - rather than rendered pixels. Keeping that policy
/// in the model is what makes it assertable at all.
@MainActor
@Suite("Browser accessibility")
struct BrowserAccessibilityTests {
    private func searchedModel() async -> BrowserViewModel {
        let cards = SampleCards.make()
        var banProvider = StubBanStatusProvider()
        banProvider.cards = cards
        banProvider.statuses = [
            CardIdentifier(55144522): .forbidden,
            CardIdentifier(46986414): .semiLimited,
        ]

        let model = BrowserViewModel(
            repository: CountingSearchRepository(cards: cards),
            artwork: NoArtworkAvailable(),
            banStatusProvider: banProvider,
            language: .italian)
        await model.search()
        return model
    }

    /// Evidence for NFR6: every tile announces what it is, whether or not its
    /// artwork has arrived. Without this the grid is a wall of unlabelled
    /// images before the prefetch finishes, and permanently so offline.
    @Test func exposesNameAndCardTypeForEveryGridElement() async throws {
        let model = await searchedModel()
        #expect(model.items.count == 3)

        for item in model.items {
            let label = item.accessibilityLabel
            #expect(label.contains(item.title), "etichetta senza nome: \(label)")
            #expect(label.contains(item.subtitle), "etichetta senza tipo: \(label)")
            #expect(!label.isEmpty)

            // No tile here has artwork, and every one is still announced.
            guard case .placeholder = item.artwork else {
                Issue.record("atteso placeholder per \(item.title)")
                continue
            }
        }

        // A restriction is spoken, not conveyed by badge colour alone.
        let forbidden = try #require(model.items.first { $0.id == CardIdentifier(55144522) })
        #expect(forbidden.accessibilityLabel.contains("vietata"))
        let semiLimited = try #require(model.items.first { $0.id == CardIdentifier(46986414) })
        #expect(semiLimited.accessibilityLabel.contains("semi-limitata"))

        // So is the fact that a title fell back to English.
        let untranslated = try #require(model.items.first { $0.isUntranslated })
        #expect(untranslated.accessibilityLabel.contains("in inglese"))

        // An unrestricted card is not announced as restricted.
        let unrestricted = try #require(model.items.first { $0.banStatus == .unlimited })
        #expect(!unrestricted.accessibilityLabel.contains("vietata"))
        #expect(!unrestricted.accessibilityLabel.contains("limitata"))
    }

    /// Evidence for NFR6: the search field, the filter controls and the grid
    /// are all reachable with the keyboard alone, and the grid's own contents
    /// can be traversed without a pointer.
    @Test func reachesSearchFiltersAndGridByKeyboardAlone() async throws {
        let model = await searchedModel()

        // Focus starts where typing goes.
        #expect(model.focusedRegion == .searchField)

        // Moving forward reaches every region and returns, so none is stranded.
        var visited: [BrowserFocusRegion] = [model.focusedRegion]
        for _ in 0..<BrowserFocusRegion.allCases.count {
            model.advanceFocus()
            visited.append(model.focusedRegion)
        }
        #expect(Set(visited) == Set(BrowserFocusRegion.allCases))
        #expect(visited.last == .searchField, "il ciclo deve tornare al punto di partenza")

        // Moving backward works too, so a shift-tab is not a dead end.
        model.retreatFocus()
        #expect(model.focusedRegion == .grid)
        model.retreatFocus()
        #expect(model.focusedRegion == .filters)

        // Inside the grid every card is reachable by arrow movement.
        model.focusRegion(.grid)
        #expect(model.selectedIndex == 0)

        var reached: Set<CardIdentifier> = []
        for _ in 0..<model.items.count {
            let selected = try #require(model.selectedItem)
            reached.insert(selected.id)
            model.moveSelection(by: 1)
        }
        #expect(reached == Set(model.items.map(\.id)))

        // Selection stops at the ends rather than wrapping, so the edge of the
        // grid is perceptible without sight.
        model.moveSelection(by: 50)
        #expect(model.selectedIndex == model.items.count - 1)
        model.moveSelection(by: -50)
        #expect(model.selectedIndex == 0)
    }

    /// Selection survives a language change: the keyboard does not lose its
    /// place because the reader switched language.
    @Test func keepsSelectionAcrossLanguageChange() async throws {
        let model = await searchedModel()
        model.moveSelection(by: 2)
        let before = try #require(model.selectedItem).id

        model.setLanguage(.english)

        #expect(model.selectedIndex == 2)
        #expect(try #require(model.selectedItem).id == before)
    }
}
