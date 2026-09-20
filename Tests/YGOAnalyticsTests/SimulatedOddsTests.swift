import Testing
import YGOCore
@testable import YGOAnalytics

@Suite("Simulated odds")
struct SimulatedOddsTests {
    /// Evidence for R5.AC4, and the check that matters most here: the
    /// simulation must land on the figure the closed form gives. If the two
    /// disagree, one of them is wrong, and this is how we find out which.
    @Test func simulationConvergesOnTheExactFigure() {
        let (deck, _) = Sample.deck(size: 40, copies: 3)
        let simulator = HandSimulator(deck: deck, playingFirst: true)
        let target = CardIdentifier(1)

        let exact = Hypergeometric.probabilityOfAtLeast(
            1, population: 40, copies: 3, drawn: 5)
        #expect(abs(exact - 0.338) < 0.0005)

        let simulated = simulator.measure(hands: 50_000, seed: 20_260_920) {
            $0.holds(target)
        }

        #expect(abs(simulated.share - exact) < 0.01,
                "simulato \(simulated.share) contro esatto \(exact)")
        #expect(abs(simulated.share - exact) < simulated.margin * 2,
                "lo scarto deve stare dentro il margine dichiarato")

        // It also converges for a threshold the single figure does not cover.
        let exactTwo = Hypergeometric.probabilityOfAtLeast(
            2, population: 40, copies: 3, drawn: 5)
        let simulatedTwo = simulator.measure(hands: 50_000, seed: 7) {
            $0.copies(of: target) >= 2
        }
        #expect(abs(simulatedTwo.share - exactTwo) < 0.01)

        // And for a combination.
        let (comboDeck, _) = Sample.deck(size: 40, copies: 3)
        var slots = comboDeck.slots.filter { $0.card != CardIdentifier(1_000) }
        slots.append(Sample.slot(2, quantity: 3))
        let paired = Deck(id: 2, name: "Combo", format: .tcg,
                          slots: slots + [Sample.slot(1_500, quantity: 1)],
                          createdAt: Sample.at, updatedAt: Sample.at)
        let pairedSimulator = HandSimulator(deck: paired, playingFirst: true)
        let exactCombo = Hypergeometric.probabilityOfCombination(
            [(3, 1), (3, 1)], population: pairedSimulator.population, drawn: 5)
        let simulatedCombo = pairedSimulator.measure(hands: 50_000, seed: 3) {
            $0.holds(CardIdentifier(1)) && $0.holds(CardIdentifier(2))
        }
        #expect(abs(simulatedCombo.share - exactCombo) < 0.01,
                "combo simulata \(simulatedCombo.share) contro esatta \(exactCombo)")
    }

    /// Evidence for R5.AC5: a share without its sample count is not a claim
    /// anyone can weigh.
    @Test func everySimulatedResultCarriesItsSampleCount() {
        let (deck, _) = Sample.deck(size: 40, copies: 3)
        let simulator = HandSimulator(deck: deck, playingFirst: true)
        let target = CardIdentifier(1)

        let rough = simulator.measure(hands: 100, seed: 1) { $0.holds(target) }
        let precise = simulator.measure(hands: 100_000, seed: 1) { $0.holds(target) }

        #expect(rough.hands == 100)
        #expect(precise.hands == 100_000)
        #expect(rough.sentence.contains("100 mani"))
        #expect(precise.sentence.contains("100000 mani"))

        // And the margin says which of the two to trust.
        #expect(rough.margin > precise.margin * 10,
                "cento mani devono dichiarare un margine molto più largo")
        #expect(precise.margin < 0.01)

        // A measurement over no hands claims nothing.
        let none = simulator.measure(hands: 0) { _ in true }
        #expect(none.hands == 0)
        #expect(none.share == 0)
        #expect(none.margin == 1, "zero mani non autorizzano alcuna fiducia")

        // The hand size travels with it too.
        #expect(precise.hand.size == 5)
        #expect(precise.sentence.contains("5"))
    }
}
