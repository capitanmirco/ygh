import Foundation
import Testing
import YGOCore
@testable import YGOPricing

/// The qualifications are carried by the type, so a total cannot be built
/// without them and cannot be remembered in one screen and forgotten in
/// another.
@Suite("Valuation honesty")
struct ValuationHonestyTests {
    private func valuation(
        source: PriceSource = .cardmarket,
        unpriced: Int = 0,
        disputed: Bool = false
    ) -> Valuation {
        var prices = [Sample.price(source, 10.00)]
        if disputed { prices.append(Sample.price(.amazon, 5_000)) }

        let quote = PriceQuote(card: CardIdentifier(1), cardName: "Carta 1",
                               chosenSource: source, allSources: prices)
        var quotes = [CardIdentifier(1): quote]
        if unpriced > 0 {
            quotes[CardIdentifier(2)] = PriceQuote(
                card: CardIdentifier(2), cardName: "Carta 2",
                chosenSource: source, allSources: [])
        }

        var items = [ValuationItem(card: CardIdentifier(1), quantity: 2)]
        if unpriced > 0 {
            items.append(ValuationItem(card: CardIdentifier(2), quantity: unpriced))
        }
        return Valuer.value(items, quotes: quotes, source: source)
    }

    /// Evidence for R6.AC1: a number without its source is not a price.
    @Test func everyFigureNamesItsSource() {
        for source in PriceSource.allCases {
            let value = valuation(source: source)
            #expect(value.source == source)
            #expect(value.sentence.contains(source.displayName))
            // And the currency follows the source rather than being assumed.
            #expect(value.total.currency == source.currency)
        }

        // Cardmarket in euro, TCGplayer in dollars, never blended.
        #expect(valuation(source: .cardmarket).total.formatted.hasPrefix("€"))
        #expect(valuation(source: .tcgplayer).total.formatted.hasPrefix("$"))
    }

    /// Evidence for R6.AC2: a figure is exactly as old as the catalog.
    @Test func everyFigureCarriesWhenPricesWereObserved() {
        let value = valuation()
        #expect(value.observedAt == Sample.observedAt)

        // A valuation over nothing priced has no observation to report, and
        // says nothing rather than inventing a time.
        let empty = Valuer.value([], quotes: [:], source: .cardmarket)
        #expect(empty.observedAt == nil)
        #expect(empty.total.cents == 0)
        #expect(empty.totalCopies == 0)
    }

    /// Evidence for R6.AC3: prices are per card, not per printing, so a Secret
    /// Rare and a Common of one card carry the same figure. No care in the
    /// arithmetic changes that, and the figure has to say so.
    @Test func everyFigureSaysItIsAnEstimateAndWhy() {
        let value = valuation()

        #expect(value.sentence.contains("Stima"))
        #expect(!value.sentence.lowercased().contains("perizia,"),
                "non deve rivendicare una perizia")

        let reason = value.estimateReason
        #expect(reason.contains("per carta"))
        #expect(reason.contains("stampa"))
        #expect(reason.contains("Cardmarket"))
        #expect(reason.contains("Secret Rare"))

        // The reason names whichever source was chosen.
        #expect(valuation(source: .tcgplayer).estimateReason.contains("TCGplayer"))
    }

    /// Evidence for R6.AC4: a figure covering nine cards of ten must say so
    /// rather than presenting itself as covering all ten.
    @Test func everyFigureReportsWhatItCouldNotValue() {
        let complete = valuation()
        #expect(complete.isComplete)
        #expect(complete.copiesUnpriced == 0)
        #expect(complete.sentence.contains("tutte le 2 copie"))

        let partial = valuation(unpriced: 3)
        #expect(!partial.isComplete)
        #expect(partial.copiesValued == 2)
        #expect(partial.copiesUnpriced == 3)
        #expect(partial.totalCopies == 5)
        #expect(partial.sentence.contains("2 copie di 5"))
        #expect(partial.sentence.contains("3 senza prezzo"))

        // Disputed cards are counted and stated too.
        let contested = valuation(disputed: true)
        #expect(contested.disputedCards == 1)
        #expect(contested.sentence.contains("contestate"))
        #expect(contested.total.cents == 2_000,
                "e il totale le comprende comunque")

        // A figure with nothing wrong with it does not warn about nothing.
        #expect(!complete.sentence.contains("contestate"))
        #expect(!complete.sentence.contains("senza prezzo"))
    }
}
