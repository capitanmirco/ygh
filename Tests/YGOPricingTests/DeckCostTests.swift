import Foundation
import Testing
import YGOCore
@testable import YGOPricing

@Suite("Deck cost")
struct DeckCostTests {
    private let at = Date(timeIntervalSince1970: 1_758_000_000)

    private func quotes(_ table: [Int: Double?]) -> [CardIdentifier: PriceQuote] {
        table.reduce(into: [:]) { result, pair in
            let card = CardIdentifier(pair.key)
            let prices = pair.value.map { [Sample.price(.cardmarket, $0)] } ?? []
            result[card] = PriceQuote(card: card, cardName: "Carta \(pair.key)",
                                      chosenSource: .cardmarket, allSources: prices)
        }
    }

    private func deck(_ slots: [(card: Int, section: DeckSection, quantity: Int)]) -> Deck {
        Deck(id: 1, name: "Prova", format: .goat,
             slots: slots.map {
                 DeckSlot(artwork: ArtworkIdentifier($0.card), card: CardIdentifier($0.card),
                          section: $0.section, quantity: $0.quantity)
             },
             createdAt: at, updatedAt: at)
    }

    /// Evidence for R4.AC1: a side-deck copy costs what a main-deck copy costs.
    @Test func sumsEveryCopyAcrossEverySection() {
        let built = deck([
            (1, .main, 3), (2, .extra, 2), (3, .side, 1),
        ])
        let priced = quotes([1: 4.00, 2: 10.00, 3: 2.50])

        let cost = Valuer.cost(of: built, quotes: priced, source: .cardmarket)
        #expect(cost.total.cents == 1_200 + 2_000 + 250)
        #expect(cost.total.formatted == "€34.50")
        #expect(cost.copiesValued == 6)
        #expect(cost.isComplete)
    }

    /// Evidence for R4.AC2: the completion cost is the one a duelist acts on.
    @Test func completionCostsOnlyWhatIsMissing() {
        let built = deck([(1, .main, 3)])
        let priced = quotes([1: 4.00])

        let full = Valuer.cost(of: built, quotes: priced, source: .cardmarket)
        #expect(full.total.cents == 1_200, "tre copie a 4 € fanno 12 €")

        // The shortfall comes from collection-tracker: one owned, two missing.
        let shortfall = ShortfallCalculator.shortfall(
            deck: built, names: [:], owned: [CardIdentifier(1): 1])
        #expect(shortfall.first?.missing == 2)

        let completion = Valuer.completionCost(
            shortfall: shortfall, quotes: priced, source: .cardmarket)
        #expect(completion.total.cents == 800, "due copie mancanti a 4 € fanno 8 €")
        #expect(completion.copiesValued == 2)
    }

    /// Evidence for R4.AC3: owning a deck costs nothing more, but the deck is
    /// still worth something.
    @Test func aFullyOwnedDeckCostsNothingToComplete() {
        let built = deck([(1, .main, 3), (2, .main, 2)])
        let priced = quotes([1: 4.00, 2: 1.00])

        let shortfall = ShortfallCalculator.shortfall(
            deck: built, names: [:],
            owned: [CardIdentifier(1): 3, CardIdentifier(2): 2])
        #expect(shortfall.isEmpty)

        let completion = Valuer.completionCost(
            shortfall: shortfall, quotes: priced, source: .cardmarket)
        #expect(completion.total.cents == 0)
        #expect(completion.totalCopies == 0)
        #expect(completion.isComplete)

        let full = Valuer.cost(of: built, quotes: priced, source: .cardmarket)
        #expect(full.total.cents == 1_400, "costruirlo da zero costa comunque")
    }

    /// Evidence for R4.AC4: what a card contributes is price times copies, not
    /// price alone.
    @Test func ranksTheDecksDearestCardsByWhatTheyContribute() {
        let built = deck([(1, .main, 3), (2, .main, 1), (3, .main, 1)])
        // Card 1 is cheaper each but held three times.
        let priced = quotes([1: 6.00, 2: 15.00, 3: 1.00])

        let dearest = Valuer.dearestCards(in: built, quotes: priced, source: .cardmarket)
        #expect(dearest.count == 3)
        #expect(dearest[0].card == CardIdentifier(1), "18 € battono 15 €")
        #expect(dearest[0].totalValue.cents == 1_800)
        #expect(dearest[0].copies == 3)
        #expect(dearest[1].card == CardIdentifier(2))
        #expect(dearest.map(\.totalValue.cents) == [1_800, 1_500, 100])
    }

    /// Evidence for R4.AC5: a deck cost that silently covers nine cards of ten
    /// is worse than one that admits it.
    @Test func excludesUnpricedCardsAndSaysHowMany() {
        let built = deck([(1, .main, 3), (2, .main, 2)])
        let priced = quotes([1: 4.00, 2: nil])

        let cost = Valuer.cost(of: built, quotes: priced, source: .cardmarket)
        #expect(cost.total.cents == 1_200)
        #expect(cost.copiesValued == 3)
        #expect(cost.copiesUnpriced == 2)
        #expect(!cost.isComplete)
        #expect(cost.sentence.contains("2 senza prezzo"))

        // The unpriced card does not appear in the ranking either.
        let dearest = Valuer.dearestCards(in: built, quotes: priced, source: .cardmarket)
        #expect(dearest.map(\.card) == [CardIdentifier(1)])
    }
}
