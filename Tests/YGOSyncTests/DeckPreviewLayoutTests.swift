import Foundation
import Testing
import YGOCore
import YGODesignSystem
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

@MainActor
@Suite("Deck preview layout")
struct DeckPreviewLayoutTests {
    /// Window widths from a small laptop to a large display.
    static let widths: [CGFloat] = [900, 1_100, 1_280, 1_440, 1_680, 1_920, 2_560, 3_440]

    /// Evidence for R2.AC1: the deck editor is already two columns, and the
    /// user has already met three columns going wrong in the catalog.
    @Test func theDetailIsNeverWiderThanAQuarterOfTheWindow() {
        for total in Self.widths {
            let width = Theme.Inspector.width(forWindowWidth: total)
            // A quarter, unless the floor had to win — and then the window was
            // too narrow for a quarter to be readable anyway.
            if Theme.Inspector.isFloorApplied(forWindowWidth: total) {
                #expect(width == Theme.Inspector.minimumWidth)
            } else {
                #expect(width == total * Theme.Inspector.maximumShare)
                #expect(width <= total / 4 + 0.001, "at \(total) the detail took \(width)")
            }
            // The deck always keeps the majority of the window.
            #expect(total - width > width * 2)
        }

        #expect(Theme.Inspector.maximumShare == 0.25)
    }

    /// Evidence for R2.AC2: below a certain width a quarter is unreadable, so
    /// the floor wins and the deck narrows instead of the panel.
    @Test func aNarrowWindowNarrowsTheDeckNotThePanel() {
        let narrow: CGFloat = 800
        #expect(Theme.Inspector.isFloorApplied(forWindowWidth: narrow))
        #expect(Theme.Inspector.width(forWindowWidth: narrow)
                == Theme.Inspector.minimumWidth)

        // Wide enough, and the share takes over from the floor.
        let wide: CGFloat = 1_440
        #expect(!Theme.Inspector.isFloorApplied(forWindowWidth: wide))
        #expect(Theme.Inspector.width(forWindowWidth: wide) > Theme.Inspector.minimumWidth)

        // The floor is wide enough to read a card's effect rather than being
        // a token gesture.
        #expect(Theme.Inspector.minimumWidth >= 240)

        // The rule is monotonic: a wider window never gives a narrower panel.
        let widths = Self.widths.map(Theme.Inspector.width(forWindowWidth:))
        #expect(widths == widths.sorted())
    }

    /// Evidence for R2.AC4: a deck list is walked with the arrow keys, so the
    /// panel has to follow without a pointer ever being involved.
    @Test func selectingAndDismissingAreReachableWithoutAPointer() async throws {
        let (database, decks) = try RealDeck.seededRepository()
        let deck = try await decks.createDeck(name: "Nuovo", format: .tcg)
        let reader = SQLiteCardRepository(database: database)
        let model = DeckEditorViewModel(
            repository: decks, validator: DeckValidator(),
            catalogue: reader, editing: decks, reader: reader)
        await model.load(deckID: deck.id)

        let first = try #require(model.candidates.first { !$0.frame.belongsInExtraDeck })
        let second = try #require(
            model.candidates.dropFirst().first { !$0.frame.belongsInExtraDeck })
        await model.add(first, to: .main)
        await model.add(second, to: .main)

        // Moving the selection with the keyboard previews what it lands on.
        model.moveSelection(by: 0)
        await model.previewSelection()
        let firstShown = try #require(model.previewCard)

        model.moveSelection(by: 1)
        await model.previewSelection()
        let secondShown = try #require(model.previewCard)
        #expect(secondShown.id != firstShown.id)

        // Dismissing and restoring need no pointer either.
        model.dismissPreview()
        #expect(!model.isPreviewVisible)
        model.restorePreview()
        #expect(model.isPreviewVisible)
        #expect(model.previewCard?.id == secondShown.id)

        // And the panel follows the selection back up the list.
        model.moveSelection(by: -1)
        await model.previewSelection()
        #expect(model.previewCard?.id == firstShown.id)
    }
}
