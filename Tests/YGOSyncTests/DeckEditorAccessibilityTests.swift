import Foundation
import GRDB
import Testing
import YGOCore
import YGODeckIO
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

/// These assert the contract the view binds to rather than rendered pixels.
/// Keeping focus order and the wording of a violation in the model is what
/// makes either assertable at all.
@Suite("Deck editor accessibility")
struct DeckEditorAccessibilityTests {
    @MainActor
    private func brokenDeck() async throws -> DeckEditorViewModel {
        let (_, repository) = try RealDeck.seededRepository()
        let cards = try RealDeck.cards()

        // Too few cards, one card over its allowance, one in the wrong section.
        let deck = try await repository.createDeck(name: "Rotto", format: .goat)
        let over = ArtworkIdentifier(try #require(cards.first?.cardImages.first).id)
        for _ in 0..<4 {
            try await repository.addCard(artwork: over, section: .main, to: deck.id)
        }
        if let fusion = cards.first(where: { $0.frameType == "fusion" }),
           let image = fusion.cardImages.first {
            try await repository.addCard(
                artwork: ArtworkIdentifier(image.id), section: .main, to: deck.id)
        }

        let model = DeckEditorViewModel(repository: repository, validator: DeckValidator())
        await model.load(deckID: deck.id)
        return model
    }

    /// Evidence for NFR5: a violation is a sentence naming the card and the
    /// rule, not a colour or an icon a screen reader cannot convey.
    @Test @MainActor func everyViolationReadsAsASentenceNamingCardAndRule() async throws {
        let model = try await brokenDeck()
        let sentences = model.violationSentences

        #expect(sentences.count >= 2, "il mazzo di prova deve avere più problemi")

        for sentence in sentences {
            #expect(!sentence.isEmpty)
            #expect(sentence.count > 12, "una frase, non un'etichetta: \(sentence)")
        }

        // What each kind must carry differs, and asserting a number on all of
        // them would be wrong: a misplaced card has no count to state, only a
        // name and a place.
        for violation in try #require(model.legality).violations {
            let sentence = violation.sentence
            switch violation {
            case .sectionSize, .overCopyLimit:
                #expect(sentence.rangeOfCharacter(from: .decimalDigits) != nil,
                        "una violazione di quantità deve dire quanto: \(sentence)")
            case .misplacedCard(_, let cardName, _):
                #expect(sentence.contains(cardName))
                #expect(sentence.contains("Extra Deck"))
            case .outsideFormatPool(_, let cardName, let format):
                #expect(sentence.contains(cardName))
                #expect(sentence.contains(format.rawValue))
            }
        }

        // The size problem names its section and its bound.
        let size = try #require(sentences.first { $0.contains("Deck principale") })
        #expect(size.contains("minimo") || size.contains("massimo"))

        // The copy problem names the card and both counts.
        let violations = try #require(model.legality).violations
        let overLimit = try #require(violations.first {
            if case .overCopyLimit = $0 { return true } else { return false }
        })
        guard case .overCopyLimit(let name, let held, let permitted, _) = overLimit else { return }
        #expect(overLimit.sentence.contains(name))
        #expect(overLimit.sentence.contains("\(held)"))
        #expect(overLimit.sentence.contains("\(permitted)"))

        // Every card row is announced with its count, name and section.
        for item in model.items {
            #expect(item.accessibilityLabel.contains(item.title))
            #expect(item.accessibilityLabel.contains("\(item.quantity)"))
            #expect(item.accessibilityLabel.contains(item.section.italianName))
        }
    }

    /// Evidence for NFR5: the sections, the card list and the report are all
    /// reachable without a pointer, and the list can be traversed card by card.
    @Test @MainActor func reachesSectionsCardListAndReportByKeyboardAlone() async throws {
        let model = try await brokenDeck()

        #expect(model.focusedRegion == .sections)

        var visited: [DeckEditorFocusRegion] = [model.focusedRegion]
        for _ in 0..<DeckEditorFocusRegion.allCases.count {
            model.advanceFocus()
            visited.append(model.focusedRegion)
        }
        #expect(Set(visited) == Set(DeckEditorFocusRegion.allCases))
        #expect(visited.last == .sections, "il ciclo deve chiudersi")

        model.retreatFocus()
        #expect(model.focusedRegion == .violationReport, "shift-tab non è un vicolo cieco")

        // Every row is reachable by arrow movement.
        model.focusRegion(.cardList)
        #expect(model.selectedIndex == 0)

        var reached: Set<ArtworkIdentifier> = []
        for _ in 0..<model.items.count {
            reached.insert(try #require(model.selectedItem).id)
            model.moveSelection(by: 1)
        }
        #expect(reached == Set(model.items.map(\.id)))

        // Selection stops at the ends, so the edge of the list is perceptible.
        model.moveSelection(by: 100)
        #expect(model.selectedIndex == model.items.count - 1)
        model.moveSelection(by: -100)
        #expect(model.selectedIndex == 0)
    }
}
