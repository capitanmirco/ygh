import Foundation
import Testing
import YGOBanlistHistory
import YGOCore
@testable import YGOFeatureCardDetail

@Suite("Card detail assembly")
struct CardDetailAssemblyTests {
    private let observedAt = Date(timeIntervalSince1970: 1_758_441_600)

    private func loader(
        details: StubDetailReader = StubDetailReader(),
        usage: StubUsageReader = StubUsageReader(),
        prices: StubPriceLookup = StubPriceLookup(),
        history: StubBanlistHistory = StubBanlistHistory(),
        statuses: [CardIdentifier: BanStatus] = [:]
    ) -> CardDetailLoader {
        CardDetailLoader(
            catalog: StubCardRepository(
                statuses: statuses,
                cards: [DetailCards.blueEyes, DetailCards.untranslated]),
            details: details,
            usage: usage,
            priceLookup: prices,
            history: history,
            provenance: history)
    }

    private func fullPrices() -> StubPriceLookup {
        StubPriceLookup(recorded: [DetailCards.blueEyes.id: [
            RecordedPrice(source: .cardmarket,
                          money: Money(cents: 289, currency: .eur), observedAt: observedAt),
            RecordedPrice(source: .tcgplayer,
                          money: Money(cents: 450, currency: .usd), observedAt: observedAt),
            RecordedPrice(source: .ebay,
                          money: Money(cents: 99_999, currency: .usd), observedAt: observedAt),
            RecordedPrice(source: .amazon,
                          money: Money(cents: 1_250, currency: .usd), observedAt: observedAt),
            RecordedPrice(source: .coolstuffinc,
                          money: Money(cents: 399, currency: .usd), observedAt: observedAt),
        ]])
    }

    /// Evidence for R2.AC2: the three things you read first, in the language
    /// you asked for.
    @Test func readsNameTypeAndEffectInTheChosenLanguage() async throws {
        let detail = await loader().load(DetailCards.blueEyes, language: .italian)

        #expect(detail.text.name == "Drago Bianco Occhi Blu")
        #expect(detail.text.effect.hasPrefix("Questo drago leggendario"))
        #expect(detail.card.humanReadableType == "Normal Monster")
        #expect(!detail.isUntranslated)
        #expect(detail.language == .italian)

        // The same card in English changes the text and nothing else.
        let english = await loader().load(DetailCards.blueEyes, language: .english)
        #expect(english.text.name == "Blue-Eyes White Dragon")
        #expect(english.text.effect.hasPrefix("This legendary dragon"))
        #expect(english.card.id == detail.card.id)
        #expect(!english.isUntranslated)
    }

    /// Evidence for R2.AC3: 2,981 cards have no Italian text. Falling back is
    /// right; falling back silently is not, because the reader would think
    /// that card simply has an English name.
    @Test func anUntranslatedCardReadsEnglishAndSaysSo() async throws {
        let detail = await loader().load(DetailCards.untranslated, language: .italian)

        #expect(detail.text.name == "Upstart Goblin")
        #expect(detail.text.effect == "Draw 1 card, then your opponent gains 1000 LP.")
        #expect(detail.isUntranslated)
        #expect(detail.text.isFallbackToEnglish)

        // Asking for English is not a fallback, even though the text matches.
        let english = await loader().load(DetailCards.untranslated, language: .english)
        #expect(english.text.name == "Upstart Goblin")
        #expect(!english.isUntranslated)
    }

    /// Evidence for R3.AC3: five sources, each named, each in the currency it
    /// publishes. Cardmarket is in euro and the rest in dollars, and there is
    /// no conversion to hide that.
    @Test func reportsEachSourcesFigureWithItsCurrency() async throws {
        let detail = await loader(prices: fullPrices())
            .load(DetailCards.blueEyes, language: .italian)

        #expect(detail.prices.count == 5)
        #expect(Set(detail.prices.map(\.source)) == Set(PriceSource.allCases))
        #expect(detail.prices.allSatisfy { !$0.isUnpriced })

        let cardmarket = try #require(detail.prices.first { $0.source == .cardmarket })
        #expect(cardmarket.money == Money(cents: 289, currency: .eur))
        #expect(cardmarket.currency == .eur)
        #expect(cardmarket.source.displayName == "Cardmarket")

        #expect(detail.prices.filter { $0.currency == .usd }.count == 4)

        // The sources that publish asking prices stay marked as such, so no
        // later reader folds them into an average.
        let asking = detail.prices.filter { $0.source.carriesAskingPrices }
        #expect(Set(asking.map(\.source)) == [.ebay, .amazon])
    }

