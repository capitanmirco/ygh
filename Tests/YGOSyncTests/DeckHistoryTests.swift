import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

@MainActor
@Suite("Deck history")
struct DeckHistoryTests {
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

    /// The deck as a comparable shape: section, artwork and count.
    private func shape(_ model: DeckEditorViewModel) -> [String] {
        model.items
            .map { "\($0.section.rawValue)/\($0.id.rawValue)x\($0.quantity)" }
            .sorted()
    }

    /// Evidence for R4.AC1: an undo restores the deck section by section, not
    /// approximately. A misdrag is exactly the case this exists for.
    @Test func undoRestoresTheDeckSectionBySection() async throws {
        let (_, repository, catalogue) = try rig()
        let deck = try await repository.createDeck(name: "Nuovo", format: .tcg)
        let model = editor(repository, catalogue)
        await model.load(deckID: deck.id)

        let first = try #require(model.candidates.first)
        await model.add(first)
        let before = shape(model)
        #expect(model.canUndo)

        let second = try #require(model.candidates.dropFirst().first)
        await model.add(second)
        #expect(shape(model) != before)

        let undone = await model.undo()
        #expect(undone)
        #expect(shape(model) == before)
        #expect(model.lastFailure == nil)
    }

    /// Evidence for R4.AC2: a redo puts back exactly what the undo took away.
    @Test func redoAppliesTheUndoneEditAgain() async throws {
        let (_, repository, catalogue) = try rig()
        let deck = try await repository.createDeck(name: "Nuovo", format: .tcg)
        let model = editor(repository, catalogue)
        await model.load(deckID: deck.id)

        let card = try #require(model.candidates.first)
        await model.add(card)
        let afterEdit = shape(model)

        await model.undo()
        let afterUndo = shape(model)
        #expect(afterUndo != afterEdit)
        #expect(model.canRedo)

        let redone = await model.redo()
        #expect(redone)
        #expect(shape(model) == afterEdit)
        #expect(!model.canRedo)
        #expect(model.canUndo)
    }

    /// Evidence for R4.AC3: all four kinds of edit, each undone to what stood
    /// before it. Adding and removing are count changes, which is why this is
    /// one implementation rather than four.
    @Test func everyKindOfEditIsUndoneToItsPriorState() async throws {
        let (_, repository, catalogue) = try rig()
        let deck = try await repository.createDeck(name: "Nuovo", format: .tcg)
        let model = editor(repository, catalogue)
        await model.load(deckID: deck.id)
        let card = try #require(model.candidates.first)

        // 1. An addition.
        let empty = shape(model)
        await model.add(card)
        let added = shape(model)
        await model.undo()
        #expect(shape(model) == empty)
        await model.redo()
        #expect(shape(model) == added)

        let artwork = try #require(model.items.first?.id)

        // 2. A count change.
        await model.setQuantity(3, of: artwork, in: .main)
        #expect(model.items.first?.quantity == 3)
        await model.undo()
        #expect(shape(model) == added)

        // 3. A move.
        await model.setQuantity(2, of: artwork, in: .main)
        let beforeMove = shape(model)
        await model.move(artwork, from: .main, to: .side, copies: 1)
        #expect(shape(model) != beforeMove)
        await model.undo()
        #expect(shape(model) == beforeMove)

        // 4. A removal.
        await model.remove(artwork: artwork, from: .main)
        #expect(shape(model) != beforeMove)
        await model.undo()
        #expect(shape(model) == beforeMove)
    }

    /// Evidence for R4.AC3: undo works because every edit's inverse is an edit
    /// of the same kind, so undoing reuses the two write operations rather
    /// than needing a third way to reach a deck state.
    @Test func everyEditsInverseIsAnEditOfTheSameKind() {
        let artwork = ArtworkIdentifier(89_631_139)

        let count = DeckEdit.quantity(
            artwork: artwork, section: .main, from: 1, to: 3)
        #expect(count.inverse == .quantity(
            artwork: artwork, section: .main, from: 3, to: 1))
        #expect(count.inverse.inverse == count)

        let move = DeckEdit.move(
            artwork: artwork, from: .main, to: .side, copies: 2)
        #expect(move.inverse == .move(
            artwork: artwork, from: .side, to: .main, copies: 2))
        #expect(move.inverse.inverse == move)

        // Adding and removing are count changes, so there are two cases and
        // not four.
        let added = DeckEdit.quantity(
            artwork: artwork, section: .extra, from: 0, to: 1)
        #expect(added.inverse == .quantity(
            artwork: artwork, section: .extra, from: 1, to: 0))
    }
}
