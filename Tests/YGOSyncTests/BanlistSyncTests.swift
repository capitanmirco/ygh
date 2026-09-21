import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOSync

/// Reads the recorded lists from disk. No test reaches a live host.
final class RecordedBanlistSource: BanlistFetching, @unchecked Sendable {
    static let directory: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "fixtures")
        .appending(path: "banlist")

    private let lock = NSLock()
    private var _bodyFetches = 0
    var bodyFetches: Int { lock.withLock { _bodyFetches } }

    var offline = false
    var substitute: [BanlistFormat: [String: PublishedBanlist]] = [:]

    func availableDates(for format: BanlistFormat) async throws -> [String] {
        if offline { throw URLError(.cannotConnectToHost) }
        if let dates = substitute[format]?.keys { return dates.sorted() }
        let files = try FileManager.default.contentsOfDirectory(
            at: Self.directory.appending(path: format.rawValue),
            includingPropertiesForKeys: nil)
        return files
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(".vector.json") }
            .map { String($0.dropLast(".vector.json".count)) }
            .sorted()
    }

    func fetchList(
        _ format: BanlistFormat, effectiveDate: String
    ) async throws -> PublishedBanlist {
        if offline { throw URLError(.cannotConnectToHost) }
        lock.withLock { _bodyFetches += 1 }
        if let list = substitute[format]?[effectiveDate] { return list }
        let data = try Data(contentsOf: Self.directory
            .appending(path: format.rawValue)
            .appending(path: "\(effectiveDate).vector.json"))
        return try JSONDecoder().decode(PublishedBanlist.self, from: data)
    }
}

@Suite("Banlist synchronisation")
struct BanlistSyncTests {
    /// Non-async on purpose: inside an async test, `queue.read` would resolve
    /// to GRDB's async overload and every call site would need an `await`.
    private func readSync<T>(
        _ queue: DatabaseQueue, _ body: (Database) throws -> T
    ) throws -> T {
        try queue.read(body)
    }

