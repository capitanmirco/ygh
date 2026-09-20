import Foundation
import Testing
import YGOCore
import YGOFeatureAnalytics
@testable import YGOAnalytics

/// A probability read aloud without its card or its hand size is not
/// information, it is a number.
@MainActor
@Suite("Analytics accessibility")
struct AnalyticsAccessibilityTests {
    private func loadedModel(format: CardFormat = .goat) -> AnalyticsViewModel {
        let (deck, index) = Sample.deck(size: 40, copies: 3, format: format, extra: 15)
        let model = AnalyticsViewModel()
        model.load(deck: deck, index: index)
        return model
    }

    /// Evidence for NFR6: each figure states what it is about, how likely it
    /// is, and what it assumed.
    @Test func everyFigureReadsAsASentenceNamingCardProbabilityAndHandSize() {
        let model = loadedModel()
        #expect(!model.odds.isEmpty)

        for odds in model.odds {
            let sentence = odds.sentence
            #expect(sentence.contains(odds.cardName), "manca il nome: \(sentence)")
            #expect(sentence.contains("%"), "manca la probabilità: \(sentence)")
            #expect(sentence.contains("\(odds.hand.size)"), "manca la mano: \(sentence)")
            #expect(sentence.contains(odds.hand.format.rawValue))
            #expect(sentence.count > 20, "una frase, non un'etichetta: \(sentence)")
        }

        // A GOAT deck says six, and the same deck in TCG says five, so the
        // reader never has to know the rule themselves.
        #expect(model.odds[0].sentence.contains("6"))
        let modern = loadedModel(format: .tcg)
        #expect(modern.odds[0].sentence.contains("5"))

        // The copy-count table reads as sentences too, and names what each
        // extra copy buys.
        let table = try? #require(model.table)
        #expect(table?.rows.count == 3)
        for row in table?.rows ?? [] {
            #expect(row.sentence.contains("%"))
            #expect(row.sentence.contains("\(row.copies)"))
        }
        #expect(table?.rows[1].sentence.contains("punti") == true)

        #expect(model.sentences.count == model.odds.count)
    }

    /// Evidence for NFR6: everything is reachable without a pointer.
    @Test func reachesBreakdownsAndTableByKeyboardAlone() {
        let model = loadedModel()

        #expect(model.focusedRegion == .playOrder, "il fuoco parte dalla scelta più a monte")

        var visited: [AnalyticsFocusRegion] = [model.focusedRegion]
        for _ in 0..<AnalyticsFocusRegion.allCases.count {
            model.advanceFocus()
            visited.append(model.focusedRegion)
        }
        #expect(Set(visited) == Set(AnalyticsFocusRegion.allCases))
        #expect(visited.last == .playOrder, "il ciclo deve chiudersi")

        model.retreatFocus()
        #expect(model.focusedRegion == .probabilityTable, "shift-tab non è un vicolo cieco")

        // Every card row is reachable, and the table follows the selection.
        model.focusRegion(.cardList)
        #expect(model.selectedIndex == 0)

        var reached: Set<CardIdentifier> = []
        for _ in 0..<model.odds.count {
            let selected = try? #require(model.selectedOdds)
            if let selected {
                reached.insert(selected.card)
                #expect(model.table?.cardName == selected.cardName,
                        "la tabella deve seguire la selezione")
            }
            model.moveSelection(by: 1)
        }
        #expect(reached == Set(model.odds.map(\.card)))

        // Selection stops at the ends, so the edge of the list is perceptible.
        model.moveSelection(by: 500)
        #expect(model.selectedIndex == model.odds.count - 1)
        model.moveSelection(by: -500)
        #expect(model.selectedIndex == 0)
    }
}
