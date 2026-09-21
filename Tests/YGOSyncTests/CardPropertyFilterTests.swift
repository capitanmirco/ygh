import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureBrowser
import YGOPersistence
@testable import YGOSync

@MainActor
@Suite("Card property filters")
struct CardPropertyFilterTests {
    /// Driven through the view model rather than the query builder: the
    /// filters already reached SQL, what none of them had was a caller.
    private func browser(_ queue: DatabaseQueue) -> BrowserViewModel {
        let repository = SQLiteCardRepository(database: queue)
        return BrowserViewModel(
            repository: repository, counter: repository,
            artwork: NoArtwork(), banStatusProvider: repository, language: .english)
    }

    private func titles(_ model: BrowserViewModel) -> Set<String> {
        Set(model.items.map(\.title))
    }

    /// Evidence for R1.AC2: an attribute is a monster's property, so asking
    /// for one cannot bring spells along.
    @Test func darkAdmitsOnlyDarkMonstersAndNoSpellOrTrap() async throws {
        let model = browser(try FilterFixture.database())
        await model.start()

        var filters = CardFilters()
        filters.attributes = [.dark]
        model.filters = filters
        await model.filtersChanged()

        #expect(titles(model) == ["Dark Magician", "Chaos Emperor Dragon"])
        #expect(model.matchCount == 2)
        #expect(!titles(model).contains("Pot of Greed"))
    }

    /// Evidence for R1.AC3: a spell has no level. Counting it as zero would
    /// put every spell in a "Level 0 to 4" search.
    @Test func aLevelRangeExcludesCardsWithNoLevelRatherThanCountingThemAsZero() async throws {
        let model = browser(try FilterFixture.database())
        await model.start()

        var filters = CardFilters()
        filters.levels = 4...4
        model.filters = filters
        await model.filtersChanged()

        #expect(titles(model) == ["Goblin Attack Force", "Undated Card"])
        #expect(model.matchCount == 2)

        // A range starting at zero still admits no spell, because a spell has
        // no level rather than a level of zero.
        filters.levels = 0...4
        model.filters = filters
        await model.filtersChanged()
        #expect(!titles(model).contains("Pot of Greed"))
        #expect(!titles(model).contains("Mirror Force"))
        #expect(model.matchCount == 3)
    }

    /// Evidence for R1.AC4: the two filters that make a themed deck findable.
    @Test func monsterTypeAndArchetypeEachAdmitOnlyTheirMembers() async throws {
        let model = browser(try FilterFixture.database())
        await model.start()

        var filters = CardFilters()
        filters.races = ["Dragon"]
        model.filters = filters
        await model.filtersChanged()
        let dragons = titles(model)
        #expect(dragons.count == 4)
        #expect(dragons.contains("Blue-Eyes White Dragon"))
        #expect(!dragons.contains("Dark Magician"))

        filters = CardFilters()
        filters.archetypes = ["Blue-Eyes"]
        model.filters = filters
        await model.filtersChanged()
        #expect(titles(model) == ["Blue-Eyes White Dragon", "Blue-Eyes Alternative",
                                  "A Fusion Monster"])

        // The two together narrow rather than widen.
        filters.races = ["Spellcaster"]
        model.filters = filters
        await model.filtersChanged()
        #expect(model.matchCount == 0)
        #expect(model.state == .noMatches)
    }

    /// Evidence for R1.AC6: a band of attack, which is how a deck builder
    /// looks for a beater.
    @Test func anAttackBandAdmitsOnlyMonstersInsideIt() async throws {
        let model = browser(try FilterFixture.database())
        await model.start()

        var filters = CardFilters()
        filters.attack = 2000...3000
        model.filters = filters
        await model.filtersChanged()

        let beaters = titles(model)
        #expect(beaters.contains("Blue-Eyes White Dragon"))
        #expect(beaters.contains("Goblin Attack Force"))
        #expect(!beaters.contains("Unlinkable Card"))
        // And not the one printing "?", whose attack is unknown rather than
        // outside the band.
        #expect(!beaters.contains("Slifer the Sky Dragon"))
        #expect(model.matchCount == beaters.count)

        // Defence bands work the same way and combine with attack.
        filters.defense = 2400...2600
        model.filters = filters
        await model.filtersChanged()
        #expect(!titles(model).contains("Goblin Attack Force"))
    }
}

/// No artwork is stored, which is the state every filter test runs in.
struct NoArtwork: ArtworkProviding {
    func storedArtworkPath(
        for identifier: ArtworkIdentifier, variant: ArtworkVariant
    ) async -> String? { nil }
}
