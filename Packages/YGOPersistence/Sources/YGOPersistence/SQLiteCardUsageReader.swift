import Foundation
import GRDB
import YGOCore

/// Answers "do I already have this, and what is it already in".
///
/// `CollectionWriting.entries(forCard:)` returns a location identifier and not
/// its name, so holdings are read here rather than reused: a panel that showed
/// "location 3" would be asking the reader to look it up themselves.
public struct SQLiteCardUsageReader: CardUsageReading {
    private let database: any DatabaseReader

    public init(database: any DatabaseReader) {
        self.database = database
    }

    public func holdings(forCard identifier: CardIdentifier) async throws -> [CardHolding] {
        try await database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT e.quantity, e.condition, l.name AS location
                FROM collection_entry e
                LEFT JOIN storage_location l ON l.id = e.location_id
                WHERE e.card_id = ?
                ORDER BY l.name IS NULL, l.name, e.condition
                """, arguments: [identifier.rawValue])
            .compactMap { row in
                guard let condition = CardCondition(rawValue: row["condition"]) else { return nil }
                return CardHolding(
                    quantity: row["quantity"],
                    condition: condition,
                    location: row["location"])
            }
        }
    }

    public func deckUses(forCard identifier: CardIdentifier) async throws -> [DeckUse] {
        try await database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT d.id AS deck_id, d.name AS deck_name,
                       s.section, s.quantity
                FROM deck_slot s
                JOIN deck d ON d.id = s.deck_id
                WHERE s.card_id = ?
                ORDER BY d.name, s.section
                """, arguments: [identifier.rawValue])
            .compactMap { row in
                guard let section = DeckSection(rawValue: row["section"]) else { return nil }
                return DeckUse(
                    deckID: row["deck_id"],
                    deckName: row["deck_name"],
                    section: section,
                    quantity: row["quantity"])
            }
        }
    }
}
