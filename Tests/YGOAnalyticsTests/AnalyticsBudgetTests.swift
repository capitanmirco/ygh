import Foundation
import Testing
import YGOCore
import YGOFeatureAnalytics
@testable import YGOAnalytics

@Suite(.serialized)
struct AnalyticsBudgetTests {
    /// Evidence for NFR1: the figures follow an edit rather than a button,
    /// so they have to be cheap on the largest deck the rules allow.
    @Test func everyExactFigureIsComputedUnderTenMilliseconds() {
        let (deck, index) = Sample.deck(size: 60, copies: 3, extra: 15)
        let cards = Set(deck.slots(in: .main).map(\.card))

        // One untimed pass so first-use costs stay out of the measurement.
        for card in cards {
            _ = Hypergeometric.odds(for: card, in: deck, index: index, playingFirst: true)
        }

        var samples: [Double] = []
        for _ in 0..<20 {
            let started = ContinuousClock.now
            // Every card in a sixty-card deck, its copy-count table, and a
            // combination: the whole screen, recomputed.
            for card in cards {
                _ = Hypergeometric.odds(for: card, in: deck, index: index, playingFirst: true)
            }
            _ = Hypergeometric.copyCountTable(
                for: CardIdentifier(1), in: deck, index: index, playingFirst: true)
            _ = Hypergeometric.odds(
                forCombination: [(CardIdentifier(1), 1), (CardIdentifier(1_000), 1)],
                in: deck, index: index, playingFirst: true)
            samples.append(Double(started.duration(to: .now).components.attoseconds) / 1e15)
        }

        samples.sort()
        let p95 = samples[Int(Double(samples.count) * 0.95)]
        #expect(p95 < 10, "p95 \(String(format: "%.2f", p95)) ms sopra il budget di 10 ms")
    }

    /// Evidence for NFR2: the claim the arithmetic rests on, checked across
    /// every deck size and hand the rules permit.
    @Test func integerArithmeticStaysExactAcrossEveryDeckSize() {
        for population in 40...60 {
            for drawn in [5, 6] {
                // The exact path is available for every real input.
                #expect(Hypergeometric.binomial(population, choose: drawn) != nil,
                        "C(\(population),\(drawn)) deve stare in un Int")

                for copies in 1...3 {
                    let probability = Hypergeometric.probabilityOfAtLeast(
                        1, population: population, copies: copies, drawn: drawn)
                    #expect(probability > 0 && probability < 1)
                    #expect(!probability.isNaN)

                    // The exact probabilities over every count sum to one, to
                    // the last bit a Double can carry.
                    let total = (0...copies).reduce(0.0) { sum, count in
                        sum + Hypergeometric.probabilityOfExactly(
                            count, population: population, copies: copies, drawn: drawn)
                    }
                    #expect(abs(total - 1) < 1e-12,
                            "somma \(total) a N=\(population) K=\(copies) n=\(drawn)")
                }
            }
        }

        // The largest coefficient a legal deck can need, against the ceiling.
        let largest = Hypergeometric.binomial(60, choose: 6)
        #expect(largest == 50_063_860)
        #expect(largest! < Int.max / 1_000_000_000)
    }

    /// Evidence for NFR3: a figure nobody can reproduce cannot be checked, and
    /// the reproduction must survive being made in a different object.
    @Test func seededSimulationReproducesAcrossInstances() {
        let (deck, _) = Sample.deck(size: 40, copies: 3)

        let first = HandSimulator(deck: deck, playingFirst: true)
        let second = HandSimulator(deck: deck, playingFirst: true)

        for seed in [UInt64(0), 1, 42, 20_260_920, UInt64.max] {
            #expect(first.deal(seed: seed).drawn == second.deal(seed: seed).drawn,
                    "seme \(seed) deve dare la stessa mano da due simulatori")
        }

        // A measured share is reproducible too.
        let target = CardIdentifier(1)
        let a = first.measure(hands: 5_000, seed: 99) { $0.holds(target) }
        let b = second.measure(hands: 5_000, seed: 99) { $0.holds(target) }
        #expect(a.share == b.share)
        #expect(a.hands == b.hands)
    }

    /// Evidence for NFR4: a measured share and a computed one are different
    /// kinds of claim, and nothing may present them as the same.
    @Test func simulatedAndExactFiguresAreNeverConfused() {
        let (deck, index) = Sample.deck(size: 40, copies: 3)
        let simulator = HandSimulator(deck: deck, playingFirst: true)
        let target = CardIdentifier(1)

        let exact = Hypergeometric.odds(
            for: target, in: deck, index: index, playingFirst: true)
        let simulated = simulator.measure(hands: 500, seed: 1) { $0.holds(target) }

        // The simulated one says how many hands it saw; the exact one does not
        // claim a sample at all.
        #expect(simulated.sentence.contains("simulate"))
        #expect(simulated.sentence.contains("\(simulated.hands)"))
        #expect(!exact.sentence.contains("simulate"))

        // Both state the hand they assumed.
        #expect(exact.sentence.contains("\(exact.hand.size)"))
        #expect(simulated.sentence.contains("\(simulated.hand.size)"))

        // The simulated one carries a margin; an exact figure needs none.
        #expect(simulated.margin > 0)
        #expect(abs(simulated.share - exact.atLeastOne) < simulated.margin * 3)
    }

    /// Evidence for NFR5: there is no network seam in this feature to stub
    /// out, which is the assertion rather than a stub that proves nothing.
    @Test @MainActor func everyCalculationAnswersOffline() {
        let (deck, index) = Sample.deck(size: 40, copies: 3, extra: 15)

        let model = AnalyticsViewModel()
        model.load(deck: deck, index: index)

        #expect(model.mainBreakdown?.totalCards == 40)
        #expect(model.extraBreakdown?.totalCards == 15)
        #expect(!model.odds.isEmpty)
        #expect(model.table != nil)
        #expect(model.hand?.size == 5)

        model.setPlayingFirst(false)
        #expect(model.hand?.size == 6)
        #expect(model.odds.first?.hand.size == 6)

        model.dealHand(seed: 1)
        #expect(model.dealtHand.count == 6)

        // Everything above read a deck and an index already in memory.
        #expect(model.sentences.count == model.odds.count)
    }
}
