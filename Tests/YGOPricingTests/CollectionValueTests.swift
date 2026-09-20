import Foundation
import Testing
import YGOCore
@testable import YGOPricing

@Suite("Collection value")
struct CollectionValueTests {
    private func quotes(_ table: [Int: [RecordedPrice]]) -> [CardIdentifier: PriceQuote] {
        table.reduce(into: [:]) { result, pair in
            let card = CardIdentifier(pair.key)
            result[card] = PriceQuote(card: card, cardName: "Carta \(pair.key)",
                                      chosenSource: .cardmarket, allSources: pair.value)
        }
    }

    /// Evidence for R3.AC1.
    @Test func sumsEachCopyAtTheChosenSource() {
        let priced = quotes([
            1: [Sample.price(.cardmarket, 2.00)],
            2: [Sample.price(.cardmarket, 5.00)],
        ])
        let items = [
            ValuationItem(card: CardIdentifier(1), quantity: 3),
            ValuationItem(card: CardIdentifier(2), quantity: 1),
        ]

        let value = Valuer.value(items, quotes: priced, source: .cardmarket)
        #expect(value.total.cents == 1_100, "tre a 2 € più una a 5 € fanno 11 €")
        #expect(value.total.formatted == "€11.00")
        #expect(value.copiesValued == 4)
        #expect(value.copiesUnpriced == 0)
        #expect(value.isComplete)
        #expect(value.source == .cardmarket)
    }

    /// Evidence for R3.AC2: a card with no price is not a free card, and the
    /// total must say how much of the collection it could not reach.
    @Test func excludesUnpricedCopiesAndSaysHowMany() {
        let priced = quotes([
            1: [Sample.price(.cardmarket, 2.00)],
            2: [],                                   // nessuna fonte
            3: [Sample.price(.amazon, 50.00)],       // ma non quella scelta
        ])
        let items = [
            ValuationItem(card: CardIdentifier(1), quantity: 2),
            ValuationItem(card: CardIdentifier(2), quantity: 1),
            ValuationItem(card: CardIdentifier(3), quantity: 4),
        ]

        let value = Valuer.value(items, quotes: priced, source: .cardmarket)
        #expect(value.total.cents == 400, "solo le due copie quotate contano")
        #expect(value.copiesValued == 2)
        #expect(value.copiesUnpriced == 5)
        #expect(value.totalCopies == 7)
        #expect(!value.isComplete)
        #expect(value.sentence.contains("5 senza prezzo"))
    }

    /// Evidence for R3.AC3: the parts must account for the whole, or the
    /// breakdown misleads.
    @Test func perRarityValuesSumToTheTotal() {
        let priced = quotes([
            1: [Sample.price(.cardmarket, 1.00)],
            2: [Sample.price(.cardmarket, 10.00)],
            3: [Sample.price(.cardmarket, 4.00)],
        ])
        let items = [
            ValuationItem(card: CardIdentifier(1), quantity: 3, rarity: "Common"),
            ValuationItem(card: CardIdentifier(2), quantity: 1, rarity: "Secret Rare"),
            ValuationItem(card: CardIdentifier(3), quantity: 2, rarity: "Common"),
            ValuationItem(card: CardIdentifier(1), quantity: 1, rarity: nil),
        ]

        let whole = Valuer.value(items, quotes: priced, source: .cardmarket)
        let byRarity = Valuer.value(items, quotes: priced, source: .cardmarket) { $0.rarity }

        #expect(byRarity["Common"]?.total.cents == 300 + 800)
        #expect(byRarity["Secret Rare"]?.total.cents == 1_000)
        #expect(byRarity[nil as String?]?.total.cents == 100,
                "le copie senza stampa vanno riportate")

        let parts = byRarity.values.reduce(0) { $0 + $1.total.cents }
        #expect(parts == whole.total.cents, "le rarità devono sommare al totale")
        #expect(byRarity.values.reduce(0) { $0 + $1.copiesValued } == whole.copiesValued)
    }

    /// Evidence for R3.AC4: the same property for locations, unfiled included.
    @Test func perLocationValuesSumToTheTotal() {
        let priced = quotes([
            1: [Sample.price(.cardmarket, 2.00)],
            2: [Sample.price(.cardmarket, 7.50)],
        ])
        let items = [
            ValuationItem(card: CardIdentifier(1), quantity: 2, location: "Raccoglitore A"),
            ValuationItem(card: CardIdentifier(2), quantity: 1, location: "Scatola B"),
            ValuationItem(card: CardIdentifier(1), quantity: 3, location: nil),
        ]

        let whole = Valuer.value(items, quotes: priced, source: .cardmarket)
        let byLocation = Valuer.value(items, quotes: priced, source: .cardmarket) { $0.location }

        #expect(byLocation["Raccoglitore A"]?.total.cents == 400)
        #expect(byLocation["Scatola B"]?.total.cents == 750)
        #expect(byLocation[nil as String?]?.total.cents == 600,
                "le copie non archiviate contano comunque")

        let parts = byLocation.values.reduce(0) { $0 + $1.total.cents }
        #expect(parts == whole.total.cents)
    }

    /// Evidence for R3.AC5: the figure worth having is the comparison, not
    /// either number alone.
    @Test func reportsValueBesideWhatWasPaid() {
        let priced = quotes([1: [Sample.price(.cardmarket, 10.00)]])
        let items = [ValuationItem(card: CardIdentifier(1), quantity: 3)]

        let value = Valuer.value(items, quotes: priced, source: .cardmarket)
        // What the collection tracker recorded as paid, in the same currency.
        let paid = Money(amount: 12.00, currency: .eur)

        #expect(value.total.cents == 3_000)
        let difference = value.total.subtracting(paid)
        #expect(difference?.cents == 1_800)
        #expect(difference?.formatted == "€18.00")

        // Across currencies the comparison is refused rather than invented.
        #expect(value.total.subtracting(Money(amount: 12, currency: .usd)) == nil)
    }
}
