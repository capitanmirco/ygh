import Foundation
import GRDB
import YGOCore

/// Reads the prices `card-catalog` stored alongside the cards.
///
/// One query for a whole collection rather than one per card, which is what
/// keeps a ten-thousand-copy valuation arithmetic over rows already in memory.
public struct SQLitePriceRepository: PriceLookup {
    private let database: any DatabaseReader

    public init(database: any DatabaseReader) {
        self.database = database
    }

    public func prices(
        forCards cards: Set<CardIdentifier>
    ) async throws -> [CardIdentifier: [RecordedPrice]] {
        guard !cards.isEmpty else { return [:] }

        return try await database.read { db in
            let placeholders = Array(repeating: "?", count: cards.count).joined(separator: ", ")
            let rows = try Row.fetchAll(db, sql: """
                SELECT card_id, source, value, observed_at FROM card_price
                WHERE card_id IN (\(placeholders))
                """, arguments: StatementArguments(cards.map(\.rawValue)))

            var result: [CardIdentifier: [RecordedPrice]] = [:]
            let formatter = ISO8601DateFormatter()

            for row in rows {
                guard let source = PriceSource(rawValue: row["source"] ?? "") else { continue }
                let card = CardIdentifier(row["card_id"] as Int)
                result[card, default: []].append(RecordedPrice(
                    source: source,
                    money: Money(amount: row["value"], currency: source.currency),
                    observedAt: formatter.date(from: row["observed_at"] ?? "") ?? .distantPast))
            }
            return result
        }
    }
}
