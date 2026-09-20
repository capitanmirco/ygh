import Foundation
import GRDB
import YGOCore

/// One owned card as the collection list shows it.
public struct OwnedCard: Hashable, Sendable, Identifiable {
    public let card: CardIdentifier
    public let name: String
    public let copies: Int

    public var id: CardIdentifier { card }
}

/// Where a card's copies physically are.
public struct CardWhereabouts: Hashable, Sendable {
    public let locationID: Int64?
    public let locationName: String?
    public let copies: Int

    public var isUnfiled: Bool { locationID == nil }
}

/// What a collection list is narrowed by.
public struct CollectionFilters: Hashable, Sendable {
    public var rarities: Set<String> = []
    public var setCodes: Set<String> = []
    public var conditions: Set<CardCondition> = []
    public var locationID: Int64??

    public init() {}

    public var isEmpty: Bool {
        rarities.isEmpty && setCodes.isEmpty && conditions.isEmpty && locationID == nil
    }
}

/// What a narrowed collection list came back with.
///
/// An empty collection and a filter that excludes everything are different
/// answers, and the interface must not have to infer which it is from a count.
public enum CollectionListing: Hashable, Sendable {
    case entries([CollectionEntry])
    /// Nothing matched, but the collection does hold something.
    case noMatches
    /// Nothing is recorded at all.
    case empty

    public var entries: [CollectionEntry] {
        if case .entries(let entries) = self { return entries }
        return []
    }
}

extension SQLiteCollectionRepository {
    // MARK: - Locations

    @discardableResult
    public func createLocation(named name: String, notes: String? = nil) async throws -> Int64 {
        try await writer.write { db in
            try db.execute(sql: "INSERT INTO storage_location (name, notes) VALUES (?, ?)",
                           arguments: [name, notes])
            return db.lastInsertedRowID
        }
    }

    public func locations() async throws -> [StorageLocation] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM storage_location ORDER BY name COLLATE NOCASE")
                .map { StorageLocation(id: $0["id"], name: $0["name"], notes: $0["notes"]) }
        }
    }

    public func assign(entry id: Int64, toLocation locationID: Int64?) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE collection_entry SET location_id = ? WHERE id = ?",
                           arguments: [locationID, id])
        }
    }

    /// Removes a location. Its copies survive and become unfiled, which the
    /// schema guarantees rather than this code remembering to.
    public func deleteLocation(_ id: Int64) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM storage_location WHERE id = ?", arguments: [id])
        }
    }

    public func entries(inLocation locationID: Int64?) async throws -> [CollectionEntry] {
        try await writer.read { db in
            let sql = locationID == nil
                ? "SELECT * FROM collection_entry WHERE location_id IS NULL ORDER BY id"
                : "SELECT * FROM collection_entry WHERE location_id = ? ORDER BY id"
            let arguments: StatementArguments = locationID.map { [$0] } ?? []
            return try Row.fetchAll(db, sql: sql, arguments: arguments).map(Self.entry)
        }
    }

    /// Each place a card's copies are kept, and how many are there.
    public func whereabouts(of cardID: CardIdentifier) async throws -> [CardWhereabouts] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT collection_entry.location_id AS location_id,
                       storage_location.name AS location_name,
                       sum(collection_entry.quantity) AS copies
                FROM collection_entry
                LEFT JOIN storage_location ON storage_location.id = collection_entry.location_id
                WHERE collection_entry.card_id = ?
                GROUP BY collection_entry.location_id
                ORDER BY location_name IS NULL, location_name COLLATE NOCASE
                """, arguments: [cardID.rawValue]).map { row in
                CardWhereabouts(
                    locationID: row["location_id"],
                    locationName: row["location_name"],
                    copies: row["copies"])
            }
        }
    }

    // MARK: - Browsing

    /// The owned cards whose name matches, which is a search of the collection
    /// rather than of the catalog: a card the user does not own must not appear.
    public func ownedCards(named query: String = "") async throws -> [OwnedCard] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await writer.read { db in
            var sql = """
                SELECT card.id AS id, card.name_en AS name,
                       sum(collection_entry.quantity) AS copies
                FROM collection_entry
                JOIN card ON card.id = collection_entry.card_id
                """
            var arguments = StatementArguments()
            if !trimmed.isEmpty {
                sql += " WHERE (card.name_en LIKE ? ESCAPE '\\' OR card.name_it LIKE ? ESCAPE '\\')"
                let pattern = "%\(Self.escapingWildcards(trimmed))%"
                arguments += [pattern, pattern]
            }
            sql += " GROUP BY card.id ORDER BY card.name_en COLLATE NOCASE"

            return try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
                OwnedCard(card: CardIdentifier(row["id"] as Int),
                          name: row["name"], copies: row["copies"])
            }
        }
    }

    /// A card named "100%" must not match everything.
    static func escapingWildcards(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    /// Narrows the collection. Rarity and set come from the printing the entry
    /// points at, never from a copy of them on the entry itself.
    public func listing(matching filters: CollectionFilters) async throws -> CollectionListing {
        let total = try await totals()
        guard !total.isEmpty else { return .empty }

        let entries = try await writer.read { db -> [CollectionEntry] in
            var conditions: [String] = []
            var arguments = StatementArguments()

            if !filters.rarities.isEmpty {
                let placeholders = Array(repeating: "?", count: filters.rarities.count)
                    .joined(separator: ", ")
                conditions.append("card_print.rarity IN (\(placeholders))")
                arguments += StatementArguments(Array(filters.rarities))
            }
            if !filters.setCodes.isEmpty {
                let placeholders = Array(repeating: "?", count: filters.setCodes.count)
                    .joined(separator: ", ")
                conditions.append("card_print.set_code IN (\(placeholders))")
                arguments += StatementArguments(Array(filters.setCodes))
            }
            if !filters.conditions.isEmpty {
                let placeholders = Array(repeating: "?", count: filters.conditions.count)
                    .joined(separator: ", ")
                conditions.append("collection_entry.condition IN (\(placeholders))")
                arguments += StatementArguments(filters.conditions.map(\.rawValue))
            }
            if let locationID = filters.locationID {
                if let locationID {
                    conditions.append("collection_entry.location_id = ?")
                    arguments += [locationID]
                } else {
                    conditions.append("collection_entry.location_id IS NULL")
                }
            }

            let sql = """
                SELECT collection_entry.* FROM collection_entry
                LEFT JOIN card_print ON card_print.id = collection_entry.print_id
                \(conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND "))
                ORDER BY collection_entry.id
                """
            return try Row.fetchAll(db, sql: sql, arguments: arguments).map(Self.entry)
        }

        return entries.isEmpty ? .noMatches : .entries(entries)
    }

    /// How many copies of each rarity the collection holds.
    ///
    /// Copies recorded against no printing have no rarity, and are reported
    /// under a nil key rather than dropped: the figures have to sum to the
    /// collection's total or they mislead.
    public func copiesByRarity() async throws -> [String?: Int] {
        try await writer.read { db in
            var result: [String?: Int] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT card_print.rarity AS rarity, sum(collection_entry.quantity) AS copies
                FROM collection_entry
                LEFT JOIN card_print ON card_print.id = collection_entry.print_id
                GROUP BY card_print.rarity
                """) {
                result[row["rarity"] as String?] = row["copies"]
            }
            return result
        }
    }
}

