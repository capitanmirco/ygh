import Foundation
import Testing
import YGOCore
import YGOFeatureBrowser
@testable import YGOSync

/// The catalog's real monster types, including the ones that are characters.
struct CatalogTypeVocabulary: CardVocabularyReading {
    func monsterTypes() async throws -> [String] {
        ["Spellcaster", "Dragon", "Warrior", "Winged Beast", "Fiend", "Machine",
         "Wyrm", "Zombie", "Normal", "Continuous", "Joey Wheeler", "Bastion Misaw"]
    }
    func archetypes() async throws -> [String] {
        ["Blue-Eyes", "Dark Magician", "Sky Striker", "Red-Eyes"]
    }
}

@MainActor
@Suite("Vocabulary and proper names")
struct VocabularyProperNameTests {
    private func panel() async -> FilterPanelModel {
        let model = FilterPanelModel(vocabulary: CatalogTypeVocabulary())
        await model.load()
        return model
    }

    /// Evidence for R2.AC3: translating "Blue-Eyes" would make a card
    /// unfindable by the name printed on it.
    @Test func archetypesSetsAndFormatsAreShownAsPublished() async throws {
        let model = await panel()

        // Archetypes come through untouched.
        #expect(model.allArchetypes.contains("Blue-Eyes"))
        model.archetypeQuery = "Blue"
        #expect(model.archetypeSuggestions == ["Blue-Eyes"])

        // The vocabulary has no opinion about them.
        #expect(Vocabulary.cardKind("Blue-Eyes") == "Blue-Eyes")
        #expect(Vocabulary.monsterType("Sky Striker") == "Sky Striker")

        // Format names are published names too.
        for format in CardFormat.allCases {
            #expect(Vocabulary.cardKind(format.rawValue) == format.rawValue)
        }

        // And a character in the type column stays as the source wrote it,
        // truncation included.
        #expect(model.displayName(forMonsterType: "Joey Wheeler") == "Joey Wheeler")
        #expect(model.displayName(forMonsterType: "Bastion Misaw") == "Bastion Misaw")
    }

    /// Evidence for R2.AC4: a field that displays "Incantatore" and finds
    /// nothing when you type it is worse than one that displays English.
    @Test func typingIncantatoreFindsSpellcaster() async throws {
        let model = await panel()

        model.monsterTypeQuery = "incantatore"
        #expect(model.monsterTypeSuggestions == ["Spellcaster"])

        model.monsterTypeQuery = "Bestia Alata"
        #expect(model.monsterTypeSuggestions == ["Winged Beast"])

        model.monsterTypeQuery = "drago"
        #expect(model.monsterTypeSuggestions == ["Dragon"])

        // What the list shows is the Italian term, while the filter stores the
        // upstream one, because that is what the catalog holds.
        #expect(model.displayName(forMonsterType: "Spellcaster") == "Incantatore")
    }

    /// Evidence for R2.AC4: the English term keeps working. Someone who reads
    /// the game in English should not be locked out by a translation.
    @Test func theFilterStillMatchesTheUpstreamTermToo() async throws {
        let model = await panel()

        model.monsterTypeQuery = "Spellcaster"
        #expect(model.monsterTypeSuggestions == ["Spellcaster"])

        model.monsterTypeQuery = "winged"
        #expect(model.monsterTypeSuggestions == ["Winged Beast"])

        // A term that is the same word in both languages matches once, not
        // twice.
        model.monsterTypeQuery = "zombie"
        #expect(model.monsterTypeSuggestions == ["Zombie"])

        // And nothing matching is still nothing.
        model.monsterTypeQuery = "qqqqq"
        #expect(model.monsterTypeSuggestions.isEmpty)
    }
}
