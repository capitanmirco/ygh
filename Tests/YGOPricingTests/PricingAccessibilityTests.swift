import Foundation
import Testing
import YGOCore
import YGOFeaturePricing
@testable import YGOPricing

@MainActor
@Suite("Pricing accessibility")
struct PricingAccessibilityTests {
    private func loadedModel() async -> PricingViewModel {
        var table: [CardIdentifier: [RecordedPrice]] = [:]
        var names: [CardIdentifier: String] = [:]
        var items: [ValuationItem] = []

        // A priced card, a disputed one, and one nobody prices.
        table[CardIdentifier(1)] = [Sample.price(.cardmarket, 12.50)]
        table[CardIdentifier(2)] = Sample.gateGuardian
        names = [CardIdentifier(1): "Carta Cara", CardIdentifier(2): "Gate Guardian",
                 CardIdentifier(3): "Carta Ignota"]
        items = [
            ValuationItem(card: CardIdentifier(1), quantity: 2, location: "Raccoglitore A"),
            ValuationItem(card: CardIdentifier(2), quantity: 1, location: "Scatola B"),
            ValuationItem(card: CardIdentifier(3), quantity: 3),
        ]

        let model = PricingViewModel(lookup: StubPriceLookup(table: table))
        await model.load(items: items, names: names,
                         recordedSpend: Money(amount: 10, currency: .eur))
        return model
    }

    /// Evidence for NFR5: an amount read aloud without its source or its
    /// coverage is not information.
    @Test func everyFigureReadsAsASentenceNamingAmountSourceAndCoverage() async {
        let model = await loadedModel()
        let value = try? #require(model.collectionValue)

        let sentence = value?.sentence ?? ""
        #expect(sentence.contains("€"), "manca l'importo: \(sentence)")
        #expect(sentence.contains("Cardmarket"), "manca la fonte: \(sentence)")
        #expect(sentence.contains("copie"), "manca la copertura: \(sentence)")
        #expect(sentence.contains("Stima"), "manca l'avvertenza: \(sentence)")
        #expect(sentence.contains("senza prezzo"), "tre copie non sono quotate")

        // Each valuable card reads as its own sentence.
        for card in model.mostValuable {
            #expect(card.sentence.contains(card.cardName))
            #expect(card.sentence.contains("×"))
            #expect(card.sentence.contains("€"))
        }

        // The disputed one says so, so a suspicious ranking can be checked.
        let disputed = model.mostValuable.first { $0.isDisputed }
        #expect(disputed?.cardName == "Gate Guardian")
        #expect(disputed?.sentence.contains("contestato") == true)

        #expect(model.sentences.count == model.mostValuable.count + 1)
    }

    /// Evidence for NFR5: everything is reachable without a pointer.
    @Test func reachesValuationScreensByKeyboardAlone() async {
        let model = await loadedModel()

        #expect(model.focusedRegion == .sourcePicker,
                "il fuoco parte dalla scelta che cambia tutte le cifre")

        var visited: [PricingFocusRegion] = [model.focusedRegion]
        for _ in 0..<PricingFocusRegion.allCases.count {
            model.advanceFocus()
            visited.append(model.focusedRegion)
        }
        #expect(Set(visited) == Set(PricingFocusRegion.allCases))
        #expect(visited.last == .sourcePicker, "il ciclo deve chiudersi")

        model.retreatFocus()
        #expect(model.focusedRegion == .mostValuable, "shift-tab non è un vicolo cieco")

        // Every valuable card is reachable by arrow movement.
        model.focusRegion(.mostValuable)
        #expect(model.selectedIndex == 0)

        var reached: Set<CardIdentifier> = []
        for _ in 0..<model.mostValuable.count {
            if let selected = model.selectedCard { reached.insert(selected.card) }
            model.moveSelection(by: 1)
        }
        #expect(reached == Set(model.mostValuable.map(\.card)))

        // Selection stops at the ends.
        model.moveSelection(by: 200)
        #expect(model.selectedIndex == model.mostValuable.count - 1)
        model.moveSelection(by: -200)
        #expect(model.selectedIndex == 0)
    }
}