/// The collection view reads through this rather than through SQLite directly.
extension SQLiteCollectionRepository: CollectionReading {
    public func ownedCardItems(matching query: String) async throws -> [OwnedCardItem] {
        try await ownedCards(named: query).map {
            OwnedCardItem(id: $0.card, name: $0.name, copies: $0.copies)
        }
    }

    public func collectionTotals() async throws -> CollectionTotals {
        try await totals()
    }

    public func ownedCopiesByCard() async throws -> [CardIdentifier: Int] {
        try await copiesByCard()
    }
}

extension SQLiteCollectionRepository {
    /// The collection as the valuation needs it, with each lot's rarity and
    /// binder resolved.
    ///
    /// Built here rather than in the view because rarity lives on the printing
    /// and the binder on the location: assembling it upstream would mean two
    /// more round trips and a place for the two to disagree.
    public func valuationRows() async throws
        -> [(card: CardIdentifier, quantity: Int, rarity: String?, location: String?)] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT collection_entry.card_id AS card_id,
                       collection_entry.quantity AS quantity,
                       card_print.rarity AS rarity,
                       storage_location.name AS location
                FROM collection_entry
                LEFT JOIN card_print ON card_print.id = collection_entry.print_id
                LEFT JOIN storage_location ON storage_location.id = collection_entry.location_id
                ORDER BY collection_entry.id
                """).map { row in
                (card: CardIdentifier(row["card_id"] as Int),
                 quantity: row["quantity"] as Int,
                 rarity: row["rarity"] as String?,
                 location: row["location"] as String?)
            }
        }
    }

    /// Card names for a set of cards, for whichever screen needs to label them.
    public func cardNames(for cards: Set<CardIdentifier>) async throws
        -> [CardIdentifier: String] {
        guard !cards.isEmpty else { return [:] }
        return try await writer.read { db in
            let placeholders = Array(repeating: "?", count: cards.count).joined(separator: ", ")
            var result: [CardIdentifier: String] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT id, name_it, name_en FROM card WHERE id IN (\(placeholders))
                """, arguments: StatementArguments(cards.map(\.rawValue))) {
                let id = CardIdentifier(row["id"] as Int)
                result[id] = (row["name_it"] as String?) ?? (row["name_en"] as String? ?? "")
            }
            return result
        }
    }
}
