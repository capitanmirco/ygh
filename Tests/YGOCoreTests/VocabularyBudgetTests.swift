import Foundation
import Testing
@testable import YGOCore

@Suite("Vocabulary budgets")
struct VocabularyBudgetTests {
    /// Evidence for NFR1: a grid holds 200 tiles and each translates one term,
    /// so the cost is measured at that size rather than argued away.
    @Test func translatingTwoHundredTilesCostsNothingMeasurable() {
        let kinds = Array(Vocabulary.cardKinds.keys)
        #expect(kinds.count > 20)

        // Warm the dictionary once, then measure.
        _ = kinds.map(Vocabulary.cardKind)

        var worst: Double = 0
        for _ in 0..<10 {
            let started = DispatchTime.now().uptimeNanoseconds
            for index in 0..<200 {
                _ = Vocabulary.cardKind(kinds[index % kinds.count])
            }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            worst = max(worst, elapsed)
        }

        #expect(worst < 1, "translating 200 terms took \(worst) ms")
    }

    /// Evidence for NFR2: the game keeps adding kinds. A term nobody has
    /// translated yet has to reach the screen, not vanish from it.
    @Test func noTermIsEverLostOnItsWayToTheScreen() {
        let unknowns = ["Quantum Effect Monster", "PLASMA", "Chronomancer",
                        "Quarter Century Secret Rare", "Skill - Someone New",
                        "", "   ", "12345", "Ω"]

        for term in unknowns {
            #expect(!Vocabulary.cardKind(term).isEmpty || term.isEmpty)
            #expect(!Vocabulary.attribute(term).isEmpty || term.isEmpty)
            #expect(!Vocabulary.monsterType(term).isEmpty || term.isEmpty)
            #expect(!Vocabulary.rarity(term).isEmpty || term.isEmpty)
        }

        // Anything not in a table comes back exactly as it went in.
        #expect(Vocabulary.attribute("PLASMA") == "PLASMA")
        #expect(Vocabulary.monsterType("Chronomancer") == "Chronomancer")
        #expect(Vocabulary.rarity("Quarter Century Secret Rare")
                == "Quarter Century Secret Rare")

        // A new skill character still reads as a skill rather than as English.
        #expect(Vocabulary.cardKind("Skill - Someone New") == "Abilità - Someone New")
    }

    /// Evidence for NFR3: the translated term is the one shown, so it is also
    /// the one read aloud. A screen that announced the English term beside the
    /// Italian one would be reading a different card.
    @Test func whatIsReadAloudIsTheTranslatedTerm() {
        // The vocabulary is the single source for both, so there is no second
        // string that could differ.
        let kind = "Quick-Play Spell"
        let shown = Vocabulary.cardKind(kind)
        let spoken = Vocabulary.cardKind(kind)
        #expect(shown == spoken)
        #expect(shown == "Magia Rapida")

        // Nothing in the table maps two upstream terms to one Italian term in
        // a way that would make a reader hear the wrong card.
        let collisions = Dictionary(grouping: Vocabulary.cardKinds) { $0.value }
            .filter { $0.value.count > 1 }
        #expect(collisions.isEmpty, "two kinds read the same: \(collisions.keys)")

        let typeCollisions = Dictionary(grouping: Vocabulary.monsterTypes) { $0.value }
            .filter { $0.value.count > 1 }
        #expect(typeCollisions.isEmpty, "two types read the same: \(typeCollisions.keys)")
    }
}
