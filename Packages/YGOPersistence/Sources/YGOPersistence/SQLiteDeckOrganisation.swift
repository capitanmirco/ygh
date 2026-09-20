import Foundation
import GRDB
import YGOCore

/// A saved state of a deck, recoverable later.
public struct DeckVersion: Hashable, Sendable, Identifiable {
    public let id: Int64
    public let deckID: Int64
    public let label: String?
    public let createdAt: Date
    public let slots: [DeckSlot]

    public init(id: Int64, deckID: Int64, label: String?, createdAt: Date, slots: [DeckSlot]) {
        self.id = id
        self.deckID = deckID
        self.label = label
        self.createdAt = createdAt
        self.slots = slots
    }
}

/// Folders, tags and version history.
extension SQLiteDeckRepository {
    // MARK: - Folders

    public func createFolder(named name: String, inside parent: Int64? = nil) async throws -> Int64 {
        try await writer.write { db in
            try db.execute(sql: "INSERT INTO folder (name, parent_id) VALUES (?, ?)",
                           arguments: [name, parent])
            return db.lastInsertedRowID
        }
    }

    public func move(_ deckID: Int64, toFolder folderID: Int64?) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE deck SET folder_id = ? WHERE id = ?",
                           arguments: [folderID, deckID])
        }
    }

    public func decks(inFolder folderID: Int64?) async throws -> [Deck] {
        try await writer.read { db in
            let sql = folderID == nil
                ? "SELECT id FROM deck WHERE folder_id IS NULL ORDER BY name COLLATE NOCASE"
                : "SELECT id FROM deck WHERE folder_id = ? ORDER BY name COLLATE NOCASE"
            let arguments: StatementArguments = folderID.map { [$0] } ?? []
            return try Int64.fetchAll(db, sql: sql, arguments: arguments)
                .compactMap { try Self.loadDeck($0, from: db) }
        }
    }

    /// Removes a folder. Its decks are released to the top level rather than
    /// deleted with it, which the schema's `ON DELETE SET NULL` guarantees.
    public func deleteFolder(_ folderID: Int64) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM folder WHERE id = ?", arguments: [folderID])
        }
    }

    // MARK: - Tags

    public func addTag(_ name: String, to deckID: Int64) async throws {
        try await writer.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO tag (name) VALUES (?)", arguments: [name])
            let tagID = try Int64.fetchOne(db, sql: "SELECT id FROM tag WHERE name = ?",
                                           arguments: [name])
            try db.execute(sql: "INSERT OR IGNORE INTO deck_tag (deck_id, tag_id) VALUES (?, ?)",
                           arguments: [deckID, tagID])
        }
    }

    public func decks(withTag name: String) async throws -> [Deck] {
        try await writer.read { db in
            try Int64.fetchAll(db, sql: """
                SELECT deck.id FROM deck
                JOIN deck_tag ON deck_tag.deck_id = deck.id
                JOIN tag ON tag.id = deck_tag.tag_id
                WHERE tag.name = ? ORDER BY deck.name COLLATE NOCASE
                """, arguments: [name])
                .compactMap { try Self.loadDeck($0, from: db) }
        }
    }

    // MARK: - Search

    public func decks(named query: String) async throws -> [Deck] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try await allDecks() }

        return try await writer.read { db in
            try Int64.fetchAll(db, sql: """
                SELECT id FROM deck WHERE name LIKE ? ESCAPE '\\' ORDER BY name COLLATE NOCASE
                """, arguments: ["%\(Self.escapingWildcards(trimmed))%"])
                .compactMap { try Self.loadDeck($0, from: db) }
        }
    }

    /// A deck named "100%" must not match every deck.
    static func escapingWildcards(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    // MARK: - Versions

    /// Stores the deck's slots as they stand.
    ///
    /// Kept as its own document rather than as copied rows, so a version saved
    /// today still reads correctly after `deck_slot` gains a column.
    @discardableResult
    public func saveVersion(of deckID: Int64, label: String?) async throws -> Int64 {
        let timestamp = ISO8601DateFormatter().string(from: clock())
        return try await writer.write { db in
            guard let deck = try Self.loadDeck(deckID, from: db) else {
                throw DeckRepositoryError.deckNotFound(deckID)
            }
            let snapshot = try Self.encodeSnapshot(deck.slots)
            try db.execute(sql: """
                INSERT INTO deck_version (deck_id, label, created_at, snapshot)
                VALUES (?, ?, ?, ?)
                """, arguments: [deckID, label, timestamp, snapshot])
            return db.lastInsertedRowID
        }
    }

    public func versions(of deckID: Int64) async throws -> [DeckVersion] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, deck_id, label, created_at, snapshot FROM deck_version
                WHERE deck_id = ? ORDER BY created_at, id
                """, arguments: [deckID]).map { row in
                DeckVersion(
                    id: row["id"],
                    deckID: row["deck_id"],
                    label: row["label"],
                    createdAt: ISO8601DateFormatter().date(from: row["created_at"] ?? "")
                        ?? .distantPast,
                    slots: (try? Self.decodeSnapshot(row["snapshot"])) ?? [])
            }
        }
    }

    /// Puts a deck back to a stored version.
    ///
    /// The state being replaced is saved first, so a restore is itself
    /// reversible: an experiment must never be a one-way door.
    public func restore(versionID: Int64) async throws {
        let timestamp = ISO8601DateFormatter().string(from: clock())
        try await writer.write { db in
            guard let row = try Row.fetchOne(db, sql:
                "SELECT deck_id, snapshot FROM deck_version WHERE id = ?",
                arguments: [versionID]) else { return }

            let deckID: Int64 = row["deck_id"]
            guard let current = try Self.loadDeck(deckID, from: db) else { return }

            try db.execute(sql: """
                INSERT INTO deck_version (deck_id, label, created_at, snapshot)
                VALUES (?, ?, ?, ?)
                """, arguments: [deckID, "Prima del ripristino", timestamp,
                                 try Self.encodeSnapshot(current.slots)])

            try db.execute(sql: "DELETE FROM deck_slot WHERE deck_id = ?", arguments: [deckID])
            for slot in try Self.decodeSnapshot(row["snapshot"]) {
                try db.execute(sql: """
                    INSERT INTO deck_slot (deck_id, section, artwork_id, card_id, quantity)
                    VALUES (?, ?, ?, ?, ?)
                    """, arguments: [deckID, slot.section.rawValue, slot.artwork.rawValue,
                                     slot.card.rawValue, slot.quantity])
            }
            try db.execute(sql: "UPDATE deck SET updated_at = ? WHERE id = ?",
                           arguments: [timestamp, deckID])
        }
    }

    // MARK: - Snapshots

    private struct StoredSlot: Codable {
        let section: String
        let artwork: Int
        let card: Int
        let quantity: Int
    }

    static func encodeSnapshot(_ slots: [DeckSlot]) throws -> String {
        let stored = slots.map {
            StoredSlot(section: $0.section.rawValue, artwork: $0.artwork.rawValue,
                       card: $0.card.rawValue, quantity: $0.quantity)
        }
        return String(decoding: try JSONEncoder().encode(stored), as: UTF8.self)
    }

    static func decodeSnapshot(_ text: String?) throws -> [DeckSlot] {
        guard let text, let data = text.data(using: .utf8) else { return [] }
        return try JSONDecoder().decode([StoredSlot].self, from: data).compactMap { stored in
            guard let section = DeckSection(rawValue: stored.section) else { return nil }
            return DeckSlot(artwork: ArtworkIdentifier(stored.artwork),
                            card: CardIdentifier(stored.card),
                            section: section, quantity: stored.quantity)
        }
    }
}
