import Foundation
import GRDB
import Testing
@testable import YGOPersistence

@Suite("Banlist schema")
struct BanlistSchemaTests {
    private func migratedQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)
        return queue
    }

    private func insertRevision(
        _ db: Database, format: String, date: String,
        source: String = "yaml-yugi-limit-regulation"
    ) throws -> Int64 {
        try db.execute(sql: """
            INSERT INTO banlist_revision
                (format_code, effective_date, source, fetched_at)
            VALUES (?, ?, ?, ?)
            """, arguments: [format, date, source, "2026-09-21T09:00:00Z"])
        return db.lastInsertedRowID
    }

    /// The history arrives as its own migration and leaves the catalog's
    /// current view alone: `ban_status` is `card-catalog`'s certified contract,
    /// and R4.AC3 reports disagreement instead of reconciling it.
    @Test func migratesToVersionFiveWithoutTouchingBanStatus() throws {
        let queue = try migratedQueue()
        let migrator = CatalogSchema.migrator

        #expect(CatalogSchema.migrationIdentifiers.last == "v005_banlist_history")
        let applied = try queue.read { try migrator.appliedIdentifiers($0) }
        #expect(applied.contains("v005_banlist_history"))

        try queue.read { db in
            #expect(try db.tableExists("banlist_revision"))
            #expect(try db.tableExists("banlist_entry"))

            // Untouched, and still the four columns card-catalog wrote.
            #expect(try db.tableExists("ban_status"))
            let banStatusColumns = try db.columns(in: "ban_status").map(\.name)
            #expect(banStatusColumns.contains("card_id"))
            #expect(banStatusColumns.contains("format_code"))

            let indexes = try String.fetchSet(db, sql: """
                SELECT name FROM sqlite_master WHERE type = 'index'
                """)
            #expect(indexes.contains("banlist_entry_konami_idx"))
            #expect(indexes.contains("banlist_revision_format_idx"))
        }
    }

    /// Evidence for R1.AC2: a stored list knows when it took effect and which
    /// format it belongs to, and says where it came from and when it was read.
    @Test func aStoredRevisionCarriesItsDateAndFormat() throws {
        let queue = try migratedQueue()

        let row = try queue.write { db -> Row in
            _ = try insertRevision(db, format: "tcg", date: "2005-03-01")
            return try Row.fetchOne(db, sql: """
                SELECT format_code, effective_date, source, fetched_at
                FROM banlist_revision
                """)!
        }

        #expect(row["format_code"] == "tcg")
        #expect(row["effective_date"] == "2005-03-01")
        #expect(row["source"] == "yaml-yugi-limit-regulation")
        #expect(row["fetched_at"] == "2026-09-21T09:00:00Z")
    }

    /// Evidence for R1.AC2: two formats publishing on the same day are two
    /// lists, not one. The TCG and the OCG have both dated lists 2005-03-01.
    @Test func twoFormatsShareADateAndStayDistinct() throws {
        let queue = try migratedQueue()

        let (tcg, ocg) = try queue.write { db in
            (try insertRevision(db, format: "tcg", date: "2005-03-01"),
             try insertRevision(db, format: "ocg", date: "2005-03-01"))
        }
        #expect(tcg != ocg)

        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO banlist_entry (revision_id, konami_id, status)
                VALUES (?, 4007, 'forbidden'), (?, 4007, 'limited')
                """, arguments: [tcg, ocg])
        }

        let statuses = try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT r.format_code, e.status
                FROM banlist_entry e
                JOIN banlist_revision r ON r.id = e.revision_id
                WHERE e.konami_id = 4007
                ORDER BY r.format_code
                """)
        }
        #expect(statuses.count == 2)
        #expect(statuses[0]["format_code"] == "ocg")
        #expect(statuses[0]["status"] == "limited")
        #expect(statuses[1]["format_code"] == "tcg")
        #expect(statuses[1]["status"] == "forbidden")
    }

    /// Evidence for R1.AC4: the stored dates are the cursor. A list already
    /// held cannot be stored twice, so a second synchronisation has nothing to
    /// fetch rather than fetching and discarding.
    @Test func refusesASecondRevisionForTheSameFormatAndDate() throws {
        let queue = try migratedQueue()
        let first = try queue.write { try insertRevision($0, format: "tcg", date: "2005-03-01") }

        #expect(throws: DatabaseError.self) {
            try queue.write { try insertRevision($0, format: "tcg", date: "2005-03-01") }
        }

        // The same card cannot hold two statuses on one list either.
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO banlist_entry (revision_id, konami_id, status)
                VALUES (?, 4007, 'forbidden')
                """, arguments: [first])
        }
        #expect(throws: DatabaseError.self) {
            try queue.write { db in
                try db.execute(sql: """
                    INSERT INTO banlist_entry (revision_id, konami_id, status)
                    VALUES (?, 4007, 'limited')
                    """, arguments: [first])
            }
        }

        // And no fourth status can be written, because none is published.
        #expect(throws: DatabaseError.self) {
            try queue.write { db in
                try db.execute(sql: """
                    INSERT INTO banlist_entry (revision_id, konami_id, status)
                    VALUES (?, 9999, 'unlimited')
                    """, arguments: [first])
            }
        }

        // Dropping a list takes its entries with it.
        try queue.write { db in
            try db.execute(sql: "DELETE FROM banlist_revision WHERE id = ?", arguments: [first])
        }
        #expect(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM banlist_entry") } == 0)
    }
}
