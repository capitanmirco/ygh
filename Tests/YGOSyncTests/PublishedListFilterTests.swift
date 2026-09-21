import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureBrowser
import YGOPersistence
@testable import YGOSync

@MainActor
@Suite("Published list filter")
struct PublishedListFilterTests {
    /// The fixture catalog, plus two stored lists: an era one and a current
    /// one that disagrees with it.
    private func seeded() throws -> DatabaseQueue {
        let queue = try FilterFixture.database()
        let history = SQLiteBanlistHistory(database: queue)

        // 2005: Chaos Emperor Dragon forbidden, Graceful Charity limited,
        // Goblin Attack Force semi-limited. Plus one identifier the catalog
        // does not hold at all.
        try history.store(
            PublishedBanlist(effectiveDate: "2005-03-01", statuses: [
                4009: .forbidden, 4013: .limited, 4010: .semiLimited, 99_999: .forbidden,
            ]),
            format: .tcg, source: "yaml-yugi-limit-regulation",
            fetchedAt: Date(timeIntervalSince1970: 1_758_441_600))

        // Today: Chaos Emperor Dragon is free again and Pot of Greed is gone.
        try history.store(
            PublishedBanlist(effectiveDate: "2026-05-18", statuses: [4012: .forbidden]),
            format: .tcg, source: "yaml-yugi-limit-regulation",
            fetchedAt: Date(timeIntervalSince1970: 1_758_441_600))
        return queue
    }

    private func browser(_ queue: DatabaseQueue) -> BrowserViewModel {
        let repository = SQLiteCardRepository(database: queue)
        return BrowserViewModel(
            repository: repository, counter: repository,
            artwork: NoArtwork(), banStatusProvider: repository,
            publishedLists: SQLiteBanlistHistory(database: queue), language: .english)
    }

    private func titles(_ model: BrowserViewModel) -> Set<String> {
        Set(model.items.map(\.title))
    }

    /// Evidence for R3.AC1: choosing a list shows what that list named, and
    /// nothing else.
    @Test func theMarch2005ListAdmitsItsSeventySevenCardsAndNoOthers() async throws {
        let model = browser(try seeded())
        await model.start()
        let whole = model.matchCount

        var filters = CardFilters()
        filters.publishedList = PublishedListSelection(
            format: .tcg, effectiveDate: "2005-03-01")
        model.filters = filters
        await model.filtersChanged()

        // Three of its four entries match a card in this catalog.
        #expect(model.matchCount == 3)
        #expect(model.matchCount < whole)
        #expect(titles(model) == ["Chaos Emperor Dragon", "Graceful Charity",
                                  "Goblin Attack Force"])
        #expect(!titles(model).contains("Pot of Greed"))

        // A different list is a different set.
        filters.publishedList = PublishedListSelection(
            format: .tcg, effectiveDate: "2026-05-18")
        model.filters = filters
        await model.filtersChanged()
        #expect(titles(model) == ["Pot of Greed"])
    }

    /// Evidence for R3.AC2, which is the point of the filter: the status shown
    /// is the one the chosen list gave, not the one the card carries today.
    @Test func aCardForbiddenThenAndFreeNowShowsForbidden() async throws {
        let model = browser(try seeded())
        await model.start()

        var filters = CardFilters()
        filters.publishedList = PublishedListSelection(
            format: .tcg, effectiveDate: "2005-03-01")
        model.filters = filters
        await model.filtersChanged()

        let chaos = try #require(model.items.first { $0.title == "Chaos Emperor Dragon" })
        #expect(chaos.banStatus == .forbidden)

        let charity = try #require(model.items.first { $0.title == "Graceful Charity" })
        #expect(charity.banStatus == .limited)

        let goblin = try #require(model.items.first { $0.title == "Goblin Attack Force" })
        #expect(goblin.banStatus == .semiLimited)

        // The catalog itself records no TCG restriction for any of them, so
        // these statuses can only have come from the list.
        let repository = SQLiteCardRepository(database: try seeded())
        #expect(try await repository.banStatus(
            for: CardIdentifier(3), in: .tcg) == .unlimited)
    }

    /// Evidence for R3.AC2: without a list, the grid goes back to the
    /// catalog's current view. Mixing the two would state something neither
    /// source says.
    @Test func withNoListChosenTheCurrentStatusIsShownInstead() async throws {
        let model = browser(try seeded())
        await model.start()

        var filters = CardFilters()
        filters.publishedList = PublishedListSelection(
            format: .tcg, effectiveDate: "2005-03-01")
        model.filters = filters
        await model.filtersChanged()
        #expect(model.items.first { $0.title == "Chaos Emperor Dragon" }?
            .banStatus == .forbidden)

        // Clearing the list restores today's answer for the same card.
        model.filters = CardFilters()
        await model.filtersChanged()
        let chaos = try #require(model.items.first { $0.title == "Chaos Emperor Dragon" })
        #expect(chaos.banStatus == .unlimited)

        // And in GOAT, where the catalog does record a restriction, that one
        // is shown rather than the 2005 list's.
        var goat = CardFilters()
        goat.format = .goat
        model.filters = goat
        await model.filtersChanged()
        #expect(model.items.first { $0.title == "Chaos Emperor Dragon" }?
            .banStatus == .forbidden)
    }

    /// Evidence for R3.AC3: the chooser offers what is stored, in date order.
    @Test func theChooserOffersTheStoredListsOldestFirst() async throws {
        let model = browser(try seeded())
        await model.start()

        let lists = model.availableLists(for: .tcg)
        #expect(lists.count == 2)
        #expect(lists.map(\.effectiveDate) == ["2005-03-01", "2026-05-18"])
        #expect(lists.allSatisfy { $0.format == .tcg })
        #expect(lists.first?.entryCount == 4)

        // A format with nothing stored offers nothing, which R3.AC4 turns into
        // a sentence rather than an empty menu.
        #expect(model.availableLists(for: .ocg).isEmpty)
    }

    /// Evidence for R3.AC5: a list can name a card the catalog cannot match —
    /// 203 cards carry no Konami identifier, and lists run ahead of catalog
    /// syncs. Showing fewer cards without saying why looks like a bug.
    @Test func aListNamingAnUnknownCardReportsTheDifference() async throws {
        let model = browser(try seeded())
        await model.start()
        #expect(model.unmatchedOnList == 0)

        var filters = CardFilters()
        filters.publishedList = PublishedListSelection(
            format: .tcg, effectiveDate: "2005-03-01")
        model.filters = filters
        await model.filtersChanged()

        // Four entries, three cards shown, one unmatched and counted.
        #expect(model.matchCount == 3)
        #expect(model.unmatchedOnList == 1)

        // Clearing the list stops reporting it.
        model.filters = CardFilters()
        await model.filtersChanged()
        #expect(model.unmatchedOnList == 0)
    }
}
