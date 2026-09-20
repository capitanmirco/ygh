import Foundation
import Testing
import YGOCore
@testable import YGOPricing

/// Tested against the real shape of the data rather than an invented one.
/// Gate Guardian is listed at €999.99 on Amazon and €0.02 on Cardmarket, and
/// for cards priced by three or more sources the median ratio is 74.
@Suite("Price dispute")
struct PriceDisputeTests {
    private func quote(_ prices: [RecordedPrice], source: PriceSource = .cardmarket) -> PriceQuote {
        PriceQuote(card: CardIdentifier(1), cardName: "Gate Guardian",
                   chosenSource: source, allSources: prices)
    }

    /// Evidence for R2.AC1: tenfold is the threshold, and cards whose sources
    /// broadly agree are left alone.
    @Test func marksACardWhenAnotherSourceExceedsItTenfold() {
        #expect(quote(Sample.gateGuardian).isDisputed,
                "0,02 contro 999,99 deve essere contestata")
        #expect(!quote(Sample.agreed).isDisputed,
                "fonti che concordano entro dieci volte non sono contestate")

        // Just under and just over the threshold.
        let under = quote([Sample.price(.cardmarket, 1.00), Sample.price(.ebay, 9.99)])
        let over = quote([Sample.price(.cardmarket, 1.00), Sample.price(.ebay, 10.01)])
        #expect(!under.isDisputed)
        #expect(over.isDisputed)

        // A card priced by one source alone cannot disagree with anything.
        #expect(!quote([Sample.price(.cardmarket, 1.00)]).isDisputed)

        // Nor can an unpriced one, or one whose chosen price is zero: a ratio
        // against zero is not a comparison.
        #expect(!quote([Sample.price(.amazon, 100)], source: .cardmarket).isDisputed)
        #expect(!quote([Sample.price(.cardmarket, 0), Sample.price(.amazon, 100)]).isDisputed)
    }

    /// Evidence for R2.AC2: "disputed" alone tells the user nothing to act on.
    @Test func namesTheDisagreeingSourceAndTheRatio() {
        let dispute = try? #require(quote(Sample.gateGuardian).dispute)

        #expect(dispute?.disagreeingSource == .amazon, "la fonte più lontana, non la prima")
        #expect(dispute?.disagreeingPrice.amount == 999.99)
        #expect(dispute?.chosenPrice.amount == 0.02)
        #expect((dispute?.ratio ?? 0) > 49_000, "circa 50.000 volte")

        let summary = dispute?.summary ?? ""
        #expect(summary.contains("Amazon"))
        #expect(summary.contains("999.99"))
        #expect(summary.contains("volte"))

        // The sentence a reader gets carries it.
        let sentence = quote(Sample.gateGuardian).sentence
        #expect(sentence.contains("Gate Guardian"))
        #expect(sentence.contains("Cardmarket"))
        #expect(sentence.contains("Amazon"))

        // When several sources disagree, the worst one is named.
        let several = quote([
            Sample.price(.cardmarket, 1.00), Sample.price(.ebay, 20),
            Sample.price(.amazon, 500),
        ])
        #expect(several.dispute?.disagreeingSource == .amazon)
    }

    /// Evidence for R2.AC3: deciding which of two figures is wrong would be
    /// inventing data, so the flag informs and never excludes.
    @Test func aDisputedCardStillCountsInEveryTotal() {
        let disputed = quote(Sample.gateGuardian)
        let agreed = quote(Sample.agreed)

        #expect(disputed.isDisputed)
        #expect(disputed.price?.cents == 2, "il prezzo scelto resta quello scelto")

        // A total over both counts both, and equals the sum of their chosen
        // prices rather than dropping the disputed one.
        let total = [disputed, agreed].compactMap(\.price).total(in: .eur)
        #expect(total?.cents == 2 + 200)

        // Removing the dispute flag by choosing another source does not change
        // that source's own figure either.
        let onAmazon = quote(Sample.gateGuardian, source: .amazon)
        #expect(onAmazon.price?.amount == 999.99)
    }

    /// Evidence for R2.AC4: a total that hides how many of its cards are
    /// doubtful is a total nobody can weigh.
    @Test func reportsHowManyDisputedCardsAreBehindATotal() {
        let quotes = [
            quote(Sample.gateGuardian),
            quote(Sample.agreed),
            quote([Sample.price(.cardmarket, 1.00), Sample.price(.ebay, 50)]),
            quote([]),
        ]

        let disputed = quotes.filter(\.isDisputed)
        #expect(disputed.count == 2, "due su quattro sono contestate")
        #expect(quotes.filter(\.isPriced).count == 3)

        // The flag is per card, so a count is a count of cards rather than of
        // disagreeing sources.
        let manySources = quote([
            Sample.price(.cardmarket, 1.00), Sample.price(.ebay, 50),
            Sample.price(.amazon, 80), Sample.price(.tcgplayer, 90),
        ])
        #expect(manySources.isDisputed)
        #expect(manySources.dispute != nil)
    }
}
