import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

/// Holds a card read open so a test can decide which of two selections
/// finishes first.
final class GatedCardReader: CardRepository, @unchecked Sendable {
    struct Failure: Error {}

    private let inner: SQLiteCardRepository
    private let lock = NSLock()
    private var _reads = 0
    var reads: Int { lock.withLock { _reads } }

    var failing = false
    var held: CardIdentifier?
    private var gate: CheckedContinuation<Void, Never>?

    init(inner: SQLiteCardRepository) { self.inner = inner }

    func hold(_ identifier: CardIdentifier) { held = identifier }

    func release() {
        held = nil
        gate?.resume()
        gate = nil
    }

    func isWaiting() -> Bool { lock.withLock { gate != nil } }

    func card(with identifier: CardIdentifier) async throws -> Card? {
        lock.withLock { _reads += 1 }
        if failing { throw Failure() }
        if held == identifier {
            await withCheckedContinuation { continuation in
                lock.withLock { gate = continuation }
            }
        }
        return try await inner.card(with: identifier)
    }

    func card(withArtwork identifier: ArtworkIdentifier) async throws -> Card? {
        try await inner.card(withArtwork: identifier)
    }
    func banStatus(for identifier: CardIdentifier, in format: CardFormat) async throws -> BanStatus {
        try await inner.banStatus(for: identifier, in: format)
    }
    func cardCount() async throws -> Int { try await inner.cardCount() }
}

@MainActor
@Suite("Deck preview")
struct DeckPreviewTests {
    private func rig() throws -> (DatabaseQueue, SQLiteDeckRepository, GatedCardReader) {
        let (database, repository) = try RealDeck.seededRepository()
        return (database, repository, GatedCardReader(
            inner: SQLiteCardRepository(database: database)))
    }

    private func editor(
        _ database: DatabaseQueue, _ decks: SQLiteDeckRepository,
        reader: (any CardRepository)?
    ) -> DeckEditorViewModel {
        DeckEditorViewModel(
            repository: decks, validator: DeckValidator(),
            catalogue: SQLiteCardRepository(database: database),
            editing: decks, reader: reader)
    }

    private func loaded() async throws -> (DeckEditorViewModel, GatedCardReader) {
        let (database, decks, reader) = try rig()
        let deck = try await decks.createDeck(name: "Nuovo", format: .tcg)
        let model = editor(database, decks, reader: reader)
        await model.load(deckID: deck.id)
        return (model, reader)
    }

    /// Evidence for R1.AC1: a deck list names cards and says nothing about
    /// them. Selecting one now answers the question without leaving the deck.
    @Test func selectingAnEntryPreviewsItsCard() async throws {
        let (model, reader) = try await loaded()
        #expect(model.previewCard == nil)

        let candidate = try #require(model.candidates.first { !$0.frame.belongsInExtraDeck })
        await model.add(candidate, to: .main)
        let entry = try #require(model.items.first)

        await model.previewEntry(entry)

        let card = try #require(model.previewCard)
        #expect(card.id == entry.card)
        #expect(!card.englishEffect.isEmpty)
        #expect(model.previewFailure == nil)
        #expect(reader.reads == 1)

        // Previewing whatever is selected is the same thing an arrow key does.
        await model.previewSelection()
        #expect(model.previewCard?.id == entry.card)
    }

    /// Evidence for R1.AC5: an empty panel and an unreadable card look
    /// identical on screen and are not the same thing.
    @Test func anUnreadableCardIsStatedRatherThanLeftBlank() async throws {
        let (model, reader) = try await loaded()
        let candidate = try #require(model.candidates.first { !$0.frame.belongsInExtraDeck })
        await model.add(candidate, to: .main)
        let entry = try #require(model.items.first)

        reader.failing = true
        await model.previewEntry(entry)

        #expect(model.previewCard == nil)
        let failure = try #require(model.previewFailure)
        #expect(failure.contains("non leggibile"))

        // A successful read afterwards clears the failure rather than leaving
        // a stale message beside a good card.
        reader.failing = false
        await model.previewEntry(entry)
        #expect(model.previewCard != nil)
        #expect(model.previewFailure == nil)

        // An editor with no reader says so instead of failing silently.
        let (database, decks, _) = try rig()
        let deck = try await decks.createDeck(name: "Senza lettore", format: .tcg)
        let bare = editor(database, decks, reader: nil)
        await bare.load(deckID: deck.id)
        await bare.previewEntry(entry)
        #expect(bare.previewCard == nil)
        #expect(bare.previewFailure != nil)
    }

