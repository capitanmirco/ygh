import Foundation
import GRDB
import Testing
import YGOCore
@testable import YGOPersistence

@Suite("Catalog status")
struct CatalogStatusTests {
    /// A database holding the shape of the user's own installation: a
    /// `sync_state` row and a handful of cards to count.
    private func seeded(
        version: String = "147.04",
        upstream: String? = "2026-09-16 00:05:12",
        synced: String? = "2026-09-20T10:49:19Z",
        cards: Int = 3
    ) throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)
        try queue.write { db in
            for id in stride(from: 1, through: cards, by: 1) {
                try db.execute(sql: """
                    INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                      human_readable_type)
                    VALUES (?, ?, 'effect text', 'Spell Card', 'spell', 'Spell Card')
                    """, arguments: [id, "Card \(id)"])
            }
            try db.execute(sql: """
                INSERT INTO sync_state (id, catalog_version, upstream_updated_at, last_sync_at)
                VALUES (1, ?, ?, ?)
                """, arguments: [version, upstream, synced])
        }
        return queue
    }

    /// Evidence for R2.AC1: the version and upstream's own date, both stored
    /// since the first synchronisation and never shown.
    @Test func theStatusCarriesTheStoredVersionAndUpstreamDate() async throws {
        let store = SQLiteCatalogStore(database: try seeded())
        let status = try #require(try await store.catalogStatus())

        #expect(status.version == "147.04")

        let upstream = try #require(status.upstreamUpdatedAt)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let parts = calendar.dateComponents([.year, .month, .day], from: upstream)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 16)
    }

    /// Evidence for R2.AC2: the local timestamp, written in a different shape
    /// from upstream's, read by the same panel.
    @Test func theStatusCarriesWhenTheCatalogWasLastStored() async throws {
        let store = SQLiteCatalogStore(database: try seeded())
        let status = try #require(try await store.catalogStatus())

        let synced = try #require(status.lastSyncAt)
        #expect(synced == Date(timeIntervalSinceReferenceDate: 811_594_159))

        // An unreadable date costs that field, not the whole reading.
        let odd = SQLiteCatalogStore(database: try seeded(upstream: "not a date", synced: nil))
        let oddStatus = try #require(try await odd.catalogStatus())
        #expect(oddStatus.upstreamUpdatedAt == nil)
        #expect(oddStatus.lastSyncAt == nil)
        #expect(oddStatus.version == "147.04")
    }

    /// Evidence for R2.AC3: the count comes from the same read as the version,
    /// so the panel cannot pair a version with a count from another moment.
    @Test func theStatusCarriesHowManyCardsAreStored() async throws {
        let store = SQLiteCatalogStore(database: try seeded(cards: 7))
        let status = try #require(try await store.catalogStatus())
        #expect(status.cardCount == 7)

        let empty = SQLiteCatalogStore(database: try seeded(cards: 0))
        let emptyStatus = try #require(try await empty.catalogStatus())
        #expect(emptyStatus.cardCount == 0)
    }

    /// Evidence for R2.AC1: a database that has never synchronised has no
    /// status to report, which is not a failure.
    @Test func aDatabaseThatHasNeverSynchronisedHasNoStatus() async throws {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)

        let status = try await SQLiteCatalogStore(database: queue).catalogStatus()
        #expect(status == nil)
    }
}
