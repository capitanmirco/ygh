import Testing
import YGOCore
@testable import YGOAnalytics

@Suite("Combination odds")
struct CombinationOddsTests {
    /// A deck of `size` holding the given copy counts, one card per count.
    private func deck(size: Int, copyCounts: [Int], format: CardFormat = .tcg)
        -> (Deck, DeckCardIndex) {
        var slots: [DeckSlot] = []
        var entries: [DeckCardIndex.Entry] = []
        var used = 0

        for (offset, copies) in copyCounts.enumerated() {
            let id = offset + 1
            slots.append(Sample.slot(id, quantity: copies))
            entries.append(Sample.entry(id, name: "Pezzo \(id)"))
            used += copies
        }
        for filler in 0..<(size - used) {
            let id = 1_000 + filler
            slots.append(Sample.slot(id))
            entries.append(Sample.entry(id))
        }

        return (
            Deck(id: 1, name: "Prova", format: format, slots: slots,
                 createdAt: Sample.at, updatedAt: Sample.at),
            DeckCardIndex(entries: entries))
    }

    /// Evidence for R2.AC1: a combination is far rarer than its parts, and
    /// this is the figure that shows it. 9.8% against 33.8% for either half.
    @Test func threeAndThreeInFortyOnFiveCardsIsTenPercent() {
        let exact = Hypergeometric.probabilityOfCombination(
            [(copies: 3, required: 1), (copies: 3, required: 1)],
            population: 40, drawn: 5)
        #expect(abs(exact - 0.098) < 0.0005, "atteso 0.098, ricevuto \(exact)")

        // Through the deck-shaped entry point.
        let (built, index) = deck(size: 40, copyCounts: [3, 3])
        let odds = Hypergeometric.odds(
            forCombination: [(CardIdentifier(1), 1), (CardIdentifier(2), 1)],
            in: built, index: index, playingFirst: true)
        #expect(abs(odds.probability - 0.098) < 0.0005)
        #expect(odds.pieces.count == 2)
        #expect(odds.sentence.contains("Pezzo 1"))
        #expect(odds.sentence.contains("Pezzo 2"))

        // Either half alone is far more likely: the point of the calculation.
        let alone = Hypergeometric.probabilityOfAtLeast(
            1, population: 40, copies: 3, drawn: 5)
        #expect(alone > exact * 3, "la combo deve essere molto più rara di un pezzo solo")
    }

    /// Evidence for R2.AC2: needing more can never be more likely. Checked
    /// across a sweep rather than on one case.
    @Test func aCombinationNeverExceedsItsLeastLikelyMember() {
        for population in [40, 45, 50, 60] {
            for firstCopies in 1...3 {
                for secondCopies in 1...3 {
                    for drawn in [5, 6] {
                        let combo = Hypergeometric.probabilityOfCombination(
                            [(firstCopies, 1), (secondCopies, 1)],
                            population: population, drawn: drawn)
                        let weakest = min(
                            Hypergeometric.probabilityOfAtLeast(
                                1, population: population, copies: firstCopies, drawn: drawn),
                            Hypergeometric.probabilityOfAtLeast(
                                1, population: population, copies: secondCopies, drawn: drawn))
                        #expect(combo <= weakest + 1e-12,
                                "combo \(combo) > membro più debole \(weakest)")
                        #expect(combo >= 0 && combo <= 1)
                    }
                }
            }
        }
    }

    /// Evidence for R2.AC3: one code path, so the two cannot drift apart.
    @Test func aSingleCardCombinationEqualsTheSingleCardFigure() {
        for population in [40, 50, 60] {
            for copies in 1...3 {
                for drawn in [5, 6] {
                    let asCombination = Hypergeometric.probabilityOfCombination(
                        [(copies, 1)], population: population, drawn: drawn)
                    let asSingle = Hypergeometric.probabilityOfAtLeast(
                        1, population: population, copies: copies, drawn: drawn)
                    #expect(abs(asCombination - asSingle) < 1e-12,
                            "combo a un pezzo \(asCombination) != singola \(asSingle)")
                }
            }
        }
    }

    /// Evidence for R2.AC4: a piece you do not own makes the rest irrelevant.
    @Test func reportsZeroWhenAMemberIsAbsentFromTheDeck() {
        let (built, index) = deck(size: 40, copyCounts: [3])

        let odds = Hypergeometric.odds(
            forCombination: [(CardIdentifier(1), 1), (CardIdentifier(99_999), 1)],
            in: built, index: index, playingFirst: true)
        #expect(odds.probability == 0)

        // Even with three copies of the piece that is present.
        #expect(Hypergeometric.probabilityOfCombination(
            [(3, 1), (0, 1)], population: 40, drawn: 5) == 0)
    }

    /// Evidence for R2.AC5: asking for two copies is a different question,
    /// and inclusion-exclusion could not have answered it.
    @Test func requiringTwoCopiesIsRarerThanRequiringOne() {
        let one = Hypergeometric.probabilityOfCombination(
            [(3, 1), (3, 1)], population: 40, drawn: 5)
        let two = Hypergeometric.probabilityOfCombination(
            [(3, 2), (3, 1)], population: 40, drawn: 5)

        #expect(two < one, "due copie devono essere più rare di una")
        #expect(two > 0, "tre copie in mazzo possono darne due in mano")

        // Requiring more copies than the deck holds is impossible.
        #expect(Hypergeometric.probabilityOfCombination(
            [(1, 2)], population: 40, drawn: 5) == 0)

        // Requiring two of one card matches the single-card at-least-two figure.
        let asSingle = Hypergeometric.probabilityOfAtLeast(
            2, population: 40, copies: 3, drawn: 5)
        let asCombination = Hypergeometric.probabilityOfCombination(
            [(3, 2)], population: 40, drawn: 5)
        #expect(abs(asCombination - asSingle) < 1e-12)
    }

    /// Three pieces is rarer still, and the enumeration must cope with it.
    @Test func threePieceCombinationsAreRarerThanTwo() {
        let two = Hypergeometric.probabilityOfCombination(
            [(3, 1), (3, 1)], population: 40, drawn: 5)
        let three = Hypergeometric.probabilityOfCombination(
            [(3, 1), (3, 1), (3, 1)], population: 40, drawn: 5)

        #expect(three < two)
        #expect(three > 0)

        // Five pieces needing one each cannot fit a five-card hand alongside
        // nothing else, but is still possible.
        let five = Hypergeometric.probabilityOfCombination(
            Array(repeating: (3, 1), count: 5), population: 40, drawn: 5)
        #expect(five > 0 && five < three)

        // Six pieces cannot fit in five cards at all.
        #expect(Hypergeometric.probabilityOfCombination(
            Array(repeating: (3, 1), count: 6), population: 40, drawn: 5) == 0)
    }
}
