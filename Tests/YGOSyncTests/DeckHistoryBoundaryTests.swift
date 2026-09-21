import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

@MainActor
@Suite("Deck history boundaries")
struct DeckHistoryBoundaryTests {
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

    private func shape(_ model: DeckEditorViewModel) -> [String] {
        model.items
            .map { "\($0.section.rawValue)/\($0.id.rawValue)x\($0.quantity)" }
            .sorted()
    }

    /// Evidence for R4.AC4: a redo of something that no longer follows from
    /// the current deck would apply a change to a deck it was never about.
    @Test func aNewEditDiscardsWhatWasUndone() async throws {
        let (_, repository, catalogue) = try rig()
        let deck = try await repository.createDeck(name: "Nuovo", format: .tcg)
        let model = editor(repository, catalogue)
        await model.load(deckID: deck.id)

        let first = try #require(model.candidates.first)
        let second = try #require(model.candidates.dropFirst().first)

        await model.add(first)
        await model.undo()
        #expect(model.canRedo)

        // A different edit takes the branch the undone one was on.
        await model.add(second)
        #expect(!model.canRedo)

        let afterSecond = shape(model)
        let redone = await model.redo()
        #expect(!redone)
        #expect(shape(model) == afterSecond)
        #expect(model.lastFailure?.contains("ripetere") == true)
    }

    /// Evidence for R4.AC5: ⌘Z on a deck nobody has touched has to say so
    /// rather than quietly doing nothing or, worse, something.
    @Test func undoWithNothingToUndoChangesNothingAndSaysSo() async throws {
        let (_, repository, catalogue) = try rig()
        let deck = try await repository.createDeck(name: "Nuovo", format: .tcg)
        let model = editor(repository, catalogue)
        await model.load(deckID: deck.id)

        #expect(!model.canUndo)
        #expect(!model.canRedo)
        let before = shape(model)

        let undone = await model.undo()
        #expect(!undone)
        #expect(shape(model) == before)
        #expect(model.lastFailure?.contains("annullare") == true)

        let redone = await model.redo()
        #expect(!redone)
        #expect(shape(model) == before)

        // Undoing past the beginning stops there rather than going further.
        let card = try #require(model.candidates.first)
        await model.add(card)
        let added = shape(model)
        await model.undo()
        let emptied = shape(model)
        await model.undo()
        #expect(shape(model) == emptied)
        #expect(emptied != added)
    }

    /// Evidence for R4.AC6: a ⌘Z meant for one deck reaching another is the
    /// worst thing this feature could do, so opening a deck clears the stack.
    @Test func openingAnotherDeckDiscardsTheHistory() async throws {
        let (_, repository, catalogue) = try rig()
        let first = try await repository.createDeck(name: "Primo", format: .tcg)
        let second = try await repository.createDeck(name: "Secondo", format: .tcg)

        let model = editor(repository, catalogue)
        await model.load(deckID: first.id)
        let card = try #require(model.candidates.first)
        await model.add(card)
        #expect(model.canUndo)
        let firstDeckShape = shape(model)

        await model.load(deckID: second.id)
        #expect(!model.canUndo)
        #expect(!model.canRedo)
        #expect(model.items.isEmpty)

        // An undo here must not reach back into the first deck.
        let undone = await model.undo()
        #expect(!undone)
        #expect(model.items.isEmpty)

        // The first deck is exactly as it was left.
        await model.load(deckID: first.id)
        #expect(shape(model) == firstDeckShape)
        #expect(!model.canUndo)

        // Reloading the same deck does not clear a history mid-edit.
        await model.add(card)
        #expect(model.canUndo)
        await model.load(deckID: first.id)
        #expect(model.canUndo)
    }
}
