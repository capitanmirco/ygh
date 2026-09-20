import Foundation
import Testing
import YGOCore
@testable import YGOPricing

@Suite("Price quote")
struct PriceQuoteTests {
    private func quote(
        _ prices: [RecordedPrice],
        source: PriceSource = .cardmarket,
        name: String = "Gate Guardian"
    ) -> PriceQuote {
        PriceQuote(card: CardIdentifier(1), cardName: name,
                   chosenSource: source, allSources: prices)
    }

    /// Evidence for R1.AC1: one source, named, never an average. The average of
    /// €999.99 and €0.02 would be €500, a figure describing nothing that exists.
    @Test func reportsTheChosenSourcesFigure() {
        let onCardmarket = quote(Sample.gateGuardian, source: .cardmarket)
        #expect(onCardmarket.price?.amount == 0.02)
        #expect(onCardmarket.price?.currency == .eur)

        let onAmazon = quote(Sample.gateGuardian, source: .amazon)
        #expect(onAmazon.price?.amount == 999.99)
        #expect(onAmazon.price?.currency == .usd)

        // Changing the source changes the figure, which is the point of a
        // chosen source rather than a blend of five.
        #expect(onCardmarket.price != onAmazon.price)
        #expect(onCardmarket.sentence.contains("Cardmarket"))
        #expect(onAmazon.sentence.contains("Amazon"))
    }

    /// Evidence for R1.AC2: the spread is the most useful thing the data says.
    @Test func reportsEverySourceAlongsideTheChosenOne() {
        let quoted = quote(Sample.gateGuardian)

        #expect(quoted.allSources.count == 5)
        #expect(Set(quoted.allSources.map(\.source)) == Set(PriceSource.allCases))
        for record in quoted.allSources {
            #expect(record.money.currency == record.source.currency)
        }

        // Ordered stably, so the list does not shuffle between reads.
        #expect(quoted.allSources.map(\.source.rawValue)
                == quoted.allSources.map(\.source.rawValue).sorted())
    }

    /// Evidence for R1.AC3: 289 cards carry no price from any source, and a
    /// missing figure is not a free card.
    @Test func anUnpricedCardIsUnpricedNotZero() {
        let unpriced = quote([], name: "Carta senza prezzo")
        #expect(unpriced.price == nil)
        #expect(!unpriced.isPriced)
        #expect(unpriced.sentence.contains("nessun prezzo"))

        // Priced elsewhere but not on the chosen source is the same case.
        let elsewhere = quote([Sample.price(.amazon, 5)], source: .cardmarket)
        #expect(elsewhere.price == nil)
        #expect(elsewhere.allSources.count == 1)

        // A genuine zero is a price, and is not the same thing.
        let free = quote([Sample.price(.cardmarket, 0)])
        #expect(free.price?.cents == 0)
        #expect(free.isPriced)
    }

    /// Evidence for R1.AC4: a figure is exactly as old as the catalog, and
    /// should say so.
    @Test func carriesWhenThePriceWasObserved() {
        let quoted = quote(Sample.gateGuardian)
        #expect(quoted.observedAt == Sample.observedAt)
        #expect(quoted.allSources.allSatisfy { $0.observedAt == Sample.observedAt })

        // Even when the chosen source has no figure, the observation time of
        // what is known is still reported.
        let elsewhere = quote([Sample.price(.amazon, 5)], source: .cardmarket)
        #expect(elsewhere.observedAt == Sample.observedAt)

        #expect(quote([]).observedAt == nil)
    }

    /// Evidence for R1.AC5: the source publishes one figure per card, so a
    /// Secret Rare and a Common carry the same price. This is the reason a
    /// collection's value is an estimate.
    @Test func everyPrintingOfACardCostsTheSame() async throws {
        let lookup = StubPriceLookup(table: [CardIdentifier(1): Sample.gateGuardian])
        let quoter = PriceQuoter(lookup: lookup, source: .cardmarket)

        let quotes = try await quoter.quotes(
            for: [CardIdentifier(1)], names: [CardIdentifier(1): "Gate Guardian"])
        let quoted = try #require(quotes[CardIdentifier(1)])

        // Two printings are two rows in the collection and one price here:
        // the lookup is keyed by card, because the source is.
        #expect(quoted.price?.amount == 0.02)
        #expect(quoted.cardName == "Gate Guardian")

        // A card the lookup does not know is quoted as unpriced rather than
        // omitted, so a caller cannot lose it silently.
        let withUnknown = try await quoter.quotes(
            for: [CardIdentifier(1), CardIdentifier(2)])
        #expect(withUnknown.count == 2)
        #expect(withUnknown[CardIdentifier(2)]?.isPriced == false)
    }
}
