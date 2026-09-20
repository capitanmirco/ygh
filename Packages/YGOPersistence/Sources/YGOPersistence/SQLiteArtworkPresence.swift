import Foundation
import GRDB
import YGOCore

/// Presence records for the artwork files held on disk.
public struct SQLiteArtworkPresence: ArtworkPresenceTracking {
    private let database: any DatabaseWriter

    public init(database: any DatabaseWriter) {
        self.database = database
    }

    public func isStored(
        _ identifier: ArtworkIdentifier,
        variant: ArtworkVariant
    ) async throws -> Bool {
        try await database.read { db in
            try Bool.fetchOne(db, sql: """
                SELECT EXISTS(
                    SELECT 1 FROM artwork_cache WHERE artwork_id = ? AND variant = ?)
                """, arguments: [identifier.rawValue, variant.rawValue]) ?? false
        }
    }

    public func recordStored(
        _ identifier: ArtworkIdentifier,
        variant: ArtworkVariant,
        byteSize: Int,
        at date: Date
    ) async throws {
        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO artwork_cache (artwork_id, variant, byte_size, stored_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(artwork_id, variant) DO UPDATE SET
                    byte_size = excluded.byte_size, stored_at = excluded.stored_at
                """, arguments: [
                    identifier.rawValue, variant.rawValue, byteSize,
                    ISO8601DateFormatter().string(from: date),
                ])
        }
    }

    public func forget(_ identifier: ArtworkIdentifier, variant: ArtworkVariant) async throws {
        try await database.write { db in
            try db.execute(sql:
                "DELETE FROM artwork_cache WHERE artwork_id = ? AND variant = ?",
                arguments: [identifier.rawValue, variant.rawValue])
        }
    }

    public func forgetAll() async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM artwork_cache")
        }
    }

    /// The resume query: every artwork the catalog knows about that this
    /// variant has no record for.
    public func missing(variant: ArtworkVariant, limit: Int?) async throws -> [ArtworkIdentifier] {
        try await database.read { db in
            var sql = """
                SELECT a.artwork_id FROM card_artwork a
                LEFT JOIN artwork_cache c
                    ON c.artwork_id = a.artwork_id AND c.variant = ?
                WHERE c.artwork_id IS NULL
                ORDER BY a.artwork_id
                """
            if let limit { sql += " LIMIT \(limit)" }
            return try Int.fetchAll(db, sql: sql, arguments: [variant.rawValue])
                .map { ArtworkIdentifier($0) }
        }
    }

    public func storedCount(variant: ArtworkVariant) async throws -> Int {
        try await database.read { db in
            try Int.fetchOne(db, sql:
                "SELECT count(*) FROM artwork_cache WHERE variant = ?",
                arguments: [variant.rawValue]) ?? 0
        }
    }

    public func totalArtworkCount() async throws -> Int {
        try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM card_artwork") ?? 0
        }
    }
}
