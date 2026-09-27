import Foundation
import GRDB
import Testing
import YGOCore
import YGONetworking
import YGOPersistence
@testable import YGOSync

/// A catalog update rewrites every card's artworks and printings, and the
/// user's decks and lots point at exactly those rows.
///
/// The writer used to delete a card's artworks and printings and insert them
/// again. With foreign keys on, the delete of an artwork a deck held failed,
/// so the first update after any deck existed rolled back whole and the
/// catalog stayed on the version it had before the deck. `R2.AC2` and
/// `R2.AC4` of `card-catalog` must hold whatever the user has built on top.
@Suite("Catalog rewrite with user data")
struct CatalogRewriteTests {
    private static let firstVersion = CatalogVersion(
        databaseVersion: "147.04", lastUpdate: "2026-09-16 00:05:12")

    private struct Rig {
        let database: DatabaseQueue
        let store: SQLiteCatalogStore
        let client: StubCatalogClient
        let decks: SQLiteDeckRepository
        let collection: SQLiteCollectionRepository
        let cards: [CatalogCardPayload]
    }

    private func seeded() async throws -> Rig {
        let database = try SyncFixture.migratedDatabase()
        let store = SQLiteCatalogStore(database: database)
        let cards = try SyncFixture.cards("catalog-en.json")
        let client = StubCatalogClient(version: Self.firstVersion, english: cards)
        _ = try await synchronizer(client, store).synchronize()

        return Rig(
            database: database, store: store, client: client,
            decks: SQLiteDeckRepository(database: database, now: { SyncFixture.observedAt }),
            collection: SQLiteCollectionRepository(database: database),
            cards: cards)
    }

    private func synchronizer(_ client: StubCatalogClient, _ store: any CatalogStore) -> CatalogSynchronizer {
        CatalogSynchronizer(client: client, store: store, now: { SyncFixture.observedAt })
    }

    /// Publishes a newer version, optionally with one card replaced, and
    /// synchronises against it.
    private func update(_ rig: Rig, replacing card: CatalogCardPayload? = nil) async throws -> CatalogSyncOutcome {
        if let card {
            await rig.client.replaceEnglish(with: rig.cards.map { $0.id == card.id ? card : $0 })
        }
        await rig.client.advanceVersion(to: "148.00")
        return try await synchronizer(rig.client, rig.store).synchronize()
    }

