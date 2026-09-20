import Foundation
import GRDB
import YGOCore
import YGONetworking
import YGOPersistence

/// A catalog with printings to record copies against.
enum CollectionFixture {
    struct Rig {
        let database: DatabaseQueue
        let collection: SQLiteCollectionRepository
        let decks: SQLiteDeckRepository
        let cards: [CatalogCardPayload]
    }

    static func seeded() throws -> Rig {
        let database = try SyncFixture.migratedDatabase()
        let cards = try RealDeck.cards()
        try database.write { db in
            try CatalogWriter().writeEnglishDataset(
                cards, observedAt: SyncFixture.observedAt, into: db)
        }
        return Rig(
            database: database,
            collection: SQLiteCollectionRepository(database: database),
            decks: SQLiteDeckRepository(database: database, now: { SyncFixture.observedAt }),
            cards: cards)
    }

    /// The printings the catalog stored for a card, as identifiers.
    static func printings(of cardID: Int, in database: DatabaseQueue) throws -> [Int64] {
        try database.read { db in
            try Int64.fetchAll(db, sql:
                "SELECT id FROM card_print WHERE card_id = ? ORDER BY id",
                arguments: [cardID])
        }
    }

    /// A card the catalog holds at least `count` printings for, which the
    /// across-printings assertions need.
    static func cardWithPrintings(_ count: Int, in rig: Rig) throws -> (Int, [Int64]) {
        for card in rig.cards {
            let ids = try printings(of: card.id, in: rig.database)
            if ids.count >= count { return (card.id, ids) }
        }
        return (rig.cards[0].id, try printings(of: rig.cards[0].id, in: rig.database))
    }
}
