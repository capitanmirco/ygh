import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureBrowser
import YGOPersistence
@testable import YGOSync

/// A vocabulary the size of the real one, so "typing narrows it" is tested
/// against the problem rather than against a handful of values.
struct BulkVocabulary: CardVocabularyReading {
    let types: [String]
    let archetypeNames: [String]

    func monsterTypes() async throws -> [String] { types }
    func archetypes() async throws -> [String] { archetypeNames }
}

@MainActor
@Suite("Filter panel")
struct FilterPanelTests {
    private func realVocabulary() -> BulkVocabulary {
        // 87 monster types and 662 archetypes, as the catalog holds.
        let types = (1...87).map { "Type \(String(format: "%02d", $0))" }
            + [] // names below stand in for the real ones
        var archetypes = (1...658).map { "Archetype \(String(format: "%03d", $0))" }
        archetypes += ["Blue-Eyes", "Red-Eyes", "Dark Magician", "Sky Striker"]
        return BulkVocabulary(types: Array(types.prefix(87)), archetypeNames: archetypes)
    }

    private func panel() async -> FilterPanelModel {
        let model = FilterPanelModel(vocabulary: realVocabulary())
        await model.load()
        return model
    }

    /// Evidence for R1.AC5: 662 values cannot be a menu. This is the filter
    /// that makes a themed deck findable, and it is unusable without typing.
    @Test func typingNarrowsTheSixHundredAndSixtyTwoArchetypes() async throws {
        let model = await panel()

        #expect(model.allArchetypes.count == 662)
        #expect(model.archetypeSuggestions.count == 662)

        model.archetypeQuery = "eyes"
        let eyes = model.archetypeSuggestions
        #expect(eyes.count == 2)
        #expect(eyes.contains("Blue-Eyes"))
        // Matching anywhere rather than only at the start, so "eyes" finds
        // Red-Eyes too.
        #expect(eyes.contains("Red-Eyes"))

        // Case does not matter, because nobody types an archetype's casing.
        model.archetypeQuery = "BLUE"
        #expect(model.archetypeSuggestions == ["Blue-Eyes"])

        // Nothing matching is an empty list rather than the whole catalogue.
        model.archetypeQuery = "zzzzzz"
        #expect(model.archetypeSuggestions.isEmpty)

        // Clearing the field offers everything again.
        model.archetypeQuery = "   "
        #expect(model.archetypeSuggestions.count == 662)
    }

    /// Evidence for R1.AC5: 87 is fewer than 662 and still too many to scan.
    @Test func typingNarrowsTheEightySevenMonsterTypes() async throws {
        let model = await panel()

        #expect(model.allMonsterTypes.count == 87)
        #expect(model.monsterTypeSuggestions.count == 87)

        model.monsterTypeQuery = "Type 0"
        #expect(model.monsterTypeSuggestions.count == 9)

        model.monsterTypeQuery = "Type 01"
        #expect(model.monsterTypeSuggestions == ["Type 01"])

        // The two fields are independent: narrowing one leaves the other.
        model.archetypeQuery = "Blue"
        #expect(model.monsterTypeSuggestions == ["Type 01"])
        #expect(model.archetypeSuggestions == ["Blue-Eyes"])
    }

    /// Evidence for R5.AC6: a panel that needs a pointer is a panel half the
    /// filters cannot be reached from.
    @Test func everyFilterIsSetAndClearedWithoutAPointer() async throws {
        let model = await panel()
        #expect(FilterPanelModel.Region.allCases.count == 10)
        #expect(model.focusedRegion == .cardType)

        // Stepping forward reaches every section in reading order.
        var visited: [FilterPanelModel.Region] = [model.focusedRegion]
        for _ in 1..<FilterPanelModel.Region.allCases.count {
            model.moveFocus(by: 1)
            visited.append(model.focusedRegion)
        }
        #expect(visited == FilterPanelModel.Region.allCases)

        // The ends hold rather than wrapping.
        model.moveFocus(by: 1)
        #expect(model.focusedRegion == .owned)
        for _ in 0..<20 { model.moveFocus(by: -1) }
        #expect(model.focusedRegion == .cardType)

        // Every section names itself, which is what a reader announces.
        #expect(FilterPanelModel.Region.allCases.allSatisfy { !$0.title.isEmpty })

        // And every one of them can be cleared on its own, leaving the rest.
        var filters = CardFilters()
        filters.cardTypes = [.spell]
        filters.attributes = [.dark]
        filters.levels = 4...4
        filters.races = ["Dragon"]
        filters.archetypes = ["Blue-Eyes"]
        filters.attack = 0...3000
        filters.unknownStatsOnly = true
        filters.releaseYears = 2004...2005
        filters.format = .goat
        filters.publishedList = PublishedListSelection(
            format: .tcg, effectiveDate: "2005-03-01")
        filters.ownedOnly = true
        #expect(filters.descriptions.count == 11)

        for region in FilterPanelModel.Region.allCases {
            model.clear(region, in: &filters)
        }
        #expect(filters.isEmpty)
        #expect(filters.descriptions.isEmpty)
        #expect(model.archetypeQuery.isEmpty)
        #expect(model.monsterTypeQuery.isEmpty)
    }
}
