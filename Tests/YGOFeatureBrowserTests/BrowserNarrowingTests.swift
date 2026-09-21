import Foundation
import Testing
import YGOCore
@testable import YGOFeatureBrowser

@MainActor
@Suite("Browser narrowing")
struct BrowserNarrowingTests {
    private func model(
        repository: any CardSearching & CardSearchCounting
    ) -> BrowserViewModel {
        BrowserViewModel(
            repository: repository,
            counter: repository,
            artwork: NoArtworkAvailable(),
            banStatusProvider: StubBanStatusProvider(statuses: [:], cards: SampleCards.make()),
            language: .italian)
    }

    /// Evidence for R1.AC1: the catalog is there to be looked through, not
    /// only queried. An unnarrowed search costs 3.9 ms, so opening on an
    /// instruction to type is withholding something already paid for.
    @Test func opensShowingCardsWithoutBeingAsked() async throws {
        let repository = CountingSearchRepository(cards: SampleCards.make())
        let browser = model(repository: repository)

        #expect(browser.state == .idle)
        #expect(browser.queryText.isEmpty)

        await browser.start()

        #expect(browser.items.count == 3)
        if case .results = browser.state {} else {
            Issue.record("expected results, got \(browser.state)")
        }
        // The query that produced them asked for nothing in particular.
        #expect(browser.queryText.isEmpty)
    }

    /// Evidence for R1.AC2: emptying the field returns to the whole catalog,
    /// not to a blank screen. Clearing a search is how you start looking
    /// again.
    @Test func clearingTheQueryReturnsToTheWholeCatalog() async throws {
        let all = SampleCards.make()
        let repository = GatedSearchRepository(cards: [
            "": all,
            "dark": [all[2]],
        ])
        let browser = model(repository: repository)

        await browser.start()
        #expect(browser.items.count == 3)

        browser.queryText = "dark"
        await browser.queryChanged()
        #expect(browser.items.count == 1)

        browser.queryText = ""
        await browser.queryChanged()
        #expect(browser.items.count == 3)
        #expect(browser.matchCount == 3)
    }

    /// Evidence for R1.AC3: results follow the text without a submit. Each
    /// keystroke is its own narrowing.
    @Test func narrowsOnEveryChangeWithoutSubmitting() async throws {
        let all = SampleCards.make()
        let repository = GatedSearchRepository(cards: [
            "": all,
            "d": [all[1], all[2]],
            "da": [all[2]],
            "dar": [all[2]],
        ])
        let browser = model(repository: repository)
        await browser.start()

        var counts: [Int] = []
        for text in ["d", "da", "dar"] {
            browser.queryText = text
            await browser.queryChanged()
            counts.append(browser.items.count)
        }

        #expect(counts == [2, 1, 1])
        #expect(browser.items.first?.title == "Mago Nero")
    }

    /// Evidence for R1.AC3: typing outruns querying, and an answer for text
    /// the user has moved past must not land on the grid. Here the load for
    /// "d" is held open, the user types on to "dar", and only then is "d"
    /// released.
    @Test func aSupersededResultNeverReachesTheGrid() async throws {
        let all = SampleCards.make()
        let repository = GatedSearchRepository(cards: [
            "": all,
            "d": [all[0], all[1]],
            "dar": [all[2]],
        ])
        let browser = model(repository: repository)
        await browser.start()

        await repository.hold("d")

        browser.queryText = "d"
        let stale = Task { await browser.queryChanged() }
        // Wait until the held search has actually reached its gate. Yielding
        // and hoping would make this test pass for the wrong reason: a stale
        // load that finished early proves nothing about discarding it.
        while await !repository.isWaiting("d") { await Task.yield() }

        browser.queryText = "dar"
        await browser.queryChanged()
        #expect(browser.items.count == 1)
        #expect(browser.items.first?.title == "Mago Nero")

        // The abandoned load now finishes. It must change nothing.
        await repository.release("d")
        await stale.value

        #expect(browser.items.count == 1)
        #expect(browser.items.first?.title == "Mago Nero")
        #expect(browser.matchCount == 1)
    }

    /// Evidence for R1.AC6: filters narrow on their own. Browsing a format
    /// without typing anything is a normal way to look through a catalog.
    @Test func filtersAloneNarrowWithNoQueryText() async throws {
        let repository = CountingSearchRepository(cards: SampleCards.make())
        let browser = model(repository: repository)
        await browser.start()
        let before = browser.items.count

        var filters = CardFilters()
        filters.format = .edison
        browser.filters = filters
        await browser.filtersChanged()

        // The stub answers every query with its whole set, so what this proves
        // is that the filter reached a query at all, and with no text.
        let issued = await repository.lastQuery
        #expect(issued?.filters.format == .edison)
        #expect(issued?.normalizedText == nil)
        #expect(browser.items.count == before)
    }

    /// Evidence for R1.AC7: nothing found is an answer. An empty grid that
    /// might still be filling is not.
    @Test func noMatchesIsASettledAnswerNotAnEmptyGrid() async throws {
        let empty = CountingSearchRepository(cards: [])
        let browser = model(repository: empty)

        await browser.start()
        #expect(browser.state == .noMatches)
        #expect(browser.items.isEmpty)
        #expect(browser.matchCount == 0)

        // A query that fails outright reads the same way: settled, not busy.
        let broken = model(repository: FailingSearchRepository())
        await broken.start()
        #expect(broken.state == .noMatches)
        #expect(broken.state != .searching)
    }
}
