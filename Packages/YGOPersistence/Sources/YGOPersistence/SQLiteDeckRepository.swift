import Foundation
import GRDB
import YGOCore

public enum DeckRepositoryError: Error, Equatable {
    /// Decks are user-authored and irreplaceable, so removing one is never a
    /// side effect of anything.
    case deletionNotConfirmed
    case deckNotFound(Int64)
    case artworkNotInCatalog(ArtworkIdentifier)
}

/// Stores decks beside the catalog they draw from.
public struct SQLiteDeckRepository: DeckRepository, DeckBuilding {
    private let database: any DatabaseWriter
    private let now: @Sendable () -> Date

    /// Reachable from the organisation and version extensions, which live in
    /// their own file to keep this one about the deck itself.
    var writer: any DatabaseWriter { database }
    var clock: @Sendable () -> Date { now }

    public init(database: any DatabaseWriter, now: @escaping @Sendable () -> Date = Date.init) {
        self.database = database
        self.now = now
    }

    // MARK: - Reading

    public func deck(with id: Int64) async throws -> Deck? {
        try await database.read { db in try Self.loadDeck(id, from: db) }
    }

    public func allDecks() async throws -> [Deck] {
        try await database.read { db in
            let ids = try Int64.fetchAll(db, sql: "SELECT id FROM deck ORDER BY name COLLATE NOCASE")
            return try ids.compactMap { try Self.loadDeck($0, from: db) }
        }
    }

    /// Builds the rules' view of a deck's own cards in one query.
    ///
    /// A deck holds at most ninety distinct cards, so this is small by
    /// construction; validation then needs no further lookups.
    public func cardIndex(for deck: Deck) async throws -> DeckCardIndex {
        let cardIDs = Set(deck.slots.map(\.card.rawValue))
        guard !cardIDs.isEmpty else { return DeckCardIndex(entries: []) }

        let format = deck.format.rawValue
        return try await database.read { db in
            let placeholders = Array(repeating: "?", count: cardIDs.count).joined(separator: ", ")
            var arguments = StatementArguments([format])
            arguments += StatementArguments(Array(cardIDs))

            // Ban status is read for this deck's format specifically: the same
            // card is Forbidden in one format and unrestricted in another.
            let rows = try Row.fetchAll(db, sql: """
                SELECT card.id, card.name_en, card.limit_name, card.frame_type,
                       card.type AS card_type, card.level, card.attribute, card.race,
                       ban_status.status AS ban
                FROM card
                LEFT JOIN ban_status
                    ON ban_status.card_id = card.id AND ban_status.format_code = ?
                WHERE card.id IN (\(placeholders))
                """, arguments: arguments)

            var formatsByCard: [Int: Set<CardFormat>] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT card_id, format_code FROM card_format
                WHERE card_id IN (\(placeholders))
                """, arguments: StatementArguments(Array(cardIDs))) {
                guard let value = CardFormat(rawValue: row["format_code"]) else { continue }
                formatsByCard[row["card_id"], default: []].insert(value)
            }

            return DeckCardIndex(entries: rows.map { row in
                let id: Int = row["id"]
                let name: String = row["name_en"]
                return DeckCardIndex.Entry(
                    card: CardIdentifier(id),
                    name: name,
                    // Backfilled for every row, but a deck must not silently
                    // count against nothing if one is ever missing.
                    limitName: row["limit_name"] ?? name,
                    frame: CardFrame(rawValue: row["frame_type"] ?? "") ?? .effect,
                    formats: formatsByCard[id] ?? [],
                    banStatus: BanStatus(storedValue: row["ban"]),
                    type: row["card_type"] ?? "",
                    level: row["level"],
                    attribute: (row["attribute"] as String?)
                        .flatMap(CardAttribute.init(rawValue:)),
                    race: row["race"] ?? "")
            })
        }
    }

    /// The card an artwork depicts, or `nil` when the catalog has no such
    /// printing. Alternate artworks resolve here, which is what makes a real
    /// deck file import complete.
    public func resolveArtwork(_ artwork: ArtworkIdentifier) async throws -> CardIdentifier? {
        try await database.read { db in
            // Two initialisers, so the closure is explicit.
            let cardID = try Int.fetchOne(
                db, sql: "SELECT card_id FROM card_artwork WHERE artwork_id = ?",
                arguments: [artwork.rawValue])
            return cardID.map { CardIdentifier($0) }
        }
    }

    // MARK: - Writing

    public func createDeck(name: String, format: CardFormat) async throws -> Deck {
        let timestamp = Self.text(now())
        return try await database.write { db in
            try db.execute(sql: """
                INSERT INTO deck (name, format_code, created_at, updated_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [name, format.rawValue, timestamp, timestamp])
            let id = db.lastInsertedRowID
            return try Self.loadDeck(id, from: db)!
        }
    }