    /// Evidence for R1.AC6: nothing selected is not a failure, and the panel
    /// has to invite a selection rather than report a problem.
    @Test func aFreshlyLoadedDeckHasNoPreviewAndNoFailure() async throws {
        let (model, reader) = try await loaded()

        #expect(model.previewCard == nil)
        #expect(model.previewFailure == nil)
        #expect(model.isPreviewVisible)
        #expect(reader.reads == 0)

        // Previewing the selection when there is none is a no-op, not an error.
        #expect(model.selectedItem == nil)
        await model.previewSelection()
        #expect(model.previewCard == nil)
        #expect(model.previewFailure == nil)
    }

    /// Evidence for R1.AC1: walking a deck with the arrow keys issues a read
    /// per row. One that answers after the selection moved on belongs to a
    /// card the user is no longer looking at.
    @Test func aReadAnsweredAfterTheSelectionMovedOnIsDiscarded() async throws {
        let (model, reader) = try await loaded()
        let first = try #require(model.candidates.first { !$0.frame.belongsInExtraDeck })
        let second = try #require(
            model.candidates.dropFirst().first { !$0.frame.belongsInExtraDeck })
        await model.add(first, to: .main)
        await model.add(second, to: .main)
        #expect(model.items.count == 2)

        let stale = model.items[0]
        let wanted = model.items[1]

        reader.hold(stale.card)
        let pending = Task { await model.previewEntry(stale) }
        while !reader.isWaiting() { await Task.yield() }

        await model.previewEntry(wanted)
        #expect(model.previewCard?.id == wanted.card)

        // The abandoned read now finishes and must change nothing.
        reader.release()
        await pending.value
        #expect(model.previewCard?.id == wanted.card)
        #expect(model.previewFailure == nil)
    }

    /// Evidence for R1.AC3: the deck list is what the user is working in, so
    /// changing the panel must not move it.
    @Test func selectingAnotherEntryLeavesTheDeckUndisturbed() async throws {
        let (model, _) = try await loaded()
        let first = try #require(model.candidates.first { !$0.frame.belongsInExtraDeck })
        let second = try #require(
            model.candidates.dropFirst().first { !$0.frame.belongsInExtraDeck })
        await model.add(first, to: .main)
        await model.add(second, to: .side)

        let before = model.items.map { "\($0.section.rawValue)/\($0.id.rawValue)x\($0.quantity)" }
        await model.previewEntry(model.items[0])
        await model.previewEntry(model.items[1])

        let after = model.items.map { "\($0.section.rawValue)/\($0.id.rawValue)x\($0.quantity)" }
        #expect(after == before)
        #expect(model.previewCard?.id == model.items[1].card)
        #expect(model.legality != nil)
    }

    /// Evidence for R1.AC4: a search result is already a card, so this costs
    /// no read — and it lets a card be read before it is added, not after.
    @Test func selectingACandidatePreviewsItWithoutACatalogRead() async throws {
        let (model, reader) = try await loaded()
        let candidate = try #require(model.candidates.first)
        #expect(reader.reads == 0)

        model.previewCandidate(candidate)

        #expect(model.previewCard?.id == candidate.id)
        #expect(model.previewFailure == nil)
        #expect(reader.reads == 0, "a candidate needed a catalog read")
        #expect(model.items.isEmpty, "previewing added the card to the deck")
    }

    /// Evidence for R2.AC3: a session spent adjusting counts does not need
    /// effect text on screen, and reopening should not be a second search.
    @Test func dismissingClearsThePanelAndKeepsTheCardForItsReturn() async throws {
        let (model, reader) = try await loaded()
        let candidate = try #require(model.candidates.first { !$0.frame.belongsInExtraDeck })
        await model.add(candidate, to: .main)
        await model.previewEntry(try #require(model.items.first))
        let shown = try #require(model.previewCard)
        let readsBefore = reader.reads

        model.dismissPreview()
        #expect(!model.isPreviewVisible)
        #expect(model.previewCard?.id == shown.id, "the card was thrown away")

        model.restorePreview()
        #expect(model.isPreviewVisible)
        #expect(model.previewCard?.id == shown.id)
        #expect(reader.reads == readsBefore, "restoring cost a second read")
    }
}
