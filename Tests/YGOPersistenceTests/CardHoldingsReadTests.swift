import Foundation
import GRDB
import Testing
import YGOCore
@testable import YGOPersistence

@Suite("Card holdings and deck use")
struct CardHoldingsReadTests {
    /// The shape the live database has: two decks, one card in both, plus a
    /// collection seeded here because the real one holds nothing yet.
    /// Non-async on purpose: inside an async test, `queue.read`/`write` would
    /// resolve to GRDB's async overloads.
    private func writeSync(_ queue: DatabaseQueue, _ body: (Database) throws -> Void) throws {
        try queue.write(body)
    }

    private func readSync<T>(
        _ queue: DatabaseQueue, _ body: (Database) throws -> T
    ) throws -> T {
        try queue.read(body)
    }

    private func seeded() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)

        try queue.write { db in
            for (id, name) in [(70_368_879, "Upstart Goblin"),
                               (44_763_025, "Torrential Tribute"),
                               (5_318_639, "Unused Card")] {
                try db.execute(sql: """
                    INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                      human_readable_type)
                    VALUES (?, ?, 'text', 'Spell Card', 'spell', 'Spell Card')
                    """, arguments: [id, name])
                try db.execute(sql: """
                    INSERT INTO card_artwork (artwork_id, card_id, ordinal)
                    VALUES (?, ?, 0)
                    """, arguments: [id, id])
            }

            try db.execute(sql: """
                INSERT INTO storage_location (id, name) VALUES (1, 'Raccoglitore rosso'),
                                                              (2, 'Scatola Edison')
                """)
            try db.execute(sql: """
                INSERT INTO deck (id, name, format_code, created_at, updated_at)
                VALUES (1, 'Lockdown Burn', 'TCG', '2026-01-01', '2026-01-01'),
                       (2, 'LR-Chaos Turbo', 'GOAT', '2026-01-01', '2026-01-01')
                """)

            // Upstart Goblin: in both decks, and in the side deck of one.
            try db.execute(sql: """
                INSERT INTO deck_slot (deck_id, section, artwork_id, card_id, quantity)
                VALUES (1, 'main', 70368879, 70368879, 1),
                       (2, 'main', 70368879, 70368879, 3),
                       (2, 'side', 70368879, 70368879, 1),
                       (1, 'main', 44763025, 44763025, 2)
                """)

            // Three lots: two filed, one whose location was deleted.
            try db.execute(sql: """
                INSERT INTO collection_entry
                    (card_id, condition, quantity, location_id)
                VALUES (70368879, 'near_mint', 2, 1),
                       (70368879, 'lightly_played', 1, 2),
                       (70368879, 'damaged', 4, NULL)
                """)
        }
        return queue
    }

    /// Evidence for R4.AC1: a location name, not an identifier, and the count
    /// held in each. "Do I already have this" is answered by where it is.
    @Test func reportsCopiesInEachLocationWithItsName() async throws {
        let reader = SQLiteCardUsageReader(database: try seeded())

        let holdings = try await reader.holdings(forCard: CardIdentifier(70_368_879))

        #expect(holdings.count == 3)
        #expect(holdings.reduce(0) { $0 + $1.quantity } == 7)

        let named = holdings.filter { $0.location != nil }
        #expect(named.count == 2)
        #expect(Set(named.map(\.locationName))
                == ["Raccoglitore rosso", "Scatola Edison"])

        let red = try #require(holdings.first { $0.location == "Raccoglitore rosso" })
        #expect(red.quantity == 2)
        #expect(red.condition == .nearMint)

        // A card owned in no copy at all reports nothing held.
        #expect(try await reader.holdings(forCard: CardIdentifier(5_318_639)).isEmpty)
    }

    /// Evidence for R4.AC1: deleting a place does not delete the cards in it.
    /// The schema releases them with `ON DELETE SET NULL`, and the panel has
    /// to show them as unfiled rather than lose them.
    @Test func anUnfiledCopyIsReportedNotDropped() async throws {
        let queue = try seeded()
        let reader = SQLiteCardUsageReader(database: queue)

        let unfiled = try await reader.holdings(forCard: CardIdentifier(70_368_879))
            .filter { $0.location == nil }
        #expect(unfiled.count == 1)
        #expect(unfiled.first?.quantity == 4)
        #expect(unfiled.first?.locationName == "Non archiviata")

        // Delete a place that holds copies; they stay, unfiled.
        try writeSync(queue) { db in
            try db.execute(sql: "DELETE FROM storage_location WHERE id = 1")
        }

        let after = try await reader.holdings(forCard: CardIdentifier(70_368_879))
        #expect(after.count == 3)
        #expect(after.reduce(0) { $0 + $1.quantity } == 7)
        #expect(after.filter { $0.location == nil }.count == 2)

        // Unfiled lots sort last, so the named places read first.
        #expect(after.last?.location == nil)
    }

    /// Evidence for R4.AC2: the live collection holds zero entries, so this is
    /// the state the panel is actually in today. It has to say so.
    @Test func anEmptyCollectionReportsNoCopyHeld() async throws {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)
        try writeSync(queue) { db in
            try db.execute(sql: """
                INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                  human_readable_type)
                VALUES (1, 'Any Card', 'text', 'Spell Card', 'spell', 'Spell Card')
                """)
        }
        let reader = SQLiteCardUsageReader(database: queue)

        let holdings = try await reader.holdings(forCard: CardIdentifier(1))
        #expect(holdings.isEmpty)

        let entries = try readSync(queue) { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM collection_entry")
        }
        #expect(entries == 0)
    }

    /// Evidence for R4.AC3: Upstart Goblin is in both decks of the live
    /// database. Knowing that before pulling a card out of a binder is the
    /// point of the section.
    @Test func reportsBothDecksUsingTheCardWithTheirCounts() async throws {
        let reader = SQLiteCardUsageReader(database: try seeded())

        let uses = try await reader.deckUses(forCard: CardIdentifier(70_368_879))

        #expect(Set(uses.map(\.deckName)) == ["Lockdown Burn", "LR-Chaos Turbo"])
        #expect(uses.reduce(0) { $0 + $1.quantity } == 5)
        #expect(uses.map(\.deckName) == uses.map(\.deckName).sorted())

        let lockdown = try #require(uses.first { $0.deckName == "Lockdown Burn" })
        #expect(lockdown.quantity == 1)
        #expect(lockdown.deckID == 1)

        // A card in one deck reports one deck; a card in none reports none.
        let single = try await reader.deckUses(forCard: CardIdentifier(44_763_025))
        #expect(single.count == 1)
        #expect(single.first?.quantity == 2)
        #expect(try await reader.deckUses(forCard: CardIdentifier(5_318_639)).isEmpty)
    }

    /// Evidence for R4.AC4: three in the main deck and one in the side is not
    /// four somewhere. Summing them would hide which copy is where.
    @Test func mainAndSideAreReportedSeparately() async throws {
        let reader = SQLiteCardUsageReader(database: try seeded())

        let chaos = try await reader.deckUses(forCard: CardIdentifier(70_368_879))
            .filter { $0.deckName == "LR-Chaos Turbo" }

        #expect(chaos.count == 2)
        #expect(Set(chaos.map(\.section)) == [.main, .side])

        let main = try #require(chaos.first { $0.section == .main })
        let side = try #require(chaos.first { $0.section == .side })
        #expect(main.quantity == 3)
        #expect(side.quantity == 1)

        // Both rows name the same deck, so the panel can group them.
        #expect(Set(chaos.map(\.deckID)).count == 1)
    }
}
