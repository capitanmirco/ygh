import Testing
import YGOCore
@testable import YGOAnalytics

/// A figure computed against the wrong hand is wrong for every card in the
/// deck, so the hand travels with the figure and changes when the order does.
@Suite("Play order")
struct PlayOrderTests {
    /// Evidence for R3.AC4: going second is a different question, and the
    /// answer must move with it.
    @Test func switchingPlayOrderRecomputesEveryFigure() {
        let (modern, modernIndex) = Sample.deck(size: 40, copies: 3, format: .tcg)

        let onThePlay = Hypergeometric.odds(
            for: CardIdentifier(1), in: modern, index: modernIndex, playingFirst: true)
        let onTheDraw = Hypergeometric.odds(
            for: CardIdentifier(1), in: modern, index: modernIndex, playingFirst: false)

        #expect(onThePlay.hand.size == 5)
        #expect(onTheDraw.hand.size == 6)
        #expect(onTheDraw.atLeastOne > onThePlay.atLeastOne,
                "una carta in più non può peggiorare le probabilità")
        #expect(abs((onTheDraw.atLeastOne - onThePlay.atLeastOne) - 0.057) < 0.001)

        // Every threshold moves, not only the first.
        for (first, second) in zip(onThePlay.atLeast, onTheDraw.atLeast) {
            #expect(second >= first)
        }

        // A retro deck already deals six on the play, so its two figures match.
        let (retro, retroIndex) = Sample.deck(size: 40, copies: 3, format: .goat)
        let retroFirst = Hypergeometric.odds(
            for: CardIdentifier(1), in: retro, index: retroIndex, playingFirst: true)
        let retroSecond = Hypergeometric.odds(
            for: CardIdentifier(1), in: retro, index: retroIndex, playingFirst: false)
        #expect(retroFirst.atLeastOne == retroSecond.atLeastOne,
                "in GOAT chi va primo pesca, quindi le due mani coincidono")

        // And a GOAT deck on the play beats an identical TCG deck on the play.
        #expect(retroFirst.atLeastOne > onThePlay.atLeastOne)
    }

    /// Evidence for R3.AC5: the reader should not need to know their format's
    /// first-turn rule to interpret a number.
    @Test func everyReportedFigureCarriesItsHandSize() {
        for format in CardFormat.allCases {
            for playingFirst in [true, false] {
                let (deck, index) = Sample.deck(size: 40, copies: 3, format: format)
                let odds = Hypergeometric.odds(
                    for: CardIdentifier(1), in: deck, index: index, playingFirst: playingFirst)

                #expect(odds.hand.size == OpeningHand.size(
                    format: format, playingFirst: playingFirst))
                #expect(odds.hand.format == format)
                #expect(odds.hand.playingFirst == playingFirst)

                // And it is in the sentence a reader or a screen reader gets.
                #expect(odds.sentence.contains("\(odds.hand.size)"))
                #expect(odds.sentence.contains(format.rawValue))
                #expect(odds.sentence.contains(playingFirst ? "primo" : "secondo"))
            }
        }

        // Combination figures carry it too.
        let (deck, index) = Sample.deck(size: 40, copies: 3, format: .goat)
        let combo = Hypergeometric.odds(
            forCombination: [(CardIdentifier(1), 1)],
            in: deck, index: index, playingFirst: true)
        #expect(combo.hand.size == 6)
        #expect(combo.sentence.contains("6"))
    }
}
