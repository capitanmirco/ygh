import Foundation
import Testing
import YGOCore
@testable import YGOPricing

@Suite("Most valuable")
struct MostValuableTests {
    private func quotes(_ table: [Int: (price: Double?, disputed: Bool)])
        -> [CardIdentifier: PriceQuote] {
        table.reduce(into: [:]) { result, pair in
            let card = CardIdentifier(pair.key)
            var prices: [RecordedPrice] = []
            if let price = pair.value.price {
                prices.append(Sample.price(.cardmarket, price))
                // A source disagreeing by more than tenfold marks the card.
                if pair.value.disputed {
                    prices.append(Sample.price(.amazon, price * 500))
                }
            }
            result[card] = PriceQuote(card: card, cardName: "Carta \(pair.key)",
                                      chosenSource: .cardmarket, allSources: prices)
        }
    }

    /// Evidence for R5.AC1: what you hold is worth what the copies are worth
    /// together, so two at ten beats one at fifteen.
    @Test func ranksByTheValueOfTheCopiesHeld() {
        let priced = quotes([1: (10.00, false), 2: (15.00, false), 3: (1.00, false)])
        let items = [
            ValuationItem(card: CardIdentifier(1), quantity: 2),
            ValuationItem(card: CardIdentifier(2), quantity: 1),
            ValuationItem(card: CardIdentifier(3), quantity: 30),
        ]

        let ranking = Valuer.ranked(items, quotes: priced, source: .cardmarket)
        #expect(ranking.count == 3)
        #expect(ranking[0].card == CardIdentifier(3), "trenta a 1 € fanno 30 €")
        #expect(ranking[1].card == CardIdentifier(1), "due a 10 € battono una a 15 €")
        #expect(ranking[2].card == CardIdentifier(2))
        #expect(ranking.map(\.totalValue.cents) == [3_000, 2_000, 1_500])

        // Unit price is reported too, so the ranking is explainable.
        #expect(ranking[1].unitPrice.cents == 1_000)
        #expect(ranking[1].copies == 2)

        // The limit is respected.
        #expect(Valuer.ranked(items, quotes: priced, source: .cardmarket, limit: 2).count == 2)
    }

    /// Evidence for R5.AC2: knowing a card is valuable is no use without
    /// knowing where it is.
    @Test func namesCopyCountAndWhereTheCopiesAre() {
        let priced = quotes([1: (10.00, false)])
        let items = [
            ValuationItem(card: CardIdentifier(1), quantity: 2, location: "Raccoglitore A"),
            ValuationItem(card: CardIdentifier(1), quantity: 1, location: "Scatola B"),
            ValuationItem(card: CardIdentifier(1), quantity: 1, location: nil),
        ]

        let entry = try? #require(
            Valuer.ranked(items, quotes: priced, source: .cardmarket).first)

        #expect(entry?.copies == 4, "le copie si sommano fra le posizioni")
        #expect(entry?.totalValue.cents == 4_000)
        #expect(entry?.locations == ["Raccoglitore A", "Scatola B"])

        let sentence = entry?.sentence ?? ""
        #expect(sentence.contains("4×"))
        #expect(sentence.contains("Raccoglitore A"))
        #expect(sentence.contains("Scatola B"))

        // Copies with no location at all read as unfiled rather than as blank.
        let unfiled = Valuer.ranked(
            [ValuationItem(card: CardIdentifier(1), quantity: 1)],
            quotes: priced, source: .cardmarket).first
        #expect(unfiled?.locations.isEmpty == true)
        #expect(unfiled?.sentence.contains("non archiviate") == true)
    }

    /// Evidence for R5.AC3: a card at the top of the list because one
    /// marketplace invented a number should be checkable at a glance.
    @Test func marksDisputedCardsInTheRanking() {
        let priced = quotes([1: (10.00, true), 2: (8.00, false)])
        let items = [
            ValuationItem(card: CardIdentifier(1), quantity: 1),
            ValuationItem(card: CardIdentifier(2), quantity: 1),
        ]

        let ranking = Valuer.ranked(items, quotes: priced, source: .cardmarket)
        #expect(ranking[0].isDisputed, "la carta con fonti discordi deve essere marcata")
        #expect(!ranking[1].isDisputed)
        #expect(ranking[0].sentence.contains("contestato"))
        #expect(!ranking[1].sentence.contains("contestato"))

        // And the disputed card keeps its place: the flag informs, it does not
        // demote.
        #expect(ranking[0].card == CardIdentifier(1))
        #expect(ranking[0].totalValue.cents == 1_000)
    }
}
