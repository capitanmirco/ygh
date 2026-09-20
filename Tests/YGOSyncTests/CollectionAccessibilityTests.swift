import Foundation
import GRDB
import Testing
import YGOCore
import YGODeckIO
import YGOFeatureCollection
import YGOPersistence
import YGOValidation
@testable import YGOSync

/// These assert the contract the view binds to rather than rendered pixels.
@MainActor
@Suite("Collection accessibility")
struct CollectionAccessibilityTests {
    private func modelWithShortfall() async throws -> (CollectionViewModel, Deck) {
        let rig = try CollectionFixture.seeded()
        let importer = DeckImporter(repository: rig.decks, validator: DeckValidator())
        let result = try await importer.importFile(
            at: RealDeck.root.appending(path: "fixtures/Lockdown Burn.ydk"))

        // Own some of it, but not all: a shortfall needs both cases in it.
        let required = ShortfallCalculator.required(in: result.deck)
        for (card, count) in required.prefix(6) {
            try await rig.collection.setQuantity(
                max(0, count - 1), cardID: card, printID: nil)
        }

        var names: [CardIdentifier: String] = [:]
        for card in required.keys {
            let name = try await rig.database.read { db in
                try String.fetchOne(db, sql: "SELECT name_en FROM card WHERE id = ?",
                                    arguments: [card.rawValue])
            }
            names[card] = name ?? "Carta \(card.rawValue)"
        }

        let model = CollectionViewModel(reader: rig.collection)
        await model.reload()
        await model.computeShortfall(for: result.deck, names: names)
        return (model, result.deck)
    }

    /// Evidence for NFR5: a shortfall is a shopping list read aloud, so each
    /// entry names the card and how many are still needed.
    @Test func everyShortfallEntryReadsAsASentence() async throws {
        let (model, _) = try await modelWithShortfall()

        #expect(!model.shortfall.isEmpty, "il mazzo di prova deve avere carte mancanti")
        #expect(!model.isShortfallSatisfied)

        for entry in model.shortfall {
            let sentence = entry.sentence
            #expect(sentence.contains(entry.cardName), "manca il nome: \(sentence)")
            #expect(sentence.contains("\(entry.missing)"), "manca il numero: \(sentence)")
            #expect(sentence.count > 12, "una frase, non un'etichetta: \(sentence)")
            #expect(entry.missing > 0, "una voce senza mancanze non va nell'elenco")
        }

        // The two cases read differently, because they mean different things.
        if let ownedNone = model.shortfall.first(where: { $0.owned == 0 }) {
            #expect(ownedNone.sentence.contains("non ne hai"))
        }
        if let partial = model.shortfall.first(where: { $0.owned > 0 }) {
            #expect(partial.sentence.contains("\(partial.owned)"))
            #expect(partial.sentence.contains("altre"))
        }

        #expect(model.shortfallSentences.count == model.shortfall.count)

        // Owned rows are announced with their count too.
        for item in model.items {
            #expect(item.accessibilityLabel.contains(item.name))
            #expect(item.accessibilityLabel.contains("\(item.copies)"))
        }
    }

    /// Evidence for NFR5: the search field, the filters, the owned list and
    /// the shortfall are all reachable without a pointer.
    @Test func reachesListFiltersAndShortfallByKeyboardAlone() async throws {
        let (model, _) = try await modelWithShortfall()

        #expect(model.focusedRegion == .search, "il fuoco parte dove si scrive")

        var visited: [CollectionFocusRegion] = [model.focusedRegion]
        for _ in 0..<CollectionFocusRegion.allCases.count {
            model.advanceFocus()
            visited.append(model.focusedRegion)
        }
        #expect(Set(visited) == Set(CollectionFocusRegion.allCases))
        #expect(visited.last == .search, "il ciclo deve chiudersi")

        model.retreatFocus()
        #expect(model.focusedRegion == .shortfall, "shift-tab non è un vicolo cieco")

        // Every owned row is reachable by arrow movement.
        model.focusRegion(.ownedList)
        #expect(model.selectedIndex == 0)

        var reached: Set<CardIdentifier> = []
        for _ in 0..<model.items.count {
            reached.insert(try #require(model.selectedItem).id)
            model.moveSelection(by: 1)
        }
        #expect(reached == Set(model.items.map(\.id)))

        // Selection stops at the ends, so the edge of the list is perceptible.
        model.moveSelection(by: 500)
        #expect(model.selectedIndex == model.items.count - 1)
        model.moveSelection(by: -500)
        #expect(model.selectedIndex == 0)
    }
}