    private func migratedQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)
        return queue
    }

    private func insertCard(_ queue: DatabaseQueue, id: Int, konamiID: Int?, name: String) throws {
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                  human_readable_type, konami_id)
                VALUES (?, ?, '', 'Effect Monster', 'effect', 'Effect Monster', ?)
                """, arguments: [id, name, konamiID])
        }
    }

    private func synchronizer(
        _ queue: DatabaseQueue, source: RecordedBanlistSource
    ) -> BanlistHistorySynchronizer {
        BanlistHistorySynchronizer(
            client: source,
            store: SQLiteBanlistHistory(database: queue),
            source: "yaml-yugi-limit-regulation",
            now: { Date(timeIntervalSince1970: 1_758_441_600) })
    }

    /// Evidence for R1.AC1: every enumerated list is stored, for all four
    /// formats, with the entries the source published.
    @Test func storesEveryEnumeratedListForEachFormat() async throws {
        let queue = try migratedQueue()
        let report = await synchronizer(queue, source: RecordedBanlistSource()).synchronize()

        #expect(report.succeeded)
        #expect(report.stored[.tcg] == 73)
        #expect(report.stored[.ocg] == 23)
        #expect(report.stored[.masterDuel] == 66)
        #expect(report.stored[.rush] == 15)
        #expect(report.storedTotal == 177)

        let (revisions, entries, tcg) = try readSync(queue) { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM banlist_revision"),
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM banlist_entry"),
             try String.fetchAll(db, sql: """
                SELECT effective_date FROM banlist_revision
                WHERE format_code = 'tcg' ORDER BY effective_date
                """))
        }
        #expect(revisions == 177)
        #expect(entries == 28_648)
        #expect(tcg.first == "1999-08-01")
        #expect(tcg.last == "2026-05-18")
    }

    /// Evidence for R1.AC3, read back out of the database rather than out of
    /// the decoder: the March 2005 TCG list as published.
    @Test func storesTheMarch2005ListAsEighteenForbiddenFortyFourLimitedFifteenSemi() async throws {
        let queue = try migratedQueue()
        _ = await synchronizer(queue, source: RecordedBanlistSource())
            .synchronize(formats: [.tcg])

        let counts = try readSync(queue) { db in
            try Row.fetchAll(db, sql: """
                SELECT e.status, COUNT(*) AS n
                FROM banlist_entry e
                JOIN banlist_revision r ON r.id = e.revision_id
                WHERE r.format_code = 'tcg' AND r.effective_date = '2005-03-01'
                GROUP BY e.status ORDER BY e.status
                """)
        }
        let byStatus = Dictionary(uniqueKeysWithValues:
            counts.map { ($0["status"] as String, $0["n"] as Int) })

        #expect(byStatus["forbidden"] == 18)
        #expect(byStatus["limited"] == 44)
        #expect(byStatus["semi_limited"] == 15)
        #expect(byStatus.values.reduce(0, +) == 77)
        #expect(byStatus["unlimited"] == nil)

        // The revision knows where it came from and when it was read.
        let revision = try readSync(queue) { db in
            try Row.fetchOne(db, sql: """
                SELECT source, fetched_at FROM banlist_revision
                WHERE format_code = 'tcg' AND effective_date = '2005-03-01'
                """)!
        }
        #expect(revision["source"] == "yaml-yugi-limit-regulation")
        #expect((revision["fetched_at"] as String).hasPrefix("2025-09-21"))
    }

    /// Evidence for R1.AC4: the stored dates are the cursor, so a second run
    /// with nothing new published downloads nothing at all.
    @Test func aSecondSynchronisationFetchesNoBodyAndChangesNothing() async throws {
        let queue = try migratedQueue()
        let source = RecordedBanlistSource()
        let sync = synchronizer(queue, source: source)

        let first = await sync.synchronize(formats: [.tcg])
        #expect(first.stored[.tcg] == 73)
        #expect(source.bodyFetches == 73)

        let fingerprint = try readSync(queue) { db in
            try Row.fetchAll(db, sql: """
                SELECT r.effective_date, e.konami_id, e.status
                FROM banlist_entry e JOIN banlist_revision r ON r.id = e.revision_id
                ORDER BY r.effective_date, e.konami_id
                """).map { "\($0["effective_date"] as String)/\($0["konami_id"] as Int)/\($0["status"] as String)" }
        }

        let second = await sync.synchronize(formats: [.tcg])
        #expect(second.fetchedNothing)
        #expect(second.stored[.tcg] == 0)
        #expect(second.alreadyHeld[.tcg] == 73)
        #expect(source.bodyFetches == 73)

        let after = try readSync(queue) { db in
            try Row.fetchAll(db, sql: """
                SELECT r.effective_date, e.konami_id, e.status
                FROM banlist_entry e JOIN banlist_revision r ON r.id = e.revision_id
                ORDER BY r.effective_date, e.konami_id
                """).map { "\($0["effective_date"] as String)/\($0["konami_id"] as Int)/\($0["status"] as String)" }
        }
        #expect(after == fingerprint)
    }

    /// Evidence for R1.AC6: a list may name a card the catalog has not caught
    /// up with. Its other entries are stored and the shortfall is counted, so
    /// the unknown one becomes answerable later without re-fetching anything.
    @Test func storesTheOtherEntriesAndReportsOneUnmatched() async throws {
        let queue = try migratedQueue()
        try insertCard(queue, id: 1, konamiID: 4007, name: "Monster Reborn")
        try insertCard(queue, id: 2, konamiID: 5405, name: "Graceful Charity")
        // Holds no konami_id at all, like 203 of the catalog's cards.
        try insertCard(queue, id: 3, konamiID: nil, name: "Untracked Card")

        let source = RecordedBanlistSource()
        source.substitute = [.tcg: ["2026-01-01": PublishedBanlist(
            effectiveDate: "2026-01-01",
            statuses: [4007: .forbidden, 5405: .limited, 99_999: .semiLimited])]]

        let report = await synchronizer(queue, source: source).synchronize(formats: [.tcg])

        #expect(report.unmatchedKonamiIDs == 1)
        #expect(report.stored[.tcg] == 1)
        #expect(report.succeeded)

        let (allEntries, unknownEntry) = try readSync(queue) { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM banlist_entry"),
             try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM banlist_entry WHERE konami_id = 99999
                """))
        }
        // Stored anyway, all three of them.
        #expect(allEntries == 3)
        #expect(unknownEntry == 1)

        // The catalog catches up; the entry was waiting.
        try insertCard(queue, id: 4, konamiID: 99_999, name: "Newly Catalogued")
        let matched = try readSync(queue) { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM banlist_entry e
                JOIN card c ON c.konami_id = e.konami_id
                """)
        }
        #expect(matched == 3)
    }

    /// Evidence for R1.AC5: the source going away costs the next lists, never
    /// the ones already held, and the failure is reported per format.
    @Test func keepsStoredHistoryWhenTheSourceGoesAway() async throws {
        let queue = try migratedQueue()
        let source = RecordedBanlistSource()
        let sync = synchronizer(queue, source: source)

        _ = await sync.synchronize(formats: [.tcg])
        let before = try readSync(queue) { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM banlist_entry")
        }
        #expect(before == 11_072)

        source.offline = true
        let report = await sync.synchronize(formats: [.tcg, .ocg])

        #expect(!report.succeeded)
        #expect(report.failures[.tcg] != nil)
        #expect(report.failures[.ocg] != nil)
        #expect(report.storedTotal == 0)

        let after = try readSync(queue) { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM banlist_entry")
        }
        #expect(after == before)

        // And the catalog's own tables are untouched by any of it.
        let banStatusExists = try readSync(queue) { try $0.tableExists("ban_status") }
        let banStatusRows = try readSync(queue) {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM ban_status")
        }
        #expect(banStatusExists)
        #expect(banStatusRows == 0)
    }
}
