import Foundation
import Testing
import YGOCore
@testable import YGOFeatureBrowser

@MainActor
@Suite("Browser paging")
struct BrowserPagingTests {
    private func model(
        repository: any CardSearching & CardSearchCounting
    ) -> BrowserViewModel {
        BrowserViewModel(
            repository: repository,
            counter: repository,
            artwork: NoArtworkAvailable(),
            banStatusProvider: StubBanStatusProvider(statuses: [:], cards: []),
            language: .italian)
    }

    /// Evidence for R1.AC4: the two numbers are different and both are stated.
    /// "14.566 carte, mostrate 200" is an honest answer to "show me all the
    /// cards"; showing 200 and saying nothing is not.
    @Test func reportsHowManyMatchAndHowManyAreShown() async throws {
        let repository = PagingSearchRepository(cards: BulkCards.make(14_566))
        let browser = model(repository: repository)

        await browser.start()

        #expect(browser.matchCount == 14_566)
        #expect(browser.shownCount == 200)
        #expect(browser.shownCount == BrowserViewModel.batchSize)
        #expect(browser.items.count == 200)
        #expect(browser.canShowMore)
        #expect(browser.matchCount != browser.shownCount)
    }

    /// Evidence for R1.AC5: an advance adds to what is shown rather than
    /// replacing it, keeps the order, and repeats nothing.
    @Test func advancingHoldsFourHundredInOrderWithNoRepeats() async throws {
        let repository = PagingSearchRepository(cards: BulkCards.make(14_566))
        let browser = model(repository: repository)
        await browser.start()

        let firstBatch = browser.items.map(\.id)

        await browser.showMore()

        #expect(browser.shownCount == 400)
        #expect(browser.items.count == 400)
        #expect(browser.matchCount == 14_566)

        let ids = browser.items.map(\.id)
        #expect(Set(ids).count == 400)
        #expect(Array(ids.prefix(200)) == firstBatch)
        #expect(ids == ids.sorted { $0.rawValue < $1.rawValue })

        // The second batch was asked for by offset, not re-read from the top.
        #expect(await repository.offsets == [0, 200])
    }

    /// Evidence for R1.AC5: at the end there is nothing to advance to, so the
    /// advance is refused rather than producing an empty tail the interface
    /// would have to explain.
    @Test func advancingPastTheEndIsRefusedNotShownEmpty() async throws {
        let repository = PagingSearchRepository(cards: BulkCards.make(250))
        let browser = model(repository: repository)
        await browser.start()

        #expect(browser.shownCount == 200)
        #expect(browser.canShowMore)

        await browser.showMore()
        #expect(browser.shownCount == 250)
        #expect(!browser.canShowMore)

        let offsetsAfterFullRead = await repository.offsets
        await browser.showMore()

        #expect(browser.shownCount == 250)
        #expect(browser.items.count == 250)
        // Refused before it reached the repository at all.
        #expect(await repository.offsets == offsetsAfterFullRead)
    }

    /// Evidence for R1.AC5: a batch belongs to the query that asked for it.
    /// One arriving after the user has narrowed would otherwise be appended to
    /// a different result, which is the one way paging can corrupt a grid.
    @Test func aBatchForAnAbandonedQueryIsDiscarded() async throws {
        let repository = PagingSearchRepository(cards: BulkCards.make(600))
        let browser = model(repository: repository)
        await browser.start()
        #expect(browser.shownCount == 200)

        await repository.hold(offset: 200)
        let stale = Task { await browser.showMore() }
        while await !repository.isWaiting() { await Task.yield() }

        // The user narrows while the batch is in flight.
        browser.queryText = "card 0001"
        await browser.queryChanged()
        let narrowedCount = browser.shownCount

        await repository.release()
        await stale.value

        #expect(browser.shownCount == narrowedCount)
        #expect(browser.items.count == narrowedCount)
    }
}
