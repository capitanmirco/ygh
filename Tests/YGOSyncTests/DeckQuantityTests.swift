import Foundation
import GRDB
import Testing
import YGOCore
import YGONetworking
import YGOPersistence
import YGOValidation
@testable import YGOSync

@Suite("Deck quantity editing")
struct DeckQuantityTests {
    private struct Rig {
        let repository: SQLiteDeckRepository
        let validator: DeckValidator
        let database: DatabaseQueue
        let cards: [CatalogCardPayload]
    }

    private func seeded() throws -> Rig {
        let database = try SyncFixture.migratedDatabase()
        let cards = try SyncFixture.cards("catalog-en.json")
        try database.write { db in
            try CatalogWriter().writeEnglishDataset(
                cards, observedAt: SyncFixture.observedAt, into: db)
        }
        return Rig(
            repository: SQLiteDeckRepository(database: database),
            validator: DeckValidator(),
            database: database, cards: cards)
    }

    /// A card the catalog holds, with an artwork to file it under.
    private func artwork(_ rig: Rig, at index: Int) throws -> ArtworkIdentifier {
        let image = try #require(rig.cards[index].cardImages.first)
        return ArtworkIdentifier(image.id)
    }

    /// Non-async on purpose: inside an async test, `database.read` would
    /// resolve to GRDB's async overload and every call site would need `await`.
    private func readSync<T>(
        _ database: DatabaseQueue, _ body: (Database) throws -> T
    ) throws -> T {
        try database.read(body)
    }

    private func quantity(
        _ rig: Rig, _ deck: Deck, _ artwork: ArtworkIdentifier, _ section: DeckSection
    ) throws -> Int? {
        try readSync(rig.database) { db in
            try Int.fetchOne(db, sql: """
                SELECT quantity FROM deck_slot
                WHERE deck_id = ? AND section = ? AND artwork_id = ?
                """, arguments: [deck.id, section.rawValue, artwork.rawValue])
        }
    }

    /// Evidence for R2.AC1: 8 slots in the user's own decks hold three copies.
    /// Getting there one button press at a time is the thing this replaces.
    @Test func setsASectionToHoldExactlyThatManyCopies() async throws {
        let rig = try seeded()
        let deck = try await rig.repository.createDeck(name: "Test", format: .tcg)
        let card = try artwork(rig, at: 0)

        try await rig.repository.addCard(artwork: card, section: .main, to: deck.id)
        #expect(try quantity(rig, deck, card, .main) == 1)

        try await rig.repository.setQuantity(
            artwork: card, section: .main, to: 3, in: deck.id)
        #expect(try quantity(rig, deck, card, .main) == 3)

        // Setting a card that was not there puts it there at that count.
        let other = try artwork(rig, at: 1)
        try await rig.repository.setQuantity(
            artwork: other, section: .side, to: 2, in: deck.id)
        #expect(try quantity(rig, deck, other, .side) == 2)

        // Downwards as well as upwards, and it is exact rather than additive.
        try await rig.repository.setQuantity(
            artwork: card, section: .main, to: 1, in: deck.id)
        #expect(try quantity(rig, deck, card, .main) == 1)

        // Nothing leaked into another section.
        #expect(try quantity(rig, deck, card, .side) == nil)
        let reloaded = try #require(try await rig.repository.deck(with: deck.id))
        #expect(reloaded.count(in: .main) == 1)
        #expect(reloaded.count(in: .side) == 2)
    }

    /// Evidence for R2.AC2: zero is removal, so it needs no path of its own.
    /// The row is deleted rather than left at zero, which the schema's check
    /// would refuse anyway.
    @Test func settingZeroRemovesTheCardFromThatSectionOnly() async throws {
        let rig = try seeded()
        let deck = try await rig.repository.createDeck(name: "Test", format: .tcg)
        let card = try artwork(rig, at: 0)
        let keep = try artwork(rig, at: 1)

        try await rig.repository.setQuantity(
            artwork: card, section: .main, to: 2, in: deck.id)
        try await rig.repository.setQuantity(
            artwork: card, section: .side, to: 1, in: deck.id)
        try await rig.repository.setQuantity(
            artwork: keep, section: .main, to: 3, in: deck.id)

        try await rig.repository.setQuantity(
            artwork: card, section: .main, to: 0, in: deck.id)

        #expect(try quantity(rig, deck, card, .main) == nil)
        // The same card in another section is untouched.
        #expect(try quantity(rig, deck, card, .side) == 1)
        #expect(try quantity(rig, deck, keep, .main) == 3)

        // No zero-quantity row was left behind anywhere.
        let zeros = try readSync(rig.database) { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM deck_slot WHERE quantity <= 0")
        }
        #expect(zeros == 0)

        // Setting zero on something that is not there is not an error.
        try await rig.repository.setQuantity(
            artwork: keep, section: .extra, to: 0, in: deck.id)
        #expect(try quantity(rig, deck, keep, .extra) == nil)
    }

    /// Evidence for R2.AC3: writing stays permissive. Four copies are held and
    /// the violation is reported — the contract `deck-builder` settled, which
    /// this feature adds operations to rather than reopening.
    @Test func anIllegalCountIsAppliedAndReported() async throws {
        let rig = try seeded()
        let deck = try await rig.repository.createDeck(name: "Test", format: .tcg)
        let card = try artwork(rig, at: 0)

        try await rig.repository.setQuantity(
            artwork: card, section: .main, to: 4, in: deck.id)

        // Applied: the deck really holds four.
        #expect(try quantity(rig, deck, card, .main) == 4)

        // And reported: the validator names the copy limit it broke.
        let stored = try #require(try await rig.repository.deck(with: deck.id))
        let index = try await rig.repository.cardIndex(for: stored)
        let violations = rig.validator.violations(in: stored, using: index)

        let overLimit = violations.filter {
            if case .overCopyLimit = $0 { return true }
            return false
        }
        #expect(overLimit.count == 1)
        #expect(!rig.validator.legality(of: stored, using: index).violations.isEmpty)
    }
}
