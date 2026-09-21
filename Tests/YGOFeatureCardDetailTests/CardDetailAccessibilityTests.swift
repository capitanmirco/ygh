import Foundation
import Testing
import YGOBanlistHistory
import YGOCore
@testable import YGOFeatureCardDetail

@MainActor
@Suite("Card detail accessibility")
struct CardDetailAccessibilityTests {
    /// Evidence for NFR5: a figure on its own tells a listener nothing. Every
    /// line names what it is and where it came from, and the sentence a screen
    /// reader hears is the one the eye reads, because both come from here.
    @Test func everyFigureReadsAsASentenceNamingItAndItsSource() throws {
        let priced = CardPriceLine(
            source: .cardmarket, money: Money(cents: 289, currency: .eur),
            observedAt: Date(timeIntervalSince1970: 1_758_441_600))
        let spoken = CardDetailNarration.price(priced)
        #expect(spoken.contains("Cardmarket"))
        #expect(spoken.contains("2,89") || spoken.contains("2.89"))
        #expect(spoken != Money(cents: 289, currency: .eur).formatted)

        // An absent figure is a sentence too, and it does not say zero.
        let missing = CardDetailNarration.price(
            CardPriceLine(source: .ebay, money: nil, observedAt: nil))
        #expect(missing == "eBay: nessun prezzo disponibile")
        #expect(!missing.contains("0"))

        // Dates name their region; an unknown one says so.
        #expect(CardDetailNarration.release(.known(tcg: "2002-03-08", ocg: "1999-01-21"))
                == "Uscita TCG 2002-03-08, Uscita OCG 1999-01-21")
        #expect(CardDetailNarration.release(.unknown) == "Data di uscita sconosciuta")

        // A status change names both ends and the day it happened.
        let change = CardDetailNarration.change(BanlistChangeNarration(
            date: "2005-03-01", from: .unlimited, to: .forbidden))
        #expect(change == "Il 2005-03-01 è passata da Illimitata a Vietata")

        // Copies and decks name the place and the section, not a bare number.
        #expect(CardDetailNarration.holding(CardHolding(
            quantity: 2, condition: .nearMint, location: "Raccoglitore rosso"))
                == "2 copie in Raccoglitore rosso")
        #expect(CardDetailNarration.holding(CardHolding(
            quantity: 4, condition: .damaged, location: nil))
                .contains("Non archiviata"))
        #expect(CardDetailNarration.deckUse(DeckUse(
            deckID: 1, deckName: "Lockdown Burn", section: .side, quantity: 1))
                == "Lockdown Burn, Side Deck, 1 copie")

        // A printing names its set, its code and its rarity.
        #expect(CardDetailNarration.printing(CardPrinting(
            setName: "Legend of Blue Eyes", setCode: "LOB-001",
            rarity: "Ultra Rare", listedPrice: nil))
                == "Legend of Blue Eyes, codice LOB-001, rarità Ultra Rare")

        // A disagreement names both sources, because neither is preferred.
        let sentence = CardDetailNarration.disagreement(BanlistDisagreement(
            cardID: 1, konamiID: 4007, name: "Carta",
            catalogStatus: .forbidden, historyStatus: .limited,
            historyEffectiveDate: "2026-05-18",
            historySource: "yaml-yugi-limit-regulation"))
        #expect(sentence.contains("catalogo"))
        #expect(sentence.contains("yaml-yugi-limit-regulation"))
        #expect(sentence.contains("Vietata"))
        #expect(sentence.contains("Limitata"))
    }

    /// Evidence for NFR5: the panel is a column of sections, and every one of
    /// them is reachable without a pointer.
    @Test func reachesGridPanelAndEverySectionByKeyboardAlone() async throws {
        var history = StubBanlistHistory()
        history.revisionDates = [.tcg: ["2026-05-18"]]
        let panel = CardDetailViewModel(
            loader: CardDetailLoader(
                catalog: StubCardRepository(cards: [DetailCards.blueEyes]),
                details: StubDetailReader(),
                usage: StubUsageReader(),
                priceLookup: StubPriceLookup(),
                history: history,
                provenance: history),
            artwork: StubArtworkStore())

        await panel.select(DetailCards.blueEyes, language: .italian)
        #expect(panel.focusedRegion == .artwork)

        // Stepping forward reaches every section, in reading order.
        var visited: [CardDetailFocusRegion] = [panel.focusedRegion]
        for _ in 1..<CardDetailFocusRegion.allCases.count {
            panel.moveFocus(by: 1)
            visited.append(panel.focusedRegion)
        }
        #expect(visited == CardDetailFocusRegion.allCases)
        #expect(Set(visited).count == 8)

        // The ends hold rather than wrapping, so a held key cannot cycle.
        panel.moveFocus(by: 1)
        #expect(panel.focusedRegion == .decks)
        for _ in 0..<20 { panel.moveFocus(by: -1) }
        #expect(panel.focusedRegion == .artwork)

        // Each section names itself, which is what the reader announces.
        #expect(CardDetailFocusRegion.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(CardDetailFocusRegion.prices.title == "Prezzi")

        // Jumping straight to a section works too.
        panel.focus(.banlist)
        #expect(panel.focusedRegion == .banlist)
    }
}
