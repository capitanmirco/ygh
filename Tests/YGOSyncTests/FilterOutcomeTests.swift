import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureBrowser
import YGOPersistence
@testable import YGOSync

@MainActor
@Suite("Filter outcome")
struct FilterOutcomeTests {
    private func browser(_ queue: DatabaseQueue) -> BrowserViewModel {
        let repository = SQLiteCardRepository(database: queue)
        return BrowserViewModel(
            repository: repository, counter: repository,
            artwork: NoArtwork(), banStatusProvider: repository, language: .english)
    }

    private func titles(_ model: BrowserViewModel) -> Set<String> {
        Set(model.items.map(\.title))
    }

    /// Non-async on purpose: inside an async test, `queue.write` resolves to
    /// GRDB's async overload.
    private func writeSync(_ queue: DatabaseQueue, _ body: (Database) throws -> Void) throws {
        try queue.write(body)
    }

    /// Evidence for R5.AC1: filters narrow together rather than in turn, and
    /// the count agrees with the rows — which is what would break if any of
    /// them were applied after the query instead of inside it.
    @Test func twoFiltersAdmitOnlyCardsSatisfyingBoth() async throws {
        let model = browser(try FilterFixture.database())
        await model.start()

        var filters = CardFilters()
        filters.cardTypes = [.monster]
        model.filters = filters
        await model.filtersChanged()
        let monsters = model.matchCount

        filters.attributes = [.light]
        model.filters = filters
        await model.filtersChanged()

        #expect(model.matchCount < monsters)
        #expect(titles(model) == ["Blue-Eyes White Dragon", "Blue-Eyes Alternative",
                                  "A Fusion Monster"])
        #expect(model.matchCount == model.items.count)

        // A third narrows further still.
        filters.levels = 8...8
        model.filters = filters
        await model.filtersChanged()
        #expect(titles(model) == ["Blue-Eyes White Dragon", "Blue-Eyes Alternative"])
    }

    /// Evidence for R5.AC2: the applied filters have to be visible while the
    /// results change, which is why they live beside the grid rather than in a
    /// popover that would cover it.
    @Test func eachAppliedFilterIsNamedAndAnUnsetOneIsNot() async throws {
        let model = browser(try FilterFixture.database())
        await model.start()

        #expect(model.appliedFilters.isEmpty)
        #expect(!model.hasFilters)

        var filters = CardFilters()
        filters.cardTypes = [.spell]
        filters.releaseYears = 2002...2003
        filters.format = .goat
        model.filters = filters
        await model.filtersChanged()

        let applied = model.appliedFilters
        #expect(applied.count == 3)
        #expect(applied.contains { $0.contains("magia") })
        #expect(applied.contains { $0.contains("2002") && $0.contains("2003") })
        #expect(applied.contains { $0.contains("GOAT") })
        #expect(model.hasFilters)

        // Nothing that is not applied is listed.
        #expect(!applied.contains { $0.contains("attacco") })
        #expect(!applied.contains { $0.contains("archetipo") })

        // A single-value range reads as one value rather than as a range.
        filters.levels = 4...4
        model.filters = filters
        await model.filtersChanged()
        #expect(model.appliedFilters.contains("livello 4"))
    }

    /// Evidence for R5.AC3: clearing puts the catalog back the way it opened.
    @Test func clearingReturnsTheCountToTheWholeCatalog() async throws {
        let model = browser(try FilterFixture.database())
        await model.start()
        let whole = model.matchCount

        var filters = CardFilters()
        filters.cardTypes = [.trap]
        model.filters = filters
        await model.filtersChanged()
        #expect(model.matchCount == 1)

        await model.clearFilters()

        #expect(model.matchCount == whole)
        #expect(model.appliedFilters.isEmpty)
        #expect(!model.hasFilters)
        #expect(model.excludedUndated == 0)

        // Clearing when nothing is applied is a no-op rather than a reload.
        await model.clearFilters()
        #expect(model.matchCount == whole)
    }

    /// Evidence for R5.AC4: an empty grid with no explanation is the worst
    /// outcome this feature can produce, because every filter is invisible
    /// once it has done its work.
    @Test func anEmptyResultNamesTheFiltersResponsible() async throws {
        let model = browser(try FilterFixture.database())
        await model.start()

        var filters = CardFilters()
        filters.cardTypes = [.spell]
        filters.attributes = [.dark]   // a spell has no attribute
        model.filters = filters
        await model.filtersChanged()

        #expect(model.state == .noMatches)
        #expect(model.matchCount == 0)
        #expect(model.items.isEmpty)

        // And the screen can say what did it.
        let applied = model.appliedFilters
        #expect(applied.count == 2)
        #expect(applied.contains { $0.contains("magia") })
        #expect(applied.contains { $0.contains("DARK") })

        // Removing one of them brings results back, which is the point of
        // naming them.
        filters.attributes = []
        model.filters = filters
        await model.filtersChanged()
        #expect(model.matchCount == 2)
    }

    /// Evidence for R5.AC5: the collection holds nothing today, so this filter
    /// currently hides everything. Saying so is the difference between a
    /// working filter and a broken screen.
    @Test func ownedOnlyAgainstAnEmptyCollectionSaysNothingIsOwned() async throws {
        let queue = try FilterFixture.database()
        let model = browser(queue)
        await model.start()

        var filters = CardFilters()
        filters.ownedOnly = true
        model.filters = filters
        await model.filtersChanged()

        #expect(model.matchCount == 0)
        #expect(model.state == .noMatches)
        #expect(model.appliedFilters == ["solo carte possedute"])

        // With copies recorded, it narrows to them rather than to nothing.
        try writeSync(queue) { db in
            try db.execute(sql: """
                INSERT INTO collection_entry (card_id, condition, quantity)
                VALUES (1, 'near_mint', 3), (6, 'lightly_played', 1)
                """)
        }
        await model.filtersChanged()
        #expect(titles(model) == ["Blue-Eyes White Dragon", "Pot of Greed"])
        #expect(model.matchCount == 2)
    }
}