    /// The same card as upstream would publish it after dropping one artwork or
    /// one printing. Built through the real decoder, so the payload is one the
    /// client could have produced.
    private func republished(
        _ card: CatalogCardPayload,
        withoutArtwork artwork: Int? = nil,
        withoutSetCode setCode: String? = nil
    ) throws -> CatalogCardPayload {
        let decoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(card))
        var object = try #require(decoded as? [String: Any])
        if let artwork, let images = object["card_images"] as? [[String: Any]] {
            object["card_images"] = images.filter { ($0["id"] as? Int) != artwork }
        }
        if let setCode, let sets = object["card_sets"] as? [[String: Any]] {
            object["card_sets"] = sets.filter { ($0["set_code"] as? String) != setCode }
        }
        let data = try JSONSerialization.data(withJSONObject: ["data": [object]])
        let cards = try YGOProDeckCatalogClient.decodeDataset(data)
        return try #require(cards.first)
    }

    private struct Printing: Equatable, Sendable {
        let id: Int64
        let setCode: String
        let rarity: String?
    }

    private func printings(of cardID: Int, in rig: Rig) async throws -> [Printing] {
        try await rig.database.read { db in
            try Row.fetchAll(db, sql:
                "SELECT id, set_code, rarity FROM card_print WHERE card_id = ? ORDER BY id",
                arguments: [cardID]
            ).map { Printing(id: $0["id"], setCode: $0["set_code"], rarity: $0["rarity"]) }
        }
    }

    private func artworkIsStored(_ artwork: Int, for cardID: Int, in rig: Rig) async throws -> Bool {
        try await rig.database.read { db in
            try Bool.fetchOne(db, sql:
                "SELECT EXISTS(SELECT 1 FROM card_artwork WHERE artwork_id = ? AND card_id = ?)",
                arguments: [artwork, cardID]) ?? false
        }
    }

    // MARK: - The reported failure

    /// Evidence for `card-catalog` R2.AC2 and R2.AC4 with a deck in place: a
    /// new upstream version is stored, and the deck comes out holding exactly
    /// what it held.
    @Test func anUpdateIsStoredWhileADeckHoldsACard() async throws {
        let rig = try await seeded()
        let image = try #require(rig.cards[0].cardImages.first)
        let deck = try await rig.decks.createDeck(name: "Prova", format: .tcg)
        try await rig.decks.addCard(artwork: ArtworkIdentifier(image.id), section: .main, to: deck.id)
        let before = try #require(try await rig.decks.deck(with: deck.id))

        let outcome = try await update(rig)

        #expect(outcome == .updated(cardCount: rig.cards.count))
        let stored = try await rig.store.storedVersion()
        #expect(stored?.databaseVersion == "148.00")
        let after = try #require(try await rig.decks.deck(with: deck.id))
        #expect(after.slots == before.slots)
    }

    /// The same, for a lot recorded against a printing: the update is stored
    /// and the lot still names the printing it named, by the same identifier.
    @Test func anUpdateIsStoredWhileALotHoldsAPrinting() async throws {
        let rig = try await seeded()
        let card = try #require(rig.cards.first { ($0.cardSets ?? []).count >= 2 })
        let held = try #require(try await printings(of: card.id, in: rig).last)
        try await rig.collection.addCopy(
            cardID: CardIdentifier(card.id), printID: held.id, condition: .nearMint, locationID: nil)

        let outcome = try await update(rig)

        #expect(outcome == .updated(cardCount: rig.cards.count))
        let lots = try await rig.collection.entries(forCard: CardIdentifier(card.id))
        #expect(lots.map(\.printID) == [held.id])

        let after = try await printings(of: card.id, in: rig)
        // Same identifier, same printing: the lot still names what it named.
        #expect(after.contains(held))
        // Every printing upstream still lists is there once, the held one included.
        #expect(after.count == (card.cardSets ?? []).count)
    }

    // MARK: - Upstream withdrawing what the user holds

    /// An update must not take a card out of a deck. An artwork upstream no
    /// longer lists stays while a deck holds it.
    @Test func anArtworkUpstreamWithdrewStaysWhileADeckHoldsIt() async throws {
        let rig = try await seeded()
        let card = try #require(rig.cards.first { $0.cardImages.count >= 2 })
        let withdrawn = card.cardImages[1].id
        let deck = try await rig.decks.createDeck(name: "Prova", format: .tcg)
        try await rig.decks.addCard(artwork: ArtworkIdentifier(withdrawn), section: .main, to: deck.id)

        let outcome = try await update(rig, replacing: try republished(card, withoutArtwork: withdrawn))

        #expect(outcome == .updated(cardCount: rig.cards.count))
        let after = try #require(try await rig.decks.deck(with: deck.id))
        #expect(after.slots.map(\.artwork) == [ArtworkIdentifier(withdrawn)])
        let stillStored = try await artworkIsStored(withdrawn, for: card.id, in: rig)
        #expect(stillStored)
    }

    /// A lot must not lose the printing it was recorded against. A printing
    /// upstream no longer lists stays while a lot holds it.
    @Test func aPrintingUpstreamWithdrewStaysWhileALotHoldsIt() async throws {
        let rig = try await seeded()
        let card = try #require(rig.cards.first { ($0.cardSets ?? []).count >= 2 })
        let held = try #require(try await printings(of: card.id, in: rig).first)
        try await rig.collection.addCopy(
            cardID: CardIdentifier(card.id), printID: held.id, condition: .nearMint, locationID: nil)

        let outcome = try await update(rig, replacing: try republished(card, withoutSetCode: held.setCode))

        #expect(outcome == .updated(cardCount: rig.cards.count))
        let lots = try await rig.collection.entries(forCard: CardIdentifier(card.id))
        #expect(lots.map(\.printID) == [held.id])
        let after = try await printings(of: card.id, in: rig)
        #expect(after.contains(held))
    }

    /// What nobody holds is still cleared: keeping the held rows must not turn
    /// into keeping every row upstream has withdrawn.
    @Test func withdrawnRowsNobodyHoldsAreStillRemoved() async throws {
        let rig = try await seeded()
        let card = try #require(rig.cards.first {
            $0.cardImages.count >= 2 && ($0.cardSets ?? []).count >= 2
        })
        let withdrawnArtwork = card.cardImages[1].id
        let withdrawnSet = try #require(card.cardSets?.first).setCode
        let trimmed = try republished(
            try republished(card, withoutArtwork: withdrawnArtwork),
            withoutSetCode: withdrawnSet)
        // A lot recorded against no printing puts a null among the lots'
        // printings, as a real collection does. A `NOT IN` over that null would
        // clear nothing at all.
        try await rig.collection.addCopy(
            cardID: CardIdentifier(card.id), printID: nil, condition: .nearMint, locationID: nil)

        let outcome = try await update(rig, replacing: trimmed)

        #expect(outcome == .updated(cardCount: rig.cards.count))
        let stillStored = try await artworkIsStored(withdrawnArtwork, for: card.id, in: rig)
        #expect(!stillStored)
        let codes = try await printings(of: card.id, in: rig).map(\.setCode)
        #expect(!codes.contains(withdrawnSet))
        #expect(codes.count == (trimmed.cardSets ?? []).count)
    }
}
