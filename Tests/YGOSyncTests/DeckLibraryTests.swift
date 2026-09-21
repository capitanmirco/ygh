import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

/// Refuses every write, so a test can see what the library does when storage
/// says no.
struct RefusingDeckBuilder: DeckBuilding {
    struct Refused: Error {}
    let inner: SQLiteDeckRepository

    func createDeck(name: String, format: CardFormat) async throws -> Deck { throw Refused() }
    func addCard(artwork: ArtworkIdentifier, section: DeckSection, to deckID: Int64) async throws {
        throw Refused()
    }
    func removeCard(artwork: ArtworkIdentifier, section: DeckSection, from deckID: Int64) async throws {
        throw Refused()
    }
    func deck(with id: Int64) async throws -> Deck? { try await inner.deck(with: id) }
    func cardIndex(for deck: Deck) async throws -> DeckCardIndex { try await inner.cardIndex(for: deck) }
    func changeFormat(_ deckID: Int64, to format: CardFormat) async throws { throw Refused() }
    func delete(_ deckID: Int64, confirmed: Bool) async throws { throw Refused() }
    func resolveArtwork(_ artwork: ArtworkIdentifier) async throws -> CardIdentifier? {
        try await inner.resolveArtwork(artwork)
    }
}

@MainActor
@Suite("Deck library")
struct DeckLibraryTests {
    private func rig() throws -> (DatabaseQueue, SQLiteDeckRepository) {
        try RealDeck.seededRepository()
    }

    private func library(_ decks: SQLiteDeckRepository) -> DeckLibraryViewModel {
        DeckLibraryViewModel(repository: decks, listing: decks, library: decks)
    }

    /// Evidence for R1.AC1: a deck can only enter this application by being
    /// imported. `createDeck` was certified and had no caller.
    @Test func creatingADeckStoresItAndOpensIt() async throws {
        let (_, decks) = try rig()
        let model = library(decks)
        await model.load()
        #expect(model.decks.isEmpty)

        let created = try #require(await model.createDeck(named: "Burn", format: .tcg))

        #expect(model.decks.count == 1)
        #expect(model.decks.first?.name == "Burn")
        #expect(model.lastFailure == nil)
        // Created to be filled, so the interface opens it.
        #expect(model.deckToOpen == created.id)

        // And it is genuinely stored, not merely listed.
        let stored = try #require(try await decks.deck(with: created.id))
        #expect(stored.name == "Burn")
        #expect(stored.slots.isEmpty)
    }

    /// Evidence for R1.AC2: the format decides which cards a deck may hold and
    /// which restrictions apply to it, so it has to be recorded at creation.
    @Test func aDeckIsJudgedByTheFormatItWasCreatedFor() async throws {
        let (_, decks) = try rig()
        let model = library(decks)

        let goat = try #require(await model.createDeck(named: "Retro", format: .goat))
        let modern = try #require(await model.createDeck(named: "Moderno", format: .tcg))

        #expect(goat.format == .goat)
        #expect(modern.format == .tcg)

        let storedGoat = try #require(try await decks.deck(with: goat.id))
        #expect(storedGoat.format == .goat)
        #expect(storedGoat.format.definingListDate == "2005-03-01")
    }

    /// Evidence for R1.AC3: a list of blank names is unreadable a week later.
    @Test func anUnnamedDeckIsNamedRatherThanStoredBlank() async throws {
        let (_, decks) = try rig()
        let model = library(decks)

        let unnamed = try #require(await model.createDeck(named: "", format: .tcg))
        #expect(unnamed.name == DeckLibraryViewModel.defaultName)

        // Whitespace is not a name either.
        let blank = try #require(await model.createDeck(named: "   ", format: .tcg))
        #expect(blank.name == DeckLibraryViewModel.defaultName)

        // A real name survives its surrounding spaces.
        let trimmed = try #require(await model.createDeck(named: "  Chaos  ", format: .tcg))
        #expect(trimmed.name == "Chaos")
    }

    /// Evidence for R1.AC4: a deck is its row, not its name. Refusing a
    /// duplicate name would stop someone keeping two versions of one idea.
    @Test func twoDecksMayShareAName() async throws {
        let (_, decks) = try rig()
        let model = library(decks)

        let first = try #require(await model.createDeck(named: "Chaos", format: .goat))
        let second = try #require(await model.createDeck(named: "Chaos", format: .goat))

        #expect(first.id != second.id)
        #expect(model.decks.count == 2)
        #expect(model.decks.allSatisfy { $0.name == "Chaos" })
        #expect(model.lastFailure == nil)

        // Both open independently.
        #expect(try await decks.deck(with: first.id) != nil)
        #expect(try await decks.deck(with: second.id) != nil)
    }

    /// Evidence for R1.AC5: a creation that fails and says nothing is
    /// indistinguishable from one that succeeded and did nothing.
    @Test func aRefusedCreationAddsNothingAndSaysSo() async throws {
        let (_, decks) = try rig()
        let model = library(decks)
        await model.createDeck(named: "Esistente", format: .tcg)
        let before = model.decks.count

        let refusing = DeckLibraryViewModel(
            repository: RefusingDeckBuilder(inner: decks), listing: decks, library: decks)
        await refusing.load()
        let created = await refusing.createDeck(named: "Nuovo", format: .tcg)

        #expect(created == nil)
        let failure = try #require(refusing.lastFailure)
        #expect(failure.contains("non creato"))

        await model.load()
        #expect(model.decks.count == before)
    }

