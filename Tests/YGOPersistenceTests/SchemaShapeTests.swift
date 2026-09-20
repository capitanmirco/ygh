import Foundation
import GRDB
import Testing
@testable import YGOPersistence

@Suite("Schema shape")
struct SchemaShapeTests {
    private static let expectedTables: Set<String> = [
        "card", "card_artwork", "card_fts", "card_format", "ban_status",
        "card_print", "card_price", "artwork_cache", "sync_state",
    ]

    private static let expectedIndexes: Set<String> = [
        "card_frame_type_idx", "card_type_idx", "card_attribute_idx",
        "card_race_idx", "card_level_idx", "card_atk_idx", "card_def_idx",
        "card_link_value_idx", "card_pendulum_scale_idx", "card_archetype_idx",
        "card_artwork_card_id_idx", "card_format_code_idx",
        "ban_status_format_source_idx", "card_print_card_id_idx",
    ]

    private func migratedQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)
        return queue
    }

    @Test func createsEveryDeclaredTableAndIndex() throws {
        let queue = try migratedQueue()

        try queue.read { db in
            for table in Self.expectedTables {
                #expect(try db.tableExists(table), "tabella mancante: \(table)")
            }

            let indexNames = try String.fetchSet(db, sql: """
                SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%'
                """)
            #expect(Self.expectedIndexes.isSubset(of: indexNames))
        }
    }

    /// The full-text index is external-content, so writing a card must be
    /// enough to make it searchable; nothing writes to `card_fts` directly.
    @Test func fullTextIndexFollowsTheCardTable() throws {
        let queue = try migratedQueue()

        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO card (id, name_en, desc_en, name_it, desc_it,
                                  type, frame_type, human_readable_type, has_effect)
                VALUES (55144522, 'Pot of Greed', 'Draw 2 cards.',
                        'Anfora dell''Avidità', 'Pesca 2 carte.',
                        'Spell Card', 'spell', 'Normal Spell', 0)
                """)
        }

        try queue.read { db in
            let byEnglish = try Int.fetchOne(db, sql:
                "SELECT count(*) FROM card_fts WHERE card_fts MATCH ?", arguments: ["Greed"])
            #expect(byEnglish == 1)
        }
    }

    /// Guards the tokenizer configuration: without `remove_diacritics 2` an
    /// unaccented query misses accented Italian card names.
    @Test func tokenizerFoldsItalianDiacritics() throws {
        let queue = try migratedQueue()

        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO card (id, name_en, desc_en, name_it, desc_it,
                                  type, frame_type, human_readable_type, has_effect)
                VALUES (55144522, 'Pot of Greed', 'Draw 2 cards.',
                        'Anfora dell''Avidità', 'Pesca 2 carte.',
                        'Spell Card', 'spell', 'Normal Spell', 0)
                """)
        }

        try queue.read { db in
            let unaccented = try String.fetchAll(db, sql:
                "SELECT name_it FROM card_fts WHERE card_fts MATCH ?", arguments: ["avidita"])
            #expect(unaccented == ["Anfora dell'Avidità"])
        }
    }

    /// Restrictions cascade with their card, and the check constraints reject
    /// a status or source the rest of the code does not know how to read.
    @Test func rejectsUnknownBanStatusAndSource() throws {
        let queue = try migratedQueue()

        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                  human_readable_type, has_effect)
                VALUES (1, 'A', 'B', 'Spell Card', 'spell', 'Normal Spell', 0)
                """)
        }

        #expect(throws: DatabaseError.self) {
            try queue.write { db in
                try db.execute(sql: """
                    INSERT INTO ban_status (card_id, format_code, status, source)
                    VALUES (1, 'TCG', 'unlimited', 'upstream')
                    """)
            }
        }

        #expect(throws: DatabaseError.self) {
            try queue.write { db in
                try db.execute(sql: """
                    INSERT INTO ban_status (card_id, format_code, status, source)
                    VALUES (1, 'TCG', 'limited', 'guessed')
                    """)
            }
        }
    }
}
