import Foundation
import Testing
@testable import YGOCore

@Suite("Vocabulary coverage")
struct VocabularyCoverageTests {
    /// The catalog's own distinct values, recorded from the live database
    /// rather than typed from memory. "Mostly translated" means the half
    /// nobody looks at is still English, so the check walks all of them.
    struct CatalogVocabulary: Decodable {
        let kinds: [String]
        let types: [String]
    }

    static let catalog: CatalogVocabulary = {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "fixtures/catalog-vocabulary.json")
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(
            CatalogVocabulary.self, from: try! Data(contentsOf: url))
    }()

    /// Evidence for R3.AC1: seven, all of them.
    @Test func allSevenAttributesResolve() {
        let upstream = ["DARK", "LIGHT", "EARTH", "WATER", "FIRE", "WIND", "DIVINE"]
        #expect(upstream.count == 7)

        for attribute in upstream {
            let translated = Vocabulary.attribute(attribute)
            #expect(translated != attribute, "\(attribute) was not translated")
            #expect(!translated.isEmpty)
        }

        // And the table holds nothing the catalog does not.
        #expect(Set(Vocabulary.attributes.keys) == Set(upstream))
    }

    /// Evidence for R3.AC2: 101 distinct kinds, of which 64 carry a
    /// character's name. Each resolves, the named ones through their prefix.
    @Test func everyCardKindTheCatalogHoldsResolves() {
        let kinds = Self.catalog.kinds
        #expect(kinds.count == 101)

        let skills = kinds.filter { $0.hasPrefix("Skill - ") }
        #expect(skills.count == 54)

        for kind in kinds {
            let translated = Vocabulary.cardKind(kind)
            #expect(!translated.isEmpty, "\(kind) resolved to nothing")
            // Either it was translated, or it is a skill kind whose character
            // name stays as published.
            #expect(translated != kind || kind.hasPrefix("Skill - "),
                    "\(kind) was left in English")
        }

        // The 47 that are not skills are all in the table.
        let real = kinds.filter { !$0.hasPrefix("Skill - ") }
        #expect(real.count == 47)
        #expect(real.allSatisfy { Vocabulary.cardKinds[$0] != nil })
    }

    /// Evidence for R3.AC3: 87 types, about fifty of which are the same
    /// character names again, because a skill card's type column holds the
    /// character rather than a monster type.
    @Test func everyMonsterTypeTheCatalogHoldsResolves() {
        let types = Self.catalog.types
        #expect(types.count == 87)

        // "Known to the table" rather than "changed by it": Wyrm and Zombie
        // are the same word in Italian, and counting them as untranslated
        // would be counting a correct answer as a gap.
        var known = 0
        var properNames = 0
        var unchangedButKnown: [String] = []
        for type in types where !type.isEmpty {
            let result = Vocabulary.monsterType(type)
            #expect(!result.isEmpty)
            if Vocabulary.monsterTypes[type] != nil {
                known += 1
                if result == type { unchangedButKnown.append(type) }
            } else if Vocabulary.isProperName(type) {
                properNames += 1
            }
        }

        #expect(known == 33)
        #expect(properNames == 53)
        #expect(unchangedButKnown.sorted() == ["Wyrm", "Zombie"])

        // Every non-empty value is either in the table or a known proper name;
        // nothing is left unaccounted for.
        #expect(known + properNames == types.filter { !$0.isEmpty }.count)
    }

    /// Evidence for R3.AC2: the prefix is ours, the name is the source's. The
    /// upstream truncates these to thirteen characters, and completing them
    /// would be inventing data.
    @Test func skillKindsTranslateTheirPrefixAndKeepTheirName() {
        #expect(Vocabulary.cardKind("Skill - Joey Wheeler") == "Abilità - Joey Wheeler")
        #expect(Vocabulary.cardKind("Skill - Yami Yugi") == "Abilità - Yami Yugi")

        // The truncation survives untouched.
        #expect(Vocabulary.cardKind("Skill - Bastion Misaw") == "Abilità - Bastion Misaw")
        #expect(Vocabulary.cardKind("Skill - Chazz Princet") == "Abilità - Chazz Princet")

        // A skill with no character at all is just a skill.
        #expect(Vocabulary.cardKind("Skill - ") == "Abilità")

        // The type column keeps the name as published, with no prefix to
        // translate.
        #expect(Vocabulary.monsterType("Joey Wheeler") == "Joey Wheeler")
        #expect(Vocabulary.monsterType("Bastion Misaw") == "Bastion Misaw")
    }

    /// Evidence for R3.AC4: the table will meet a term it does not hold, and
    /// the count is how that becomes visible instead of silent.
    @Test func theUntranslatedCountIsZeroForTheCatalogAsItStands() {
        let missing = Vocabulary.untranslated(
            kinds: Self.catalog.kinds, types: Self.catalog.types)
        #expect(missing.isEmpty, "not translated: \(missing)")

        // And it reports a genuinely new term rather than shrugging.
        let withNew = Vocabulary.untranslated(
            kinds: Self.catalog.kinds + ["Quantum Effect Monster"],
            types: Self.catalog.types + ["Chronomancer"])
        #expect(withNew == ["Chronomancer", "Quantum Effect Monster"])
    }
}
