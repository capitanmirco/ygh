import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureBrowser
import YGOPersistence
@testable import YGOSync

@MainActor
@Suite("Era filters")
struct EraFilterTests {
    private func browser(_ queue: DatabaseQueue) -> BrowserViewModel {
        let repository = SQLiteCardRepository(database: queue)
        return BrowserViewModel(
            repository: repository, counter: repository,
            artwork: NoArtwork(), banStatusProvider: repository, language: .english)
    }

    private func titles(_ model: BrowserViewModel) -> Set<String> {
        Set(model.items.map(\.title))
    }

    /// Evidence for R2.AC1: a year range is two string comparisons against ISO
    /// dates, so no new column and no parsing.
    @Test func aYearRangeAdmitsOnlyCardsReleasedInThoseYears() async throws {
        let model = browser(try FilterFixture.database())
        await model.start()

        var filters = CardFilters()
        filters.releaseYears = 2004...2005
        model.filters = filters
        await model.filtersChanged()

        #expect(titles(model) == ["Chaos Emperor Dragon", "Goblin Attack Force",
                                  "A Fusion Monster"])
        #expect(model.matchCount == 3)

        // The boundaries are inclusive at both ends of the year, not of the
        // date: a card released on 2005-03-01 is inside 2004 to 2005.
        filters.releaseYears = 2005...2005
        model.filters = filters
        await model.filtersChanged()
        #expect(titles(model) == ["A Fusion Monster"])

        // A single early year finds the cards from it and nothing later.
        filters.releaseYears = 2002...2002
        model.filters = filters
        await model.filtersChanged()
        #expect(model.matchCount == 4)
        #expect(!titles(model).contains("Chaos Emperor Dragon"))
    }

    /// Evidence for R2.AC2: 523 cards in the real catalog carry no TCG date.
    /// A year range necessarily hides them, and hiding them silently makes the
    /// catalog look smaller than it is.
    @Test func theUndatedCardsHiddenByAYearRangeAreCounted() async throws {
        let model = browser(try FilterFixture.database())
        await model.start()

        // With no year range, nothing is hidden by one.
        #expect(model.excludedUndated == 0)
        let whole = model.matchCount

        var filters = CardFilters()
        filters.releaseYears = 2000...2030
        model.filters = filters
        await model.filtersChanged()

        // Every dated card is inside that range, so what is missing is exactly
        // the undated one.
        #expect(model.matchCount == whole - 1)
        #expect(model.excludedUndated == 1)
        #expect(!titles(model).contains("Undated Card"))

        // Clearing the range brings it back and stops reporting an exclusion.
        model.filters = CardFilters()
        await model.filtersChanged()
        #expect(model.matchCount == whole)
        #expect(model.excludedUndated == 0)
        #expect(titles(model).contains("Undated Card"))
    }

    /// Evidence for R2.AC3: a format is a pool, and the GOAT pool is the one
    /// this user builds for.
    @Test func goatAdmitsOnlyTheGoatPool() async throws {
        let model = browser(try FilterFixture.database())
        await model.start()
        let whole = model.matchCount

        var filters = CardFilters()
        filters.format = .goat
        model.filters = filters
        await model.filtersChanged()

        #expect(model.matchCount < whole)
        #expect(model.matchCount == 8)
        #expect(!titles(model).contains("Blue-Eyes Alternative"))
        #expect(titles(model).contains("Pot of Greed"))

        // Edison is a different pool, not a subset of the same query.
        filters.format = .edison
        model.filters = filters
        await model.filtersChanged()
        #expect(model.matchCount == 3)
    }

    /// Evidence for R2.AC4: a card's restriction depends on the format being
    /// looked at. Showing the TCG status while browsing GOAT would be
    /// answering a different question.
    @Test func theStatusShownIsTheOneForTheChosenFormat() async throws {
        let model = browser(try FilterFixture.database())
        await model.start()

        var filters = CardFilters()
        filters.format = .goat
        model.filters = filters
        await model.filtersChanged()

        let chaos = try #require(model.items.first { $0.title == "Chaos Emperor Dragon" })
        #expect(chaos.banStatus == .forbidden)

        // The same card in the TCG pool carries no restriction, because the
        // fixture records one only for GOAT.
        filters.format = .tcg
        model.filters = filters
        await model.filtersChanged()
        let inTCG = try #require(model.items.first { $0.title == "Chaos Emperor Dragon" })
        #expect(inTCG.banStatus == .unlimited)

        // And the others are unrestricted in both.
        #expect(model.items.filter { $0.banStatus != .unlimited }.isEmpty)
    }
}
