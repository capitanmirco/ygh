import Foundation
import GRDB
import Testing
import YGOCore
import YGONetworking
@testable import YGOPersistence

/// Copies are counted against a card's limit name, not its printed name.
/// `Harpie Lady 1`, `2` and `3` share one limit between them, so a deck holding
/// two of each holds six copies of one card and is illegal. Storing that name
/// once keeps the rule out of the validator entirely.
@Suite("Card limit names")
struct CardLimitNameTests {
    private static let observedAt = Date(timeIntervalSince1970: 1_758_000_000)

    private func fixtureCards() throws -> [CatalogCardPayload] {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "fixtures/catalog-en.json")
        return try YGOProDeckCatalogClient.decodeDataset(Data(contentsOf: url))
    }

    private func seeded() throws -> (DatabaseQueue, [CatalogCardPayload]) {
        var configuration = GRDB.Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: configuration)
        try CatalogSchema.migrator.migrate(queue)
        let cards = try fixtureCards()
        try queue.write { db in
            try CatalogWriter().writeEnglishDataset(cards, observedAt: Self.observedAt, into: db)
        }
        return (queue, cards)
    }

    private func limitName(_ db: Database, _ id: Int) throws -> String? {
        try String.fetchOne(db, sql: "SELECT limit_name FROM card WHERE id = ?", arguments: [id])
    }

    /// Evidence for R3.AC3: a card upstream marks as being treated as another
    /// card is stored under that other name.
    @Test func storesTreatedAsNameWhenItDiffersFromTheCardName() throws {
        let (queue, cards) = try seeded()

        let shared = cards.filter { card in
            guard let treatedAs = card.misc?.treatedAs else { return false }
            return treatedAs != card.name
        }
        #expect(shared.count >= 4, "la fixture deve contenere casi di limite condiviso")

        try queue.read { db in
            for card in shared {
                let stored = try limitName(db, card.id)
                #expect(stored == card.misc?.treatedAs,
                        "\(card.name) doveva contare come \(card.misc?.treatedAs ?? "-"), trovato \(stored ?? "nil")")
                #expect(stored != card.name)
            }
        }

        // The three Harpie Lady printings must land on one name between them.
        let harpies = cards.filter { $0.name.hasPrefix("Harpie Lady ") }
        #expect(harpies.count >= 3)
        try queue.read { db in
            let names = try Set(harpies.compactMap { try limitName(db, $0.id) })
            #expect(names == ["Harpie Lady"], "le Harpie Lady devono condividere un solo limite, trovato \(names)")
        }
    }

    /// An ordinary card counts against itself, so the column is usable as the
    /// single grouping key with no fallback in the caller.
    @Test func storesTheCardsOwnNameWhenNoTreatedAsApplies() throws {
        let (queue, cards) = try seeded()

        let ordinary = cards.filter { $0.misc?.treatedAs == nil }
        #expect(!ordinary.isEmpty)

        try queue.read { db in
            for card in ordinary {
                let stored = try limitName(db, card.id)
                #expect(stored == card.name)
            }

            // Every card has one, so grouping never meets a null.
            let missing = try Int.fetchOne(db, sql:
                "SELECT count(*) FROM card WHERE limit_name IS NULL")
            #expect(missing == 0)
        }
    }

    /// The upstream value repeats the card's own name for most of the cards it
    /// marks, which must be stored as-is rather than treated as a special case.
    @Test func storesRepeatedTreatedAsValueAsTheCardsOwnName() throws {
        let (queue, cards) = try seeded()

        let selfReferential = cards.filter { $0.misc?.treatedAs == $0.name }
        #expect(!selfReferential.isEmpty)

        try queue.read { db in
            for card in selfReferential {
                let stored = try limitName(db, card.id)
                #expect(stored == card.name)
            }
        }
    }

    /// A catalog stored before this column existed is backfilled rather than
    /// left null, so an upgrade does not break copy counting until the next
    /// synchronisation.
    @Test func backfillsExistingRowsWhenTheColumnIsAdded() throws {
        var configuration = GRDB.Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: configuration)

        // Migrate only as far as the schema that predates limit names.
        let full = CatalogSchema.migrator
        try full.migrate(queue, upTo: "v001_initial_catalog")

        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                  human_readable_type, has_effect)
                VALUES (1, 'Pre-existing Card', 'Text.', 'Spell Card', 'spell',
                        'Normal Spell', 0)
                """)
        }

        try full.migrate(queue)

        try queue.read { db in
            let stored = try limitName(db, 1)
            #expect(stored == "Pre-existing Card")
        }
    }
}
