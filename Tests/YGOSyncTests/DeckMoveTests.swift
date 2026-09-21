import Foundation
import GRDB
import Testing
import YGOCore
import YGONetworking
import YGOPersistence
@testable import YGOSync

@Suite("Deck moves")
struct DeckMoveTests {
    private struct Rig {
        let repository: SQLiteDeckRepository
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
        return Rig(repository: SQLiteDeckRepository(database: database),
                   database: database, cards: cards)
    }

    private func readSync<T>(
        _ database: DatabaseQueue, _ body: (Database) throws -> T
    ) throws -> T {
        try database.read(body)
    }

    private func artwork(_ rig: Rig, at index: Int) throws -> ArtworkIdentifier {
        let image = try #require(rig.cards[index].cardImages.first)
        return ArtworkIdentifier(image.id)
    }

    private func rows(
        _ rig: Rig, _ deck: Deck, _ section: DeckSection
    ) throws -> [(artwork: Int, quantity: Int)] {
        try readSync(rig.database) { db in
            try Row.fetchAll(db, sql: """
                SELECT artwork_id, quantity FROM deck_slot
                WHERE deck_id = ? AND section = ? ORDER BY artwork_id
                """, arguments: [deck.id, section.rawValue])
                .map { (artwork: $0["artwork_id"] as Int, quantity: $0["quantity"] as Int) }
        }
    }