    /// Adds one copy of a printing to a section.
    public func addCard(
        artwork: ArtworkIdentifier,
        section: DeckSection,
        to deckID: Int64
    ) async throws {
        let timestamp = Self.text(now())
        try await database.write { db in
            guard let cardID = try Int.fetchOne(db, sql:
                "SELECT card_id FROM card_artwork WHERE artwork_id = ?",
                arguments: [artwork.rawValue]) else {
                throw DeckRepositoryError.artworkNotInCatalog(artwork)
            }

            try db.execute(sql: """
                INSERT INTO deck_slot (deck_id, section, artwork_id, card_id, quantity)
                VALUES (?, ?, ?, ?, 1)
                ON CONFLICT(deck_id, section, artwork_id) DO UPDATE SET
                    quantity = quantity + 1
                """, arguments: [deckID, section.rawValue, artwork.rawValue, cardID])
            try Self.touch(deckID, at: timestamp, in: db)
        }
    }

    /// Removes one copy, dropping the entry once nothing is left of it.
    public func removeCard(
        artwork: ArtworkIdentifier,
        section: DeckSection,
        from deckID: Int64
    ) async throws {
        let timestamp = Self.text(now())
        try await database.write { db in
            // The last copy is deleted rather than decremented to zero: a slot
            // holding nothing is not a slot, and the schema's check refuses it
            // before any tidying afterwards could run.
            try db.execute(sql: """
                DELETE FROM deck_slot
                WHERE deck_id = ? AND section = ? AND artwork_id = ? AND quantity <= 1
                """, arguments: [deckID, section.rawValue, artwork.rawValue])

            try db.execute(sql: """
                UPDATE deck_slot SET quantity = quantity - 1
                WHERE deck_id = ? AND section = ? AND artwork_id = ?
                """, arguments: [deckID, section.rawValue, artwork.rawValue])

            try Self.touch(deckID, at: timestamp, in: db)
        }
    }

    public func rename(_ deckID: Int64, to name: String) async throws {
        try await update(deckID, sql: "UPDATE deck SET name = ? WHERE id = ?", first: name)
    }

    public func changeFormat(_ deckID: Int64, to format: CardFormat) async throws {
        try await update(deckID, sql: "UPDATE deck SET format_code = ? WHERE id = ?",
                         first: format.rawValue)
    }

    private func update(_ deckID: Int64, sql: String, first: String) async throws {
        let timestamp = Self.text(now())
        try await database.write { db in
            try db.execute(sql: sql, arguments: [first, deckID])
            try Self.touch(deckID, at: timestamp, in: db)
        }
    }

    /// Copies a deck, slots and all. The copy shares nothing with its original.
    public func duplicate(_ deckID: Int64, named name: String) async throws -> Deck {
        let timestamp = Self.text(now())
        return try await database.write { db in
            guard let source = try Self.loadDeck(deckID, from: db) else {
                throw DeckRepositoryError.deckNotFound(deckID)
            }

            try db.execute(sql: """
                INSERT INTO deck (name, format_code, folder_id, notes, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [name, source.format.rawValue, source.folderID,
                                 source.notes, timestamp, timestamp])
            let copyID = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO deck_slot (deck_id, section, artwork_id, card_id, quantity)
                SELECT ?, section, artwork_id, card_id, quantity FROM deck_slot WHERE deck_id = ?
                """, arguments: [copyID, deckID])

            return try Self.loadDeck(copyID, from: db)!
        }
    }

    /// Removes a deck and its versions. Refuses without an explicit
    /// confirmation, because nothing else in the application can replace one.
    public func delete(_ deckID: Int64, confirmed: Bool) async throws {
        guard confirmed else { throw DeckRepositoryError.deletionNotConfirmed }
        try await database.write { db in
            try db.execute(sql: "DELETE FROM deck WHERE id = ?", arguments: [deckID])
        }
    }

    // MARK: - Helpers

    private static func touch(_ deckID: Int64, at timestamp: String, in db: Database) throws {
        try db.execute(sql: "UPDATE deck SET updated_at = ? WHERE id = ?",
                       arguments: [timestamp, deckID])
    }

    private static func text(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(_ text: String?) -> Date {
        guard let text, let parsed = ISO8601DateFormatter().date(from: text) else { return .distantPast }
        return parsed
    }

    static func loadDeck(_ id: Int64, from db: Database) throws -> Deck? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM deck WHERE id = ?",
                                         arguments: [id]) else { return nil }

        let slots = try Row.fetchAll(db, sql: """
            SELECT section, artwork_id, card_id, quantity FROM deck_slot
            WHERE deck_id = ? ORDER BY section, artwork_id
            """, arguments: [id]).compactMap { slotRow -> DeckSlot? in
            guard let section = DeckSection(rawValue: slotRow["section"]) else { return nil }
            return DeckSlot(
                artwork: ArtworkIdentifier(slotRow["artwork_id"]),
                card: CardIdentifier(slotRow["card_id"]),
                section: section,
                quantity: slotRow["quantity"])
        }

        return Deck(
            id: row["id"],
            name: row["name"],
            format: CardFormat(rawValue: row["format_code"] ?? "") ?? .tcg,
            folderID: row["folder_id"],
            notes: row["notes"],
            slots: slots,
            createdAt: date(row["created_at"]),
            updatedAt: date(row["updated_at"]))
    }
}
