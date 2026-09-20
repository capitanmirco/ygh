import Foundation
import GRDB
import YGOCore

/// The catalog store backed by the SQLite database.
///
/// A whole snapshot lands in one transaction, so an interruption anywhere
/// leaves either the previous catalog or, on a first run, an empty one. There
/// is no observable in-between state.
public struct SQLiteCatalogStore: CatalogStore {
    private let database: any DatabaseWriter
    private let writer = CatalogWriter()

    public init(database: any DatabaseWriter) {
        self.database = database
    }

    public func cardCount() async throws -> Int {
        try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM card") ?? 0
        }
    }

    public func storedVersion() async throws -> CatalogVersion? {
        try await database.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT catalog_version, upstream_updated_at FROM sync_state WHERE id = 1
                """),
                let version: String = row["catalog_version"] else { return nil }
            return CatalogVersion(
                databaseVersion: version,
                lastUpdate: row["upstream_updated_at"] ?? "")
        }
    }

    public func apply(
        _ dataset: CatalogDataset,
        progress: @Sendable @escaping (CatalogSyncProgress) -> Void
    ) async throws {
        let writer = self.writer
        try await database.write { db in
            progress(.init(stage: .storing, completed: 0, total: dataset.english.count))

            try writer.writeEnglishDataset(
                dataset.english, observedAt: dataset.observedAt, into: db
            ) { completed, total in
                progress(.init(stage: .storing, completed: completed, total: total))
            }

            // Same transaction as the English write: the translation columns
            // are cleared by that upsert and refilled here, so no reader ever
            // sees a card stripped of its Italian text.
            try writer.mergeItalianDataset(dataset.italian, into: db)

            try Self.recordVersion(dataset.version, observedAt: dataset.observedAt, in: db)
        }
    }

    /// The version stamp is written inside the same transaction as the cards.
    /// Recording it separately would let a crash leave the catalog claiming a
    /// freshness it does not have.
    static func recordVersion(
        _ version: CatalogVersion,
        observedAt: Date,
        in db: Database
    ) throws {
        try db.execute(sql: """
            INSERT INTO sync_state (id, catalog_version, upstream_updated_at, last_sync_at)
            VALUES (1, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                catalog_version = excluded.catalog_version,
                upstream_updated_at = excluded.upstream_updated_at,
                last_sync_at = excluded.last_sync_at
            """, arguments: [
                version.databaseVersion,
                version.lastUpdate,
                ISO8601DateFormatter().string(from: observedAt),
            ])
    }
}
