import Testing
import YGOCore
@testable import YGOAnalytics

/// Checked against figures worked out independently, not against the code's
/// own output. The targets were computed before any of this existed.
@Suite("Hypergeometric")
struct HypergeometricTests {
    /// Evidence for R1.AC1: the figure duelists have quoted for years.
    /// Three copies in forty, opening five, is 33.8%.
    @Test func threeCopiesInFortyOnFiveCardsIsThirtyFourPercent() {
        let exact = Hypergeometric.probabilityOfAtLeast(
            1, population: 40, copies: 3, drawn: 5)
        #expect(abs(exact - 0.338) < 0.0005, "atteso 0.338, ricevuto \(exact)")

        // Through the deck-shaped entry point, which must agree.
        let (deck, index) = Sample.deck(size: 40, copies: 3)
        let odds = Hypergeometric.odds(
            for: CardIdentifier(1), in: deck, index: index, playingFirst: true)
        #expect(abs(odds.atLeastOne - 0.338) < 0.0005)
        #expect(odds.hand.size == 5)
        #expect(odds.cardName == "Bersaglio")

        // The six-card hand a retro format deals is 5.7 points better.
        let onSix = Hypergeometric.probabilityOfAtLeast(
            1, population: 40, copies: 3, drawn: 6)
        #expect(abs(onSix - 0.394) < 0.0005, "atteso 0.394, ricevuto \(onSix)")
        #expect(abs((onSix - exact) - 0.057) < 0.001,
                "la differenza fra 5 e 6 carte deve essere 5.7 punti")

        // Sixty cards costs 10.4 points against forty.
        let inSixty = Hypergeometric.probabilityOfAtLeast(
            1, population: 60, copies: 3, drawn: 5)
        #expect(abs(inSixty - 0.233) < 0.0005, "atteso 0.233, ricevuto \(inSixty)")
    }

    /// Evidence for R1.AC2: a figure for each number of copies the deck holds,
    /// and asking for more can never be more likely.
    @Test func reportsAProbabilityForEachNumberOfCopiesHeld() {
        let (deck, index) = Sample.deck(size: 40, copies: 3)
        let odds = Hypergeometric.odds(
            for: CardIdentifier(1), in: deck, index: index, playingFirst: true)

        #expect(odds.atLeast.count == 3)
        #expect(odds.atLeast == odds.atLeast.sorted(by: >), "le soglie devono scendere")
        #expect(odds.atLeast.allSatisfy { $0 >= 0 && $0 <= 1 })

        // At least one is one minus the chance of drawing none.
        let none = Hypergeometric.probabilityOfExactly(
            0, population: 40, copies: 3, drawn: 5)
        #expect(abs(odds.atLeast[0] - (1 - none)) < 1e-12)

        // The exact probabilities across every count sum to one.
        let total = (0...3).reduce(0.0) { sum, count in
            sum + Hypergeometric.probabilityOfExactly(
                count, population: 40, copies: 3, drawn: 5)
        }
        #expect(abs(total - 1) < 1e-12, "le probabilità esatte devono sommare a 1")
    }

    /// Evidence for R1.AC3: the extra and side sections are not drawn from.
    @Test func countsOnlyTheMainSection() {
        let (plain, plainIndex) = Sample.deck(size: 40, copies: 3)
        let before = Hypergeometric.odds(
            for: CardIdentifier(1), in: plain, index: plainIndex, playingFirst: true)

        let (withExtra, extraIndex) = Sample.deck(size: 40, copies: 3, extra: 15)
        let after = Hypergeometric.odds(
            for: CardIdentifier(1), in: withExtra, index: extraIndex, playingFirst: true)
        #expect(after.atLeastOne == before.atLeastOne,
                "quindici carte nell'Extra non cambiano nulla")
        #expect(withExtra.totalCount == plain.totalCount + 15)

        // One more main-deck card does change it.
        let (bigger, biggerIndex) = Sample.deck(size: 41, copies: 3)
        let larger = Hypergeometric.odds(
            for: CardIdentifier(1), in: bigger, index: biggerIndex, playingFirst: true)
        #expect(larger.atLeastOne < before.atLeastOne)
    }

    /// Evidence for R1.AC4: asking about a card you have not added yet is how
    /// you decide whether to add it.
    @Test func reportsZeroForACardTheDeckDoesNotHold() {
        let (deck, index) = Sample.deck(size: 40, copies: 3)
        let odds = Hypergeometric.odds(
            for: CardIdentifier(99_999), in: deck, index: index, playingFirst: true)

        #expect(odds.copies == 0)
        #expect(odds.atLeastOne == 0)
        #expect(!odds.sentence.isEmpty)
    }

    /// Evidence for R1.AC5: drawing more cards than the deck holds draws all
    /// of them, rather than dividing by a negative count.
    @Test func reportsCertaintyWhenTheDeckIsSmallerThanTheHand() {
        let (deck, index) = Sample.deck(size: 3, copies: 1)
        let odds = Hypergeometric.odds(
            for: CardIdentifier(1), in: deck, index: index, playingFirst: true)

        #expect(odds.atLeastOne == 1.0)
        #expect(Hypergeometric.probabilityOfAtLeast(
            1, population: 3, copies: 1, drawn: 5) == 1.0)

        // An empty deck holds nothing and offers nothing.
        #expect(Hypergeometric.probabilityOfAtLeast(
            1, population: 0, copies: 0, drawn: 5) == 0)
    }

    /// The claim the whole arithmetic rests on: the coefficients an opening
    /// hand needs are small enough to be exact.
    @Test func largestCoefficientASixtyCardDeckNeedsIsExact() {
        // C(60, 6), computed independently: 60·59·58·57·56·55 / 720.
        let expected = (60 * 59 * 58 * 57 * 56 * 55) / 720
        #expect(expected == 50_063_860)
        #expect(Hypergeometric.binomial(60, choose: 6) == 50_063_860)
        // The exact path really is the one a real deck takes.
        #expect(Hypergeometric.binomial(60, choose: 6) != nil)

        // And it is nowhere near the ceiling.
        #expect(50_063_860 < Int.max / 1_000_000_000)

        // Known small values, so an off-by-one in the loop cannot hide.
        #expect(Hypergeometric.binomial(40, choose: 5) == 658_008)
        #expect(Hypergeometric.binomial(5, choose: 0) == 1)
        #expect(Hypergeometric.binomial(5, choose: 5) == 1)
        #expect(Hypergeometric.binomial(5, choose: 6) == 0)
        #expect(Hypergeometric.binomial(5, choose: -1) == 0)

        // Outside this feature's domain the coefficient will not fit, and the
        // function says so rather than trapping.
        #expect(Hypergeometric.binomial(200, choose: 100) == nil)
    }
}
