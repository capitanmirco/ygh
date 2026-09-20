import Foundation
import GRDB
import YGOCore

/// Reads cards out of the catalog database.
public struct SQLiteCardRepository: CardRepository {
    private let database: any DatabaseReader

    public init(database: any DatabaseReader) {
        self.database = database
    }

    public func card(with identifier: CardIdentifier) async throws -> Card? {
        try await database.read { db in
            try Self.loadCard(identifier.rawValue, from: db)
        }
    }

    public func card(withArtwork identifier: ArtworkIdentifier) async throws -> Card? {
        try await database.read { db in
            guard let cardID = try Int.fetchOne(db, sql:
                "SELECT card_id FROM card_artwork WHERE artwork_id = ?",
                arguments: [identifier.rawValue]) else { return nil }
            return try Self.loadCard(cardID, from: db)
        }
    }

    public func banStatus(
        for identifier: CardIdentifier,
        in format: CardFormat
    ) async throws -> BanStatus {
        try await database.read { db in
            let stored = try String.fetchOne(db, sql: """
                SELECT status FROM ban_status WHERE card_id = ? AND format_code = ?
                """, arguments: [identifier.rawValue, format.rawValue])
            // No row means unrestricted, which is why none is stored.
            return BanStatus(storedValue: stored)
        }
    }

    public func cardCount() async throws -> Int {
        try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM card") ?? 0
        }
    }

    // MARK: - Row mapping

    static func loadCard(_ id: Int, from db: Database) throws -> Card? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM card WHERE id = ?",
                                         arguments: [id]) else { return nil }
        return try assemble([row], from: db).first
    }

    /// Builds cards from already-fetched rows using three queries in total,
    /// rather than two extra queries per card. At a hundred results that is the
    /// difference between three statements and three hundred.
    static func assemble(_ rows: [Row], from db: Database) throws -> [Card] {
        guard !rows.isEmpty else { return [] }

        let ids = rows.map { $0["id"] as Int }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        let arguments = StatementArguments(ids)

        var artworksByCard: [Int: [ArtworkIdentifier]] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT card_id, artwork_id FROM card_artwork
            WHERE card_id IN (\(placeholders)) ORDER BY card_id, ordinal
            """, arguments: arguments) {
            artworksByCard[row["card_id"], default: []]
                .append(ArtworkIdentifier(row["artwork_id"]))
        }

        var formatsByCard: [Int: Set<CardFormat>] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT card_id, format_code FROM card_format WHERE card_id IN (\(placeholders))
            """, arguments: arguments) {
            guard let format = CardFormat(rawValue: row["format_code"]) else { continue }
            formatsByCard[row["card_id"], default: []].insert(format)
        }

        return rows.map { row in
            let id: Int = row["id"]
            return Card(
                id: CardIdentifier(id),
                englishName: row["name_en"],
                englishEffect: row["desc_en"],
                italianName: row["name_it"],
                italianEffect: row["desc_it"],
                frame: CardFrame(rawValue: row["frame_type"] ?? "") ?? .effect,
                humanReadableType: row["human_readable_type"],
                archetype: row["archetype"],
                monsterStats: monsterStats(from: row),
                artworks: artworksByCard[id] ?? [],
                formats: formatsByCard[id] ?? [])
        }
    }

    /// Two thirds of the pool carries no combat numbers, so their absence is
    /// reported as no stats at all rather than a struct full of nils.
    private static func monsterStats(from row: Row) -> MonsterStats? {
        let level: Int? = row["level"]
        let attack: Int? = row["atk"]
        let linkRating: Int? = row["link_value"]
        guard level != nil || attack != nil || linkRating != nil else { return nil }

        return MonsterStats(
            attribute: (row["attribute"] as String?).flatMap(CardAttribute.init(rawValue:)),
            race: row["race"] ?? "",
            level: level,
            attack: attack,
            defense: row["def"],
            linkRating: linkRating,
            pendulumScale: row["pendulum_scale"])
    }
}


// MARK: - Searching

extension SQLiteCardRepository: CardSearching {
    /// Resolves a search entirely against local storage. Nothing here reaches
    /// upstream, which is what lets the whole browsing surface work offline.
    public func search(_ query: CardQuery) async throws -> CardSearchOutcome {
        guard let statement = CardQueryBuilder(query: query).makeStatement() else {
            // The text held nothing matchable, such as punctuation alone. That
            // is a settled empty answer, not an error.
            return .noMatches
        }

        let cards = try await database.read { db -> [Card] in
            let rows = try Row.fetchAll(db, sql: statement.sql, arguments: statement.arguments)
            return try Self.assemble(rows, from: db)
        }
        return CardSearchOutcome(cards)
    }
}
