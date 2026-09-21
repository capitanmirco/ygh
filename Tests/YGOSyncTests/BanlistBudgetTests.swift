import Foundation
import GRDB
import Testing
import YGOBanlistHistory
import YGOCore
import YGONetworking
import YGOPersistence
@testable import YGOSync

@Suite("Banlist budgets")
struct BanlistBudgetTests {
    private static let fixtures: URL = RecordedBanlistSource.directory

    private func published(_ format: BanlistFormat, _ date: String) throws -> PublishedBanlist {
        try JSONDecoder().decode(PublishedBanlist.self, from: Data(contentsOf: Self.fixtures
            .appending(path: format.rawValue)
            .appending(path: "\(date).vector.json")))
    }

    private func readSync<T>(
        _ queue: DatabaseQueue, _ body: (Database) throws -> T
    ) throws -> T {
        try queue.read(body)
    }

    private func writeSync(_ queue: DatabaseQueue, _ body: (Database) throws -> Void) throws {
        try queue.write(body)
    }

    private func loadedDatabase() async throws -> (DatabaseQueue, SQLiteBanlistHistory) {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)
        let history = SQLiteBanlistHistory(database: queue)
        let report = await BanlistHistorySynchronizer(
            client: RecordedBanlistSource(), store: history,
            source: "yaml-yugi-limit-regulation",
            now: { Date(timeIntervalSince1970: 1_758_441_600) }
        ).synchronize(formats: [.tcg])
        #expect(report.stored[.tcg] == 73)
        return (queue, history)
    }

    /// A card named on every list, so the measurement is the worst case rather
    /// than a convenient one.
    private func busiestKonamiID(_ queue: DatabaseQueue) throws -> Int {
        try readSync(queue) { db in
            try Int.fetchOne(db, sql: """
                SELECT konami_id FROM banlist_entry
                GROUP BY konami_id ORDER BY COUNT(*) DESC LIMIT 1
                """)!
        }
    }

    /// Evidence for NFR1: a detail panel shows the history on opening, so the
    /// whole of it has to be ready in 20 ms. A card's history is at most 73
    /// rows and an index on `konami_id` finds them.
    @Test func reportsAFullHistoryWithinTwentyMilliseconds() async throws {
        let (queue, history) = try await loadedDatabase()
        let konamiID = try busiestKonamiID(queue)
        let dates = try history.revisions(for: .tcg).map(\.effectiveDate)

        // Warm the statement cache first: the budget is for a panel opening in
        // a running application, not for the first query after a cold start.
        _ = try history.statuses(forKonamiID: konamiID, format: .tcg)

        var worst: Double = 0
        for _ in 0..<20 {
            let started = DispatchTime.now().uptimeNanoseconds
            let statuses = try history.statuses(forKonamiID: konamiID, format: .tcg)
            let timeline = BanlistTimelineBuilder.timeline(
                format: .tcg, revisionDates: dates,
                statuses: statuses, releaseDate: nil)
            _ = timeline.changes
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            worst = max(worst, elapsed)
            #expect(timeline.entries.count == 73)
        }

        #expect(worst < 20, "worst case \(worst) ms")
    }

    /// Evidence for NFR2, first direction: the banlist source going away is
    /// not the catalog's problem. The catalog's own rows and queries are
    /// untouched by a failed history synchronisation.
    @Test func theCatalogIsUnaffectedByAnUnreachableBanlistSource() async throws {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)
        try writeSync(queue) { db in
            try db.execute(sql: """
                INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                  human_readable_type, konami_id)
                VALUES (6983839, 'Tornado Dragon', 'Once per turn...',
                        'XYZ Monster', 'xyz', 'XYZ Monster', 12600)
                """)
            try db.execute(sql: """
                INSERT INTO ban_status (card_id, format_code, status, source)
                VALUES (6983839, 'TCG', 'limited', 'upstream')
                """)
        }

        let offline = RecordedBanlistSource()
        offline.offline = true
        let report = await BanlistHistorySynchronizer(
            client: offline, store: SQLiteBanlistHistory(database: queue),
            source: "yaml-yugi-limit-regulation"
        ).synchronize()

        #expect(!report.succeeded)
        #expect(report.failures.count == BanlistFormat.allCases.count)

        // The catalog still answers, through its own repository.
        let repository = SQLiteCardRepository(database: queue)
        let card = try await repository.card(with: CardIdentifier(rawValue: 6_983_839))
        #expect(card?.englishName == "Tornado Dragon")
        let cardCount = try await repository.cardCount()
        #expect(cardCount == 1)

        let status = try await repository.banStatus(
            for: CardIdentifier(rawValue: 6_983_839), in: .tcg)
        #expect(status == .limited)
    }

    /// Evidence for NFR2, second direction: a catalog that cannot be reached
    /// costs the history nothing, because the history was never fetched
    /// through it and is not stored in its tables.
    @Test func theHistoryIsUnaffectedByAnUnreachableCatalog() async throws {
        let (queue, history) = try await loadedDatabase()

        struct DeadCatalogTransport: CatalogTransport {
            func data(from url: URL) async throws -> Data {
                throw URLError(.notConnectedToInternet)
            }
        }
        let catalog = YGOProDeckCatalogClient(transport: DeadCatalogTransport())
        await #expect(throws: (any Error).self) { try await catalog.fetchVersion() }

        // Not one card in the catalog, and the history answers regardless.
        let cardRows = try readSync(queue) {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM card")
        }
        #expect(cardRows == 0)

        let revisions = try history.revisions(for: .tcg)
        #expect(revisions.count == 73)

        let list = try history.list(.tcg, effectiveDate: "2005-03-01")
        #expect(list.count == 77)
        // Unnamed, because the catalog is empty, but present and statused.
        #expect(list.allSatisfy { $0.name == nil })
        #expect(list.filter { $0.status == .forbidden }.count == 18)
    }

    /// Evidence for NFR3: every question in R2 and R3 is answered from stored
    /// rows. The source is unreachable for the whole of this test.
    @Test func answersEveryHistoryQuestionOffline() async throws {
        let (queue, history) = try await loadedDatabase()
        let source = RecordedBanlistSource()
        source.offline = true

        // Nothing may reach the source from here on.
        await #expect(throws: (any Error).self) {
            try await source.availableDates(for: .tcg)
        }

        // R3.AC2: the lists held, in order.
        let revisions = try history.revisions(for: .tcg)
        #expect(revisions.count == 73)
        #expect(revisions.map(\.effectiveDate) == revisions.map(\.effectiveDate).sorted())

        // R3.AC1: a whole list.
        let march2005 = try history.list(.tcg, effectiveDate: "2005-03-01")
        #expect(march2005.count == 77)

        // R3.AC3: the difference between two of them.
        let differences = try history.difference(
            .tcg, from: "2005-03-01", to: "2005-09-01")
        #expect(!differences.isEmpty)
        #expect(differences.allSatisfy { $0.before != $0.after })

        // R2.AC1, AC2, AC4: a card's history and its changes.
        let konamiID = try busiestKonamiID(queue)
        let statuses = try history.statuses(forKonamiID: konamiID, format: .tcg)
        let timeline = BanlistTimelineBuilder.timeline(
            format: .tcg, revisionDates: revisions.map(\.effectiveDate),
            statuses: statuses, releaseDate: nil)
        #expect(timeline.entries.count == 73)
        #expect(!timeline.wasNeverRestricted)

        // R2.AC5: a card no list ever named.
        let unnamedStatuses = try history.statuses(forKonamiID: -1, format: .tcg)
        let never = BanlistTimelineBuilder.timeline(
            format: .tcg, revisionDates: revisions.map(\.effectiveDate),
            statuses: unnamedStatuses, releaseDate: nil)
        #expect(never.wasNeverRestricted)
        #expect(never.changes.isEmpty)

        // R4: provenance, still without asking anybody.
        let provenance = try history.provenance(for: .tcg)
        #expect(provenance.revisionCount == 73)
    }
}
