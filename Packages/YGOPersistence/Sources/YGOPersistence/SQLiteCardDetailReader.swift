import Foundation
import GRDB
import YGOCore

/// Reads the catalog columns a detail panel needs and the browser does not.
public struct SQLiteCardDetailReader: CardDetailReading {
    private let database: any DatabaseReader

    public init(database: any DatabaseReader) {
        self.database = database
    }

    public func printings(forCard identifier: CardIdentifier) async throws -> [CardPrinting] {
        try await database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT set_name, set_code, rarity, set_price
                FROM card_print WHERE card_id = ?
                ORDER BY set_name, set_code
                """, arguments: [identifier.rawValue])
            .map { row in
                CardPrinting(
                    setName: row["set_name"],
                    setCode: row["set_code"],
                    rarity: row["rarity"],
                    listedPrice: row["set_price"])
            }
        }
    }

    public func release(forCard identifier: CardIdentifier) async throws -> CardRelease {
        try await database.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT tcg_date, ocg_date FROM card WHERE id = ?
                """, arguments: [identifier.rawValue])
            else { return .unknown }
            return CardRelease(tcg: row["tcg_date"], ocg: row["ocg_date"])
        }
    }

    public func konamiID(forCard identifier: CardIdentifier) async throws -> Int? {
        try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT konami_id FROM card WHERE id = ?",
                             arguments: [identifier.rawValue])
        }
    }
}