    /// Evidence for R3.AC4: 289 cards have no price from anybody, and only
    /// 11,530 are priced by all five. Zero is a price. Absent is not.
    @Test func aMissingSourceIsUnpricedNotZero() async throws {
        let partial = StubPriceLookup(recorded: [DetailCards.blueEyes.id: [
            RecordedPrice(source: .cardmarket,
                          money: Money(cents: 289, currency: .eur), observedAt: observedAt),
        ]])
        let detail = await loader(prices: partial)
            .load(DetailCards.blueEyes, language: .italian)

        // Still five lines: a source left out would let this read as fully
        // priced.
        #expect(detail.prices.count == 5)

        let unpriced = detail.prices.filter(\.isUnpriced)
        #expect(unpriced.count == 4)
        #expect(unpriced.allSatisfy { $0.money == nil })
        #expect(!unpriced.contains { $0.money == Money(cents: 0, currency: .usd) })

        // A card nobody prices reports five unpriced lines, not an empty list.
        let none = await loader().load(DetailCards.untranslated, language: .italian)
        #expect(none.prices.count == 5)
        #expect(none.prices.allSatisfy { $0.isUnpriced })
        #expect(none.pricesObservedAt == nil)
    }

    /// Evidence for R3.AC5: a price is a fact about a moment. Dating it by
    /// when the panel opened would make a year-old figure look fresh.
    @Test func pricesCarryWhenTheyWereObserved() async throws {
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let mixed = StubPriceLookup(recorded: [DetailCards.blueEyes.id: [
            RecordedPrice(source: .cardmarket,
                          money: Money(cents: 289, currency: .eur), observedAt: older),
            RecordedPrice(source: .tcgplayer,
                          money: Money(cents: 450, currency: .usd), observedAt: observedAt),
        ]])

        let before = Date()
        let detail = await loader(prices: mixed)
            .load(DetailCards.blueEyes, language: .italian)

        let cardmarket = try #require(detail.prices.first { $0.source == .cardmarket })
        #expect(cardmarket.observedAt == older)

        // The panel dates the set by the most recent observation it holds.
        #expect(detail.pricesObservedAt == observedAt)
        let dated = try #require(detail.pricesObservedAt)
        #expect(dated < before)

        // An unpriced source carries no time either.
        #expect(detail.prices.first { $0.source == .ebay }?.observedAt == nil)
    }

    /// Evidence for R3.AC6: Blue-Eyes White Dragon has 78 printings across two
    /// rarities and one figure per source. Showing both without saying which
    /// the figure describes lets the layout imply an answer nobody has.
    @Test func statesThatAPriceDescribesTheCardNotThePrinting() async throws {
        var details = StubDetailReader()
        details.printings = [DetailCards.blueEyes.id: [
            CardPrinting(setName: "Legend of Blue Eyes", setCode: "LOB-001",
                         rarity: "Ultra Rare", listedPrice: 249.99),
            CardPrinting(setName: "Starter Deck Kaiba", setCode: "SDK-001",
                         rarity: "Common", listedPrice: 1.20),
        ]]

        let detail = await loader(details: details, prices: fullPrices())
            .load(DetailCards.blueEyes, language: .italian)

        let printings = try #require(detail.printings.value)
        #expect(printings.count == 2)
        #expect(Set(printings.map(\.rarity)).count == 2)

        // Two rarities, one figure per source: the notice is what keeps the
        // panel honest about that.
        #expect(CardDetail.priceScopeNotice.contains("per carta"))
        #expect(CardDetail.priceScopeNotice.contains("non per stampa"))
        #expect(detail.prices.filter { $0.source == .cardmarket }.count == 1)

        // The printings do carry what the upstream listed for each, which is a
        // different number from the card's price and stays beside its printing.
        #expect(printings.first { $0.setCode == "LOB-001" }?.listedPrice == 249.99)
        #expect(printings.first { $0.setCode == "SDK-001" }?.listedPrice == 1.20)
    }
}
