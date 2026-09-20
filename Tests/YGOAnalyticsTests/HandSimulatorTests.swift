import Testing
import YGOCore
@testable import YGOAnalytics

@Suite("Hand simulator")
struct HandSimulatorTests {
    /// Evidence for R5.AC1: a dealt hand is one a deck could really produce.
    @Test func dealtHandHoldsTheFormatsSizeAndNoExtraCopies() {
        let (deck, _) = Sample.deck(size: 40, copies: 3, extra: 15)
        let simulator = HandSimulator(deck: deck, playingFirst: true)

        #expect(simulator.population == 40, "l'Extra Deck non si pesca")
        #expect(simulator.hand.size == 5)

        var generator = SplitMix64(seed: 1)
        var seen: Set<[CardIdentifier]> = []

        for _ in 0..<50 {
            let deal = simulator.deal(using: &generator)
            #expect(deal.drawn.count == 5)
            #expect(deal.remainingCount == 35)
            // No card appears more often than the deck holds it.
            #expect(deal.copies(of: CardIdentifier(1)) <= 3)
            for card in Set(deal.drawn) where card != CardIdentifier(1) {
                #expect(deal.copies(of: card) <= 1)
            }
            seen.insert(deal.drawn)
        }

        #expect(seen.count > 1, "mani ripetute devono differire")

        // A retro format deals six.
        let (retro, _) = Sample.deck(size: 40, copies: 3, format: .goat)
        #expect(HandSimulator(deck: retro, playingFirst: true).deal(seed: 1).drawn.count == 6)
    }

    /// Evidence for R5.AC2: a figure nobody can reproduce cannot be checked.
    @Test func oneSeedDealsOneSequence() {
        let (deck, _) = Sample.deck(size: 40, copies: 3)
        let simulator = HandSimulator(deck: deck, playingFirst: true)

        var first = SplitMix64(seed: 20_260_920)
        var second = SplitMix64(seed: 20_260_920)

        for _ in 0..<20 {
            #expect(simulator.deal(using: &first).drawn
                    == simulator.deal(using: &second).drawn)
        }

        // A different seed gives a different sequence.
        #expect(simulator.deal(seed: 1).drawn != simulator.deal(seed: 2).drawn)

        // And the same seed twice gives the same hand.
        #expect(simulator.deal(seed: 99).drawn == simulator.deal(seed: 99).drawn)

        // The generator itself is deterministic, which is what all of the
        // above rests on.
        var a = SplitMix64(seed: 0), b = SplitMix64(seed: 0)
        #expect((0..<10).map { _ in a.next() } == (0..<10).map { _ in b.next() })
    }

    /// Evidence for R5.AC3: drawing takes from what is left, not from a fresh
    /// deck each time.
    @Test func drawingTakesFromWhatIsLeft() {
        let (deck, _) = Sample.deck(size: 40, copies: 3)
        let simulator = HandSimulator(deck: deck, playingFirst: true)
        var deal = simulator.deal(seed: 7)

        var remaining = deal.remainingCount
        #expect(remaining == 35)

        for step in 1...10 {
            let card = deal.draw()
            #expect(card != nil)
            #expect(deal.remainingCount == remaining - 1)
            #expect(deal.drawn.count == 5 + step)
            remaining = deal.remainingCount
        }

        // Never more copies than the deck holds, however deep it is drawn.
        #expect(deal.copies(of: CardIdentifier(1)) <= 3)

        // Drawing the whole deck holds every copy, and then stops.
        while deal.draw() != nil {}
        #expect(deal.drawn.count == 40)
        #expect(deal.remainingCount == 0)
        #expect(deal.copies(of: CardIdentifier(1)) == 3)
        #expect(deal.draw() == nil, "un mazzo finito non pesca più")
    }
}
