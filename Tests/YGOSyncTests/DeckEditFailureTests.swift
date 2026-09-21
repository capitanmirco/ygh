import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

/// Refuses every rearrangement, so a test can see what the editor does when a
/// write does not happen.
struct RefusingDeckEditor: DeckEditing {
    struct Refused: Error {}

    func setQuantity(
        artwork: ArtworkIdentifier, section: DeckSection,
        to copies: Int, in deckID: Int64
    ) async throws {
        throw Refused()
    }

    func move(
        artwork: ArtworkIdentifier, from source: DeckSection,
        to destination: DeckSection, copies: Int, in deckID: Int64
    ) async throws -> Int {
        throw Refused()
    }
}

@MainActor
@Suite("Deck edit failures")
struct DeckEditFailureTests {
    private func rig() throws -> (DatabaseQueue, SQLiteDeckRepository, SQLiteCardRepository) {
        let (database, repository) = try RealDeck.seededRepository()
        return (database, repository, SQLiteCardRepository(database: database))
    }

    private func editor(
        _ repository: SQLiteDeckRepository, _ catalogue: SQLiteCardRepository,
        editing: (any DeckEditing)? = nil
    ) -> DeckEditorViewModel {
        DeckEditorViewModel(
            repository: repository, validator: DeckValidator(),
            catalogue: catalogue, editing: editing ?? repository)
    }

    private func storedSlots(
        _ database: DatabaseQueue, _ deckID: Int64
    ) throws -> [String] {
        try database.read { (db: Database) in
            try Row.fetchAll(db, sql: """
                SELECT section, artwork_id, quantity FROM deck_slot
                WHERE deck_id = ? ORDER BY section, artwork_id
                """, arguments: [deckID])
                .map { "\($0["section"] as String)/\($0["artwork_id"] as Int)x\($0["quantity"] as Int)" }
        }
    }

    /// Evidence for R2.AC4: the editor called the repository with `try?`, so a
    /// refused write left the deck unchanged and said nothing at all. That is
    /// indistinguishable from an edit that succeeded and did nothing.
    @Test func aRefusedWriteIsReportedAndTheDeckIsUnchanged() async throws {
        let (database, repository, catalogue) = try rig()
        let deck = try await repository.createDeck(name: "Nuovo", format: .tcg)
        let model = editor(repository, catalogue)
        await model.load(deckID: deck.id)

        let card = try #require(model.candidates.first)
        await model.add(card)
        #expect(model.lastFailure == nil)
        let before = try storedSlots(database, deck.id)
        #expect(before.count == 1)

        // From here on, every rearrangement is refused. Adding and removing
        // go through `DeckBuilding` and are unaffected; counts and moves are
        // what `DeckEditing` carries.
        let refusing = editor(repository, catalogue, editing: RefusingDeckEditor())
        await refusing.load(deckID: deck.id)
        let artwork = try #require(refusing.items.first?.id)

        await refusing.setQuantity(3, of: artwork, in: .main)
        let failure = try #require(refusing.lastFailure)
        #expect(failure.contains("non riuscita"))
        #expect(try storedSlots(database, deck.id) == before)
        #expect(refusing.items.first?.quantity == 1)

        // A move that is refused reads the same way.
        await refusing.move(artwork, from: .main, to: .side)
        #expect(refusing.lastFailure != nil)
        #expect(try storedSlots(database, deck.id) == before)

        // And a refused edit is not recorded as something to undo.
        #expect(!refusing.canUndo)
    }

    /// Evidence for R2.AC4: the deck is reloaded from storage after every
    /// edit, successful or not, so what is on screen is never ahead of what is
    /// saved.
    @Test func theShownDeckIsTheStoredDeckAfterEveryEdit() async throws {
        let (database, repository, catalogue) = try rig()
        let deck = try await repository.createDeck(name: "Nuovo", format: .tcg)
        let model = editor(repository, catalogue)
        await model.load(deckID: deck.id)
        let card = try #require(model.candidates.first)

        func shownMatchesStored() throws -> Bool {
            let shown = model.items
                .map { "\($0.section.rawValue)/\($0.id.rawValue)x\($0.quantity)" }
                .sorted()
            return shown == (try storedSlots(database, deck.id)).sorted()
        }

        await model.add(card)
        #expect(try shownMatchesStored())

        await model.setQuantity(3, of: try #require(model.items.first?.id), in: .main)
        #expect(try shownMatchesStored())
        #expect(model.items.first?.quantity == 3)

        await model.move(try #require(model.items.first?.id), from: .main, to: .side, copies: 2)
        #expect(try shownMatchesStored())

        await model.setQuantity(0, of: try #require(model.items.first?.id), in: .main)
        #expect(try shownMatchesStored())

        // Including after a refusal.
        let refusing = editor(repository, catalogue, editing: RefusingDeckEditor())
        await refusing.load(deckID: deck.id)
        await refusing.setQuantity(9, of: try #require(refusing.items.first?.id), in: .side)
        let shown = refusing.items
            .map { "\($0.section.rawValue)/\($0.id.rawValue)x\($0.quantity)" }
            .sorted()
        #expect(shown == (try storedSlots(database, deck.id)).sorted())
    }

    /// Evidence for R2.AC5: legality is re-read after the edit, so what is
    /// reported describes the deck as it now stands rather than as it was.
    @Test func legalityIsReportedForTheEditedDeck() async throws {
        let (_, repository, catalogue) = try rig()
        let deck = try await repository.createDeck(name: "Nuovo", format: .tcg)
        let model = editor(repository, catalogue)
        await model.load(deckID: deck.id)
        let card = try #require(model.candidates.first)

        await model.add(card)
        let artwork = try #require(model.items.first?.id)
        let beforeViolations = model.legality?.violations.count ?? 0

        // Four copies of a card breaks the absolute limit.
        await model.setQuantity(4, of: artwork, in: .main)

        let violations = try #require(model.legality?.violations)
        #expect(violations.count > beforeViolations)
        #expect(violations.contains {
            if case .overCopyLimit = $0 { return true }
            return false
        })

        // Undoing the count removes the violation with it.
        await model.setQuantity(1, of: artwork, in: .main)
        #expect(!(model.legality?.violations ?? []).contains {
            if case .overCopyLimit = $0 { return true }
            return false
        })
    }
}
