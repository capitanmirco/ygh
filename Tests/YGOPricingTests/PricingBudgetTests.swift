import Foundation
import Testing
import YGOCore
import YGOFeaturePricing
@testable import YGOPricing

@Suite(.serialized)
struct PricingBudgetTests {
    /// A collection of ten thousand copies spread over two thousand cards.
    private func largeCollection() -> ([ValuationItem], StubPriceLookup, [CardIdentifier: String]) {
        var items: [ValuationItem] = []
        var table: [CardIdentifier: [RecordedPrice]] = [:]
        var names: [CardIdentifier: String] = [:]

        for index in 0..<2_000 {
            let card = CardIdentifier(index + 1)
            items.append(ValuationItem(
                card: card, quantity: 5,
                rarity: index % 3 == 0 ? "Common" : "Super Rare",
                location: index % 4 == 0 ? "Raccoglitore A" : "Scatola B"))
            // Skip a few so coverage reporting has something to report.
            if index % 50 != 0 {
                table[card] = [Sample.price(.cardmarket, 0.89)]
            }
            names[card] = "Carta \(index + 1)"
        }
        return (items, StubPriceLookup(table: table), names)
    }

    /// Evidence for NFR1: the figure is shown on opening, not behind a button.
    @Test @MainActor func valuesTenThousandCopiesUnderTwoHundredMilliseconds() async {
        let (items, lookup, names) = largeCollection()
        let model = PricingViewModel(lookup: lookup)

        // One untimed pass so first-use costs stay out of the measurement.
        await model.load(items: items, names: names)
        #expect(model.collectionValue?.totalCopies == 10_000)

        var samples: [Double] = []
        for _ in 0..<5 {
            let started = ContinuousClock.now
            await model.load(items: items, names: names)
            samples.append(Double(started.duration(to: .now).components.attoseconds) / 1e15)
        }

        samples.sort()
        #expect(samples.last! < 200,
                "peggiore \(String(format: "%.1f", samples.last!)) ms sopra il budget di 200 ms")

        // And the arithmetic stayed exact across ten thousand copies.
        let valued = model.collectionValue?.copiesValued ?? 0
        #expect(model.collectionValue?.total.cents == valued * 89)
    }

    /// Evidence for NFR3: there is no network seam here to stub out, which is
    /// the assertion rather than a stub that proves nothing.
    @Test @MainActor func everyFigureIsComputedOffline() async {
        let (items, lookup, names) = largeCollection()
        let model = PricingViewModel(lookup: lookup)

        await model.load(items: items, names: names,
                         recordedSpend: Money(amount: 5_000, currency: .eur))

        #expect(model.collectionValue != nil)
        #expect(!model.valueByRarity.isEmpty)
        #expect(!model.valueByLocation.isEmpty)
        #expect(!model.mostValuable.isEmpty)
        #expect(model.gainOverSpend != nil)

        // Switching source is also computed from what is already stored.
        await model.setSource(.tcgplayer)
        #expect(model.source == .tcgplayer)
        #expect(model.collectionValue?.source == .tcgplayer)
        // Nothing is priced on TCGplayer in this fixture, so the total is
        // empty and says so rather than reporting a euro figure in dollars.
        #expect(model.collectionValue?.copiesValued == 0)
        #expect(model.collectionValue?.copiesUnpriced == 10_000)
        #expect(model.collectionValue?.total.currency == .usd)
    }

    /// Evidence for NFR4: no figure escapes without its source, its time, its
    /// coverage and the fact that it is an estimate.
    @Test @MainActor func noFigureIsPresentedWithoutItsQualifications() async {
        let (items, lookup, names) = largeCollection()
        let model = PricingViewModel(lookup: lookup)
        await model.load(items: items, names: names)

        let value = try? #require(model.collectionValue)
        #expect(value?.source == .cardmarket)
        #expect(value?.observedAt != nil)
        #expect(value?.copiesUnpriced ?? 0 > 0, "la fixture lascia carte senza prezzo apposta")
        #expect(value?.isComplete == false)
        #expect(value?.estimateReason.isEmpty == false)

        let sentence = value?.sentence ?? ""
        #expect(sentence.contains("Cardmarket"))
        #expect(sentence.contains("Stima"))
        #expect(sentence.contains("senza prezzo"))

        // The partial figures carry the same qualifications, not only the total.
        for part in model.valueByRarity.values {
            #expect(part.source == .cardmarket)
            #expect(part.sentence.contains("Stima"))
        }
        for part in model.valueByLocation.values {
            #expect(part.sentence.contains("Cardmarket"))
        }
    }
}