    private func total(_ rig: Rig, _ deck: Deck) throws -> Int {
        try readSync(rig.database) { db in
            try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(quantity), 0) FROM deck_slot WHERE deck_id = ?
                """, arguments: [deck.id])
        } ?? 0
    }

    /// Evidence for R3.AC1: a move is a transfer. The total is the number that
    /// proves nothing was created or lost on the way across.
    @Test func movingTwoCopiesLeavesTheTotalUnchanged() async throws {
        let rig = try seeded()
        let deck = try await rig.repository.createDeck(name: "Test", format: .tcg)
        let card = try artwork(rig, at: 0)

        try await rig.repository.setQuantity(
            artwork: card, section: .main, to: 3, in: deck.id)
        let before = try total(rig, deck)
        #expect(before == 3)

        let moved = try await rig.repository.move(
            artwork: card, from: .main, to: .side, copies: 2, in: deck.id)

        #expect(moved == 2)
        #expect(try rows(rig, deck, .main).first?.quantity == 1)
        #expect(try rows(rig, deck, .side).first?.quantity == 2)
        #expect(try total(rig, deck) == before)
    }

    /// Evidence for R3.AC2: a slot is identified by its artwork, and two
    /// artworks of the same card are two entries. A move that forgot which one
    /// it carried would file the copies under the wrong picture.
    @Test func theMovedCopiesKeepTheirArtwork() async throws {
        let rig = try seeded()
        let deck = try await rig.repository.createDeck(name: "Test", format: .tcg)

        // A card the catalog holds more than one artwork for.
        let multi = try #require(rig.cards.first { $0.cardImages.count > 1 })
        let images = multi.cardImages
        let first = ArtworkIdentifier(images[0].id)
        let second = ArtworkIdentifier(images[1].id)

        try await rig.repository.setQuantity(
            artwork: first, section: .main, to: 1, in: deck.id)
        try await rig.repository.setQuantity(
            artwork: second, section: .main, to: 2, in: deck.id)

        try await rig.repository.move(
            artwork: second, from: .main, to: .side, copies: 2, in: deck.id)

        // The moved entry is the second artwork, and the first stayed put.
        #expect(try rows(rig, deck, .side).map(\.artwork) == [second.rawValue])
        #expect(try rows(rig, deck, .main).map(\.artwork) == [first.rawValue])
        #expect(try total(rig, deck) == 3)
    }

    /// Evidence for R3.AC3: two cards in the user's own decks already sit in
    /// two sections at once. Moving into an occupied section must add to what
    /// is there, as one entry.
    @Test func movingIntoAnOccupiedSectionSumsIntoOneEntry() async throws {
        let rig = try seeded()
        let deck = try await rig.repository.createDeck(name: "Test", format: .tcg)
        let card = try artwork(rig, at: 0)

        try await rig.repository.setQuantity(
            artwork: card, section: .main, to: 1, in: deck.id)
        try await rig.repository.setQuantity(
            artwork: card, section: .side, to: 2, in: deck.id)

        try await rig.repository.move(
            artwork: card, from: .main, to: .side, copies: 1, in: deck.id)

        let side = try rows(rig, deck, .side)
        #expect(side.count == 1)          // one entry, not two
        #expect(side.first?.quantity == 3)
        #expect(try rows(rig, deck, .main).isEmpty)
        #expect(try total(rig, deck) == 3)
    }

    /// Evidence for R3.AC4: the source entry is deleted, not left at zero. The
    /// schema's check refuses a zero quantity before any tidying afterwards
    /// could run, which this project has already been caught by once.
    @Test func movingEveryCopyLeavesNoEntryBehind() async throws {
        let rig = try seeded()
        let deck = try await rig.repository.createDeck(name: "Test", format: .tcg)
        let card = try artwork(rig, at: 0)

        try await rig.repository.setQuantity(
            artwork: card, section: .main, to: 2, in: deck.id)
        try await rig.repository.move(
            artwork: card, from: .main, to: .extra, copies: 2, in: deck.id)

        #expect(try rows(rig, deck, .main).isEmpty)
        #expect(try rows(rig, deck, .extra).first?.quantity == 2)

        let zeros = try readSync(rig.database) { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM deck_slot WHERE quantity <= 0")
        }
        #expect(zeros == 0)
    }

    /// Evidence for R3.AC5: a section onto itself is refused before any SQL
    /// runs, rather than being a delete and an insert that happen to cancel.
    @Test func movingASectionOntoItselfChangesNothing() async throws {
        let rig = try seeded()
        let deck = try await rig.repository.createDeck(name: "Test", format: .tcg)
        let card = try artwork(rig, at: 0)

        try await rig.repository.setQuantity(
            artwork: card, section: .main, to: 2, in: deck.id)
        let before = try rows(rig, deck, .main)

        let moved = try await rig.repository.move(
            artwork: card, from: .main, to: .main, copies: 1, in: deck.id)

        #expect(moved == 0)
        #expect(try rows(rig, deck, .main).map(\.quantity) == before.map(\.quantity))
        #expect(try total(rig, deck) == 2)

        // Moving zero copies is equally a no-op, and equally not a failure.
        #expect(try await rig.repository.move(
            artwork: card, from: .main, to: .side, copies: 0, in: deck.id) == 0)
        #expect(try total(rig, deck) == 2)
    }

    /// Evidence for R3.AC6: asking for more than is held moves what is held.
    /// A drag that reports the wrong count must not invent copies.
    @Test func askingToMoveMoreThanIsHeldMovesWhatIsThere() async throws {
        let rig = try seeded()
        let deck = try await rig.repository.createDeck(name: "Test", format: .tcg)
        let card = try artwork(rig, at: 0)

        try await rig.repository.setQuantity(
            artwork: card, section: .main, to: 2, in: deck.id)

        let moved = try await rig.repository.move(
            artwork: card, from: .main, to: .side, copies: 5, in: deck.id)

        #expect(moved == 2)
        #expect(try rows(rig, deck, .main).isEmpty)
        #expect(try rows(rig, deck, .side).first?.quantity == 2)
        #expect(try total(rig, deck) == 2)

        // Moving a card the section does not hold moves nothing at all.
        let absent = try artwork(rig, at: 1)
        #expect(try await rig.repository.move(
            artwork: absent, from: .main, to: .side, copies: 1, in: deck.id) == 0)
        #expect(try total(rig, deck) == 2)
    }
}
