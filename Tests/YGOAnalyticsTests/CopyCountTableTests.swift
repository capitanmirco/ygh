import Testing
import YGOCore
@testable import YGOAnalytics

@Suite("Copy count table")
struct CopyCountTableTests {
    /// Evidence for R6.AC1: each copy helps, and each helps less than the one
    /// before. That shape is the decision the table exists to inform.
    @Test func figuresRiseWithEachAdditionalCopy() {
        let (deck, index) = Sample.deck(size: 40, copies: 3)
        let table = Hypergeometric.copyCountTable(
            for: CardIdentifier(1), in: deck, index: index, playingFirst: true)

        #expect(table.rows.count == 3)
        #expect(table.rows.map(\.copies) == [1, 2, 3])
        #expect(table.population == 40)
        #expect(table.hand.size == 5)

        let figures = table.rows.map(\.atLeastOne)
        #expect(figures == figures.sorted(), "ogni copia in più deve aiutare")

        // Each row matches the single-card calculation at that count.
        for row in table.rows {
            let direct = Hypergeometric.probabilityOfAtLeast(
                1, population: 40, copies: row.copies, drawn: 5)
            #expect(abs(row.atLeastOne - direct) < 1e-12,
                    "la tabella non può divergere dal calcolo singolo")
        }

        // The known figure sits in the third row.
        #expect(abs(table.rows[2].atLeastOne - 0.338) < 0.0005)

        // Diminishing returns: the third copy gains less than the second.
        #expect(table.rows[2].gainOverPrevious < table.rows[1].gainOverPrevious)
        #expect(table.rows[0].gainOverPrevious == table.rows[0].atLeastOne)
        #expect(table.rows[1].sentence.contains("punti"))
    }

    /// Evidence for R6.AC2: the forty-first card has a price, and it should be
    /// visible before it is paid.
    @Test func fortyAgainstSixtyDiffersByWhatTheDistributionGives() {
        let hand = OpeningHand(format: .tcg, playingFirst: true)

        let atForty = Hypergeometric.probabilityAtDeckSize(40, copies: 3, hand: hand)
        let atSixty = Hypergeometric.probabilityAtDeckSize(60, copies: 3, hand: hand)

        #expect(abs(atForty - 0.338) < 0.0005)
        #expect(abs(atSixty - 0.233) < 0.0005)
        #expect(abs((atForty - atSixty) - 0.104) < 0.001,
                "quaranta contro sessanta vale 10.4 punti")

        // It falls monotonically as the deck grows.
        let sizes = [40, 45, 50, 55, 60]
        let figures = sizes.map {
            Hypergeometric.probabilityAtDeckSize($0, copies: 3, hand: hand)
        }
        #expect(figures == figures.sorted(by: >))

        // The table can be asked for another size without changing the deck.
        let (deck, index) = Sample.deck(size: 40, copies: 3)
        let asSixty = Hypergeometric.copyCountTable(
            for: CardIdentifier(1), in: deck, index: index,
            playingFirst: true, populationOverride: 60)
        #expect(asSixty.population == 60)
        #expect(abs(asSixty.rows[2].atLeastOne - 0.233) < 0.0005)
        #expect(deck.drawablePopulation == 40, "chiedere non deve cambiare il mazzo")
    }

    /// Evidence for R6.AC3: a probability outside zero to one is a bug that
    /// would be shown to the user as a percentage.
    @Test func noFigureFallsOutsideZeroToOne() {
        for population in [0, 1, 3, 20, 40, 60, 200] {
            for copies in 0...4 {
                for drawn in [0, 1, 5, 6, 100] {
                    for threshold in 0...4 {
                        let figure = Hypergeometric.probabilityOfAtLeast(
                            threshold, population: population,
                            copies: copies, drawn: drawn)
                        #expect(figure >= 0 && figure <= 1,
                                "P=\(figure) fuori range per N=\(population) K=\(copies) n=\(drawn) k=\(threshold)")
                        #expect(!figure.isNaN)
                    }

                    let exact = Hypergeometric.probabilityOfExactly(
                        1, population: population, copies: copies, drawn: drawn)
                    #expect(exact >= 0 && exact <= 1)
                    #expect(!exact.isNaN)
                }
            }
        }

        // Combinations too.
        for population in [1, 40, 60] {
            for drawn in [1, 5, 6] {
                let combo = Hypergeometric.probabilityOfCombination(
                    [(3, 1), (2, 2)], population: population, drawn: drawn)
                #expect(combo >= 0 && combo <= 1)
                #expect(!combo.isNaN)
            }
        }
    }
}