    /// Evidence for R3.AC1: a list that is a history of imports is not a list
    /// of your decks.
    @Test func renamingStoresTheNewNameAndShowsIt() async throws {
        let (_, decks) = try rig()
        let model = library(decks)
        let deck = try #require(await model.createDeck(named: "Senza nome", format: .tcg))

        await model.rename(deck.id, to: "Lockdown Burn")

        #expect(model.lastFailure == nil)
        #expect(model.decks.first?.name == "Lockdown Burn")
        #expect(try await decks.deck(with: deck.id)?.name == "Lockdown Burn")

        // An empty new name is refused rather than stored.
        await model.rename(deck.id, to: "   ")
        #expect(model.lastFailure != nil)
        #expect(try await decks.deck(with: deck.id)?.name == "Lockdown Burn")
    }

    /// Evidence for R3.AC2: the copy is a copy. Editing it must not reach back
    /// into the deck it came from.
    @Test func aDuplicateHoldsTheSameCardsAndEditingItLeavesTheOriginal() async throws {
        let (database, decks) = try rig()
        let model = library(decks)
        let original = try #require(await model.createDeck(named: "Originale", format: .tcg))

        let editor = DeckEditorViewModel(
            repository: decks, validator: DeckValidator(),
            catalogue: SQLiteCardRepository(database: database), editing: decks)
        await editor.load(deckID: original.id)
        let card = try #require(editor.candidates.first { !$0.frame.belongsInExtraDeck })
        await editor.add(card, to: .main)
        await editor.setQuantity(3, of: try #require(editor.items.first?.id), in: .main)

        let copy = try #require(await model.duplicate(original.id))
        #expect(copy.name == "Originale (copia)")
        #expect(copy.id != original.id)

        let copied = try #require(try await decks.deck(with: copy.id))
        let source = try #require(try await decks.deck(with: original.id))
        #expect(copied.slots.count == source.slots.count)
        #expect(copied.count(in: .main) == 3)

        // Editing the copy leaves the original where it was.
        await editor.load(deckID: copy.id)
        await editor.setQuantity(1, of: try #require(editor.items.first?.id), in: .main)
        #expect(try await decks.deck(with: original.id)?.count(in: .main) == 3)
        #expect(try await decks.deck(with: copy.id)?.count(in: .main) == 1)
    }

    /// Evidence for R3.AC3: deleting a deck cannot be undone, so it is a
    /// deliberate second step rather than a click.
    @Test func deletingAsksFirstAndOnlyThenDeletes() async throws {
        let (_, decks) = try rig()
        let model = library(decks)
        let deck = try #require(await model.createDeck(named: "Da eliminare", format: .tcg))

        // Confirming with nothing pending does nothing.
        #expect(await model.confirmDeletion() == false)
        #expect(model.decks.count == 1)

        model.requestDeletion(deck.id)
        #expect(model.pendingDeletion == deck.id)
        #expect(model.decks.count == 1, "asking already deleted it")

        // Changing your mind leaves the deck.
        model.cancelDeletion()
        #expect(model.pendingDeletion == nil)
        #expect(try await decks.deck(with: deck.id) != nil)

        model.requestDeletion(deck.id)
        #expect(await model.confirmDeletion())
        #expect(model.decks.isEmpty)
        #expect(try await decks.deck(with: deck.id) == nil)
    }

    /// Evidence for R3.AC4: a deck built for one format and played in another
    /// is judged by the one it is in now.
    @Test func changingFormatReJudgesTheDeck() async throws {
        let (database, decks) = try rig()
        let model = library(decks)
        let deck = try #require(await model.createDeck(named: "Mutevole", format: .tcg))

        await model.changeFormat(deck.id, to: .goat)
        #expect(model.lastFailure == nil)
        #expect(try await decks.deck(with: deck.id)?.format == .goat)

        // The editor now offers the GOAT pool rather than the TCG one.
        let editor = DeckEditorViewModel(
            repository: decks, validator: DeckValidator(),
            catalogue: SQLiteCardRepository(database: database), editing: decks)
        await editor.load(deckID: deck.id)
        #expect(editor.candidates.allSatisfy { $0.formats.contains(.goat) })
    }
}

@MainActor
@Suite("Deck library list freshness")
struct DeckLibraryFreshnessTests {
    /// The sidebar showed a copy of the list, refreshed when its *count*
    /// changed. A rename does not change how many decks there are, so the old
    /// name stayed on screen; a delete did change it, but the copy was one
    /// step behind.
    ///
    /// The fix was to read the library's list directly. This is what that
    /// list has to do for the fix to hold: change on every operation,
    /// including the ones that leave the count alone.
    @Test func thePublishedListReflectsEveryOperationNotOnlyTheCounting() async throws {
        let (_, decks) = try RealDeck.seededRepository()
        let model = DeckLibraryViewModel(repository: decks, listing: decks, library: decks)
        await model.load()

        let first = try #require(await model.createDeck(named: "Primo", format: .tcg))
        #expect(model.decks.map(\.name) == ["Primo"])

        // A rename leaves the count alone and must still be visible.
        let countBefore = model.decks.count
        await model.rename(first.id, to: "Rinominato")
        #expect(model.decks.count == countBefore)
        #expect(model.decks.map(\.name) == ["Rinominato"])

        // So does a format change.
        await model.changeFormat(first.id, to: .goat)
        #expect(model.decks.count == countBefore)
        #expect(model.decks.first?.format == .goat)

        // A duplicate adds one, with its own name.
        let copy = try #require(await model.duplicate(first.id))
        #expect(model.decks.count == 2)
        #expect(Set(model.decks.map(\.name)) == ["Rinominato", "Rinominato (copia)"])

        // And a deletion removes exactly the one asked for.
        model.requestDeletion(copy.id)
        #expect(await model.confirmDeletion())
        #expect(model.decks.map(\.id) == [first.id])
        #expect(model.decks.map(\.name) == ["Rinominato"])
    }

    /// Deleting the deck that is open has to be possible, which is the case
    /// the user hit. The model's part of it is that the list loses the deck
    /// and the identifier stops resolving.
    @Test func theDeckBeingEditedCanBeDeleted() async throws {
        let (database, decks) = try RealDeck.seededRepository()
        let model = DeckLibraryViewModel(repository: decks, listing: decks, library: decks)
        await model.load()
        let deck = try #require(await model.createDeck(named: "Aperto", format: .tcg))

        // Put a card in it, so it is not an empty row being removed.
        let editor = DeckEditorViewModel(
            repository: decks, validator: DeckValidator(),
            catalogue: SQLiteCardRepository(database: database), editing: decks)
        await editor.load(deckID: deck.id)
        let card = try #require(editor.candidates.first { !$0.frame.belongsInExtraDeck })
        await editor.add(card, to: .main)
        #expect(editor.items.count == 1)

        model.requestDeletion(deck.id)
        #expect(model.pendingDeletion == deck.id)
        #expect(await model.confirmDeletion())

        #expect(model.decks.isEmpty)
        #expect(model.lastFailure == nil)
        #expect(try await decks.deck(with: deck.id) == nil)

        // And nothing is left behind: the deck's slots went with it.
        // Non-async closure on purpose, or GRDB's async `read` is chosen.
        func readSync<T>(_ body: (Database) throws -> T) throws -> T {
            try database.read(body)
        }
        let orphans = try readSync { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM deck_slot WHERE deck_id = ?",
                             arguments: [deck.id])
        }
        #expect(orphans == 0)
    }
}

@MainActor
@Suite("Deck deletion sequencing")
struct DeckDeletionSequencingTests {
    /// The trap that made a deck undeletable from the interface.
    ///
    /// `confirmDeletion` reads `pendingDeletion` and returns false when it is
    /// nil. A SwiftUI alert dismisses itself before running its button's
    /// action, and that dismissal ran `cancelDeletion` — so by the time the
    /// action asked to confirm, there was nothing pending and the deck
    /// survived. The model behaved exactly as specified; the sequence around
    /// it was wrong.
    ///
    /// This is that sequence, written down so it cannot come back silently.
    @Test func confirmingAfterACancelDeletesNothing() async throws {
        let (_, decks) = try RealDeck.seededRepository()
        let model = DeckLibraryViewModel(repository: decks, listing: decks, library: decks)
        await model.load()
        let deck = try #require(await model.createDeck(named: "Da eliminare", format: .tcg))

        model.requestDeletion(deck.id)
        // What the alert's dismissal did, before the button's action ran.
        model.cancelDeletion()

        #expect(await model.confirmDeletion() == false)
        #expect(model.decks.count == 1, "the deck was deleted without a pending request")
        #expect(try await decks.deck(with: deck.id) != nil)
    }

    /// And the sequence the interface uses now: the deck is captured while
    /// the alert is built, and re-asserted before confirming.
    @Test func reAssertingTheCapturedDeckDeletesIt() async throws {
        let (_, decks) = try RealDeck.seededRepository()
        let model = DeckLibraryViewModel(repository: decks, listing: decks, library: decks)
        await model.load()
        let deck = try #require(await model.createDeck(named: "Da eliminare", format: .tcg))
        let other = try #require(await model.createDeck(named: "Da tenere", format: .tcg))

        model.requestDeletion(deck.id)
        // The alert captures this while it is being built.
        let captured = try #require(model.pendingDeletion)
        // Then dismisses, clearing it.
        model.cancelDeletion()
        #expect(model.pendingDeletion == nil)

        // The action re-asserts what the user confirmed.
        model.requestDeletion(captured)
        #expect(await model.confirmDeletion())

        #expect(model.decks.map(\.id) == [other.id])
        #expect(try await decks.deck(with: deck.id) == nil)
        #expect(try await decks.deck(with: other.id) != nil, "it deleted the wrong deck")
        #expect(model.lastFailure == nil)
    }
}
