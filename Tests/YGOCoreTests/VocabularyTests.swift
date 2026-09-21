import Foundation
import Testing
@testable import YGOCore

@Suite("Vocabulary")
struct VocabularyTests {
    /// Evidence for R1.AC1: the kinds a player reads most, and the composed
    /// ones that show why this is a table rather than a word-by-word
    /// substitution — Italian leads with the noun.
    @Test func cardKindsReadInItalian() {
        #expect(Vocabulary.cardKind("Effect Monster") == "Mostro Effetto")
        #expect(Vocabulary.cardKind("Normal Monster") == "Mostro Normale")
        #expect(Vocabulary.cardKind("Normal Trap") == "Trappola Normale")
        #expect(Vocabulary.cardKind("Normal Spell") == "Magia Normale")
        #expect(Vocabulary.cardKind("Quick-Play Spell") == "Magia Rapida")
        #expect(Vocabulary.cardKind("Field Spell") == "Magia Terreno")
        #expect(Vocabulary.cardKind("Counter Trap") == "Trappola Contro")

        // Composed kinds: the noun first, then the qualifiers.
        #expect(Vocabulary.cardKind("Xyz Effect Monster") == "Mostro Xyz Effetto")
        #expect(Vocabulary.cardKind("Fusion Pendulum Effect Monster")
                == "Mostro Fusione Pendulum Effetto")
        #expect(!Vocabulary.cardKind("Xyz Effect Monster").hasSuffix("Mostro"))
    }

    /// Evidence for R1.AC2: seven values, written in capitals in Italian too.
    @Test func attributesReadInItalian() {
        #expect(Vocabulary.attribute("DARK") == "OSCURITÀ")
        #expect(Vocabulary.attribute("LIGHT") == "LUCE")
        #expect(Vocabulary.attribute("EARTH") == "TERRA")
        #expect(Vocabulary.attribute("WATER") == "ACQUA")
        #expect(Vocabulary.attribute("FIRE") == "FUOCO")
        #expect(Vocabulary.attribute("WIND") == "VENTO")
        #expect(Vocabulary.attribute("DIVINE") == "DIVINO")
        #expect(Vocabulary.attributes.count == 7)
    }

    /// Evidence for R1.AC3: the types a deck builder filters by.
    @Test func monsterTypesReadInItalian() {
        #expect(Vocabulary.monsterType("Spellcaster") == "Incantatore")
        #expect(Vocabulary.monsterType("Winged Beast") == "Bestia Alata")
        #expect(Vocabulary.monsterType("Dragon") == "Drago")
        #expect(Vocabulary.monsterType("Warrior") == "Guerriero")
        #expect(Vocabulary.monsterType("Fiend") == "Demone")
        #expect(Vocabulary.monsterType("Machine") == "Macchina")
        #expect(Vocabulary.monsterType("Beast-Warrior") == "Bestia Guerriera")

        // The same column carries spell and trap kinds, which are translated
        // too rather than left half English.
        #expect(Vocabulary.monsterType("Continuous") == "Continua")
        #expect(Vocabulary.monsterType("Quick-Play") == "Rapida")
        #expect(Vocabulary.monsterType("Field") == "Terreno")
    }

    /// Evidence for R1.AC4: "Secret Rare" is what the Italian market calls a
    /// Secret Rare. Translating it would invent a term nobody uses.
    @Test func raritiesAreTranslatedOnlyWhereItalyRenamesThem() {
        #expect(Vocabulary.rarity("Common") == "Comune")
        #expect(Vocabulary.rarity("Rare") == "Rara")

        // Left as published, deliberately.
        #expect(Vocabulary.rarity("Secret Rare") == "Secret Rare")
        #expect(Vocabulary.rarity("Ultra Rare") == "Ultra Rare")
        #expect(Vocabulary.rarity("Super Rare") == "Super Rare")
        #expect(Vocabulary.rarity("Ghost Rare") == "Ghost Rare")
    }

    /// Evidence for R1.AC5: Pendulum arrived in 2014 and Link in 2017. The
    /// next kind will arrive too, and it has to reach the screen.
    @Test func anUnknownTermIsReturnedUnchangedRatherThanBlanked() {
        #expect(Vocabulary.cardKind("Quantum Effect Monster") == "Quantum Effect Monster")
        #expect(Vocabulary.attribute("PLASMA") == "PLASMA")
        #expect(Vocabulary.monsterType("Chronomancer") == "Chronomancer")
        #expect(Vocabulary.rarity("Quarter Century Secret Rare")
                == "Quarter Century Secret Rare")

        // Nothing is ever emptied on the way through.
        for term in ["", "   ", "Something Entirely New"] {
            #expect(Vocabulary.cardKind(term) == term)
            #expect(Vocabulary.monsterType(term) == term)
        }
    }
}
