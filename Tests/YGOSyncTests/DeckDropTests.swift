import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

@MainActor
@Suite("Deck drops")
struct DeckDropTests {
    private func rig() throws -> (DatabaseQueue, SQLiteDeckRepository, SQLiteCardRepository) {
        let (database, repository) = try RealDeck.seededRepository()
        return (database, repository, SQLiteCardRepository(database: database))
    }

    private func editor(
        _ repository: SQLiteDeckRepository, _ catalogue: SQLiteCardRepository
    ) -> DeckEditorViewModel {
        DeckEditorViewModel(
            repository: repository, validator: DeckValidator(),
            catalogue: catalogue, editing: repository)
    }

    private func loaded() async throws -> (DeckEditorViewModel, Deck) {
        let (_, repository, catalogue) = try rig()
        let deck = try await repository.createDeck(name: "Nuovo", format: .tcg)
        let model = editor(repository, catalogue)
        await model.load(deckID: deck.id)
        return (model, deck)
    }

    /// Evidence for R5.AC1, at the level a proof can reach: the drop handler.
    /// What this does not cover is SwiftUI delivering the drag to it, which is
    /// checked by hand and which `C6` says is not covered.
    @Test func droppingADeckCardOnAnotherSectionMovesIt() async throws {
        let (model, _) = try await loaded()
        let card = try #require(model.candidates.first { !$0.frame.belongsInExtraDeck })
        await model.add(card, to: .main)

        let artwork = try #require(model.items.first?.id)
        await model.setQuantity(2, of: artwork, in: .main)

        let moved = await model.drop(
            .deckCard(artwork: artwork, section: .main, copies: 1), on: .side)

        #expect(moved)
        #expect(model.quantity(of: artwork, in: .main) == 1)
        #expect(model.quantity(of: artwork, in: .side) == 1)
        #expect(model.lastFailure == nil)

        // Dropping a card back on the section it came from is not a move.
        let unchanged = await model.drop(
            .deckCard(artwork: artwork, section: .side, copies: 1), on: .side)
        #expect(!unchanged)
        #expect(model.quantity(of: artwork, in: .side) == 1)

        // And a drop is undoable like any other edit.
        await model.undo()
        #expect(model.quantity(of: artwork, in: .main) == 2)
        #expect(model.quantity(of: artwork, in: .side) == 0)
    }

    /// Evidence for R5.AC2: dragging a candidate in is an addition, and it
    /// lands in the section it was dropped on rather than the default one.
    @Test func droppingACandidateOnASectionAddsItThere() async throws {
        let (model, _) = try await loaded()
        let card = try #require(model.candidates.first { !$0.frame.belongsInExtraDeck })
        let artwork = try #require(card.artworks.first)

        let added = await model.drop(.candidate(artwork: artwork), on: .side)

        #expect(added)
        #expect(model.quantity(of: artwork, in: .side) == 1)
        #expect(model.quantity(of: artwork, in: .main) == 0)

        // Dropping the same candidate again adds a second copy there.
        await model.drop(.candidate(artwork: artwork), on: .side)
        #expect(model.quantity(of: artwork, in: .side) == 2)

        await model.undo()
        #expect(model.quantity(of: artwork, in: .side) == 1)
    }

    /// Evidence for R5.AC3: the section that would receive a drop is the one
    /// reported, and it is cleared once the drop happens so no section stays
    /// highlighted afterwards.
    @Test func theSectionUnderTheDragIsTheOneReported() async throws {
        let (model, _) = try await loaded()
        #expect(model.dropTarget == nil)

        model.dragEntered(.side)
        #expect(model.dropTarget == .side)

        model.dragEntered(.extra)
        #expect(model.dropTarget == .extra)

        model.dragEntered(nil)
        #expect(model.dropTarget == nil)

        // A completed drop leaves nothing highlighted.
        let card = try #require(model.candidates.first)
        let artwork = try #require(card.artworks.first)
        model.dragEntered(.main)
        await model.drop(.candidate(artwork: artwork), on: .main)
        #expect(model.dropTarget == nil)
    }

    /// Evidence for R5.AC4: the gesture is never the only way. Everything a
    /// drag can do is reachable from the keyboard, which is what makes the
    /// unproven gesture an affordance rather than a dependency.
    @Test func everyMoveAndCountChangeIsReachableByKeyboard() async throws {
        let (model, _) = try await loaded()
        let card = try #require(model.candidates.first { !$0.frame.belongsInExtraDeck })
        await model.add(card, to: .main)

        let artwork = try #require(model.items.first?.id)
        #expect(model.selectedItem?.id == artwork)

        // Count up and down, no pointer.
        await model.changeSelectedQuantity(by: 2)
        #expect(model.quantity(of: artwork, in: .main) == 3)
        await model.changeSelectedQuantity(by: -1)
        #expect(model.quantity(of: artwork, in: .main) == 2)

        // Move to another section, no pointer.
        await model.moveSelection(to: .side, copies: 2)
        #expect(model.quantity(of: artwork, in: .main) == 0)
        #expect(model.quantity(of: artwork, in: .side) == 2)

        // Undo and redo, no pointer.
        await model.undo()
        #expect(model.quantity(of: artwork, in: .main) == 2)
        await model.redo()
        #expect(model.quantity(of: artwork, in: .side) == 2)

        // With nothing selected, the keyboard edits do nothing rather than
        // guessing which card was meant.
        await model.setQuantity(0, of: artwork, in: .side)
        #expect(model.items.isEmpty)
        #expect(model.selectedItem == nil)
        await model.changeSelectedQuantity(by: 1)
        #expect(model.items.isEmpty)
    }
}
