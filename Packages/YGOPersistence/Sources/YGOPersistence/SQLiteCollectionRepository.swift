import Foundation
import GRDB
import YGOCore

public enum CollectionError: Error, Equatable {
    case printingNotInCatalog(Int64)
    case cardNotInCatalog(CardIdentifier)
    case entryNotFound(Int64)
    /// Copies are hand-entered and recoverable from nowhere, so removing them
    /// is never a side effect of something else.
    case removalNotConfirmed
}

/// Records what the user physically owns.
public struct SQLiteCollectionRepository: Sendable {
    private let database: any DatabaseWriter

    public init(database: any DatabaseWriter) {
        self.database = database
    }

    var writer: any DatabaseWriter { database }

    // MARK: - Recording

    /// Adds one copy, joining the lot that matches if there is an unpriced one.
    ///
    /// A lot with a recorded price is a purchase, not a bucket: adding to it
    /// would silently claim the new copy cost the same.
    public func addCopy(
        cardID: CardIdentifier,
        printID: Int64?,
        condition: CardCondition = .nearMint,
        locationID: Int64? = nil
    ) async throws {
        try await database.write { db in
            try Self.assertExists(cardID: cardID, printID: printID, in: db)

            if let existing = try Self.findUnpricedLot(
                cardID: cardID, printID: printID, condition: condition,
                locationID: locationID, in: db) {
                try db.execute(sql: "UPDATE collection_entry SET quantity = quantity + 1 WHERE id = ?",
                               arguments: [existing])
            } else {
                try db.execute(sql: """
                    INSERT INTO collection_entry (card_id, print_id, condition, quantity, location_id)
                    VALUES (?, ?, ?, 1, ?)
                    """, arguments: [cardID.rawValue, printID, condition.rawValue, locationID])
            }
        }
    }

    /// Records a purchase as its own lot, with what each copy cost.
    @discardableResult
    public func recordPurchase(
        cardID: CardIdentifier,
        printID: Int64?,
        condition: CardCondition,
        quantity: Int,
        pricePerCopy: Double?,
        acquiredAt: Date?,
        locationID: Int64? = nil,
        notes: String? = nil
    ) async throws -> Int64 {
        guard quantity > 0 else { throw CollectionError.entryNotFound(0) }
        return try await database.write { db in
            try Self.assertExists(cardID: cardID, printID: printID, in: db)
            try db.execute(sql: """
                INSERT INTO collection_entry
                    (card_id, print_id, condition, quantity, purchase_price,
                     acquired_at, location_id, notes)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    cardID.rawValue, printID, condition.rawValue, quantity,
                    pricePerCopy, acquiredAt.map(Self.text), locationID, notes,
                ])
            return db.lastInsertedRowID
        }
    }

    /// Removes one copy, dropping the lot once nothing is left of it.
    public func removeCopy(
        cardID: CardIdentifier,
        printID: Int64?,
        condition: CardCondition = .nearMint,
        locationID: Int64? = nil
    ) async throws {
        try await database.write { db in
            guard let lot = try Self.findLot(
                cardID: cardID, printID: printID, condition: condition,
                locationID: locationID, in: db) else { return }

            // The last copy is deleted rather than decremented to zero, which
            // the quantity check would refuse anyway.
            try db.execute(sql: "DELETE FROM collection_entry WHERE id = ? AND quantity <= 1",
                           arguments: [lot])
            try db.execute(sql: "UPDATE collection_entry SET quantity = quantity - 1 WHERE id = ?",
                           arguments: [lot])
        }
    }

    /// Sets a lot's count outright. Zero removes it.
    public func setQuantity(
        _ quantity: Int,
        cardID: CardIdentifier,
        printID: Int64?,
        condition: CardCondition = .nearMint,
        locationID: Int64? = nil
    ) async throws {
        try await database.write { db in
            try Self.assertExists(cardID: cardID, printID: printID, in: db)

            let lot = try Self.findLot(cardID: cardID, printID: printID,
                                       condition: condition, locationID: locationID, in: db)

            guard quantity > 0 else {
                if let lot {
                    try db.execute(sql: "DELETE FROM collection_entry WHERE id = ?",
                                   arguments: [lot])
                }
                return
            }

            if let lot {
                try db.execute(sql: "UPDATE collection_entry SET quantity = ? WHERE id = ?",
                               arguments: [quantity, lot])
            } else {
                try db.execute(sql: """
                    INSERT INTO collection_entry (card_id, print_id, condition, quantity, location_id)
                    VALUES (?, ?, ?, ?, ?)
                    """, arguments: [cardID.rawValue, printID, condition.rawValue,
                                     quantity, locationID])
            }
        }
    }

    public func deleteEntry(_ id: Int64, confirmed: Bool) async throws {
        guard confirmed else { throw CollectionError.removalNotConfirmed }
        try await database.write { db in
            try db.execute(sql: "DELETE FROM collection_entry WHERE id = ?", arguments: [id])
        }
    }

    /// Edits one lot. Only the fields given are touched, so changing a
    /// condition cannot silently clear a price.
    public func updateEntry(
        _ id: Int64,
        condition: CardCondition? = nil,
        quantity: Int? = nil,
        purchasePrice: Double? = nil,
        acquiredAt: Date? = nil,
        locationID: Int64?? = nil,
        notes: String? = nil
    ) async throws {
        try await database.write { db in
            var assignments: [String] = []
            var arguments = StatementArguments()

            if let condition {
                assignments.append("condition = ?")
                arguments += [condition.rawValue]
            }
            if let quantity, quantity > 0 {
                assignments.append("quantity = ?")
                arguments += [quantity]
            }
            if let purchasePrice {
                assignments.append("purchase_price = ?")
                arguments += [purchasePrice]
            }
            if let acquiredAt {
                assignments.append("acquired_at = ?")
                arguments += [Self.text(acquiredAt)]
            }
            // Double optional: the outer one says whether to touch the column,
            // the inner one says whether to clear it.
            if let locationID {
                assignments.append("location_id = ?")
                arguments += [locationID]
            }
            if let notes {
                assignments.append("notes = ?")
                arguments += [notes]
            }

            guard !assignments.isEmpty else { return }
            arguments += [id]
            try db.execute(
                sql: "UPDATE collection_entry SET \(assignments.joined(separator: ", ")) WHERE id = ?",
                arguments: arguments)
        }
    }

    // MARK: - Reading

    /// What the collection amounts to.
    ///
    /// The spend is a sum of what was recorded, not a valuation: lots with no
    /// price contribute nothing, and most collections are partly inherited.
    public func totals() async throws -> CollectionTotals {
        try await database.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT count(DISTINCT card_id) AS cards,
                       coalesce(sum(quantity), 0) AS copies,
                       coalesce(sum(quantity * purchase_price), 0) AS spend
                FROM collection_entry
                """)
            return CollectionTotals(
                distinctCards: row?["cards"] ?? 0,
                totalCopies: row?["copies"] ?? 0,
                recordedSpend: row?["spend"] ?? 0)
        }
    }


    public func entries() async throws -> [CollectionEntry] {
        try await database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM collection_entry ORDER BY id")
                .map(Self.entry)
        }
    }

    public func entries(forCard cardID: CardIdentifier) async throws -> [CollectionEntry] {
        try await database.read { db in
            try Row.fetchAll(db, sql:
                "SELECT * FROM collection_entry WHERE card_id = ? ORDER BY id",
                arguments: [cardID.rawValue]).map(Self.entry)
        }
    }

    /// Every copy of a card, across all of its printings and conditions.
    public func copiesHeld(ofCard cardID: CardIdentifier) async throws -> Int {
        try await database.read { db in
            try Int.fetchOne(db, sql:
                "SELECT coalesce(sum(quantity), 0) FROM collection_entry WHERE card_id = ?",
                arguments: [cardID.rawValue]) ?? 0
        }
    }

    public func copiesHeld(ofPrinting printID: Int64) async throws -> Int {
        try await database.read { db in
            try Int.fetchOne(db, sql:
                "SELECT coalesce(sum(quantity), 0) FROM collection_entry WHERE print_id = ?",
                arguments: [printID]) ?? 0
        }
    }

    /// Owned copies per card, which is what a shortfall is computed against.
    public func copiesByCard() async throws -> [CardIdentifier: Int] {
        try await database.read { db in
            var result: [CardIdentifier: Int] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT card_id, sum(quantity) AS held FROM collection_entry GROUP BY card_id
                """) {
                result[CardIdentifier(row["card_id"] as Int)] = row["held"]
            }
            return result
        }
    }

    // MARK: - Helpers

    private static func assertExists(
        cardID: CardIdentifier,
        printID: Int64?,
        in db: Database
    ) throws {
        let cardExists = try Bool.fetchOne(db, sql:
            "SELECT EXISTS(SELECT 1 FROM card WHERE id = ?)",
            arguments: [cardID.rawValue]) ?? false
        guard cardExists else { throw CollectionError.cardNotInCatalog(cardID) }

        guard let printID else { return }
        let printExists = try Bool.fetchOne(db, sql:
            "SELECT EXISTS(SELECT 1 FROM card_print WHERE id = ? AND card_id = ?)",
            arguments: [printID, cardID.rawValue]) ?? false
        guard printExists else { throw CollectionError.printingNotInCatalog(printID) }
    }

    /// Nulls compare as unequal in SQL, so `IS` is used rather than `=`.
    private static func findLot(
        cardID: CardIdentifier,
        printID: Int64?,
        condition: CardCondition,
        locationID: Int64?,
        in db: Database
    ) throws -> Int64? {
        try Int64.fetchOne(db, sql: """
            SELECT id FROM collection_entry
            WHERE card_id = ? AND print_id IS ? AND condition = ? AND location_id IS ?
            ORDER BY id LIMIT 1
            """, arguments: [cardID.rawValue, printID, condition.rawValue, locationID])
    }

    private static func findUnpricedLot(
        cardID: CardIdentifier,
        printID: Int64?,
        condition: CardCondition,
        locationID: Int64?,
        in db: Database
    ) throws -> Int64? {
        try Int64.fetchOne(db, sql: """
            SELECT id FROM collection_entry
            WHERE card_id = ? AND print_id IS ? AND condition = ? AND location_id IS ?
              AND purchase_price IS NULL
            ORDER BY id LIMIT 1
            """, arguments: [cardID.rawValue, printID, condition.rawValue, locationID])
    }

    static func entry(_ row: Row) -> CollectionEntry {
        CollectionEntry(
            id: row["id"],
            card: CardIdentifier(row["card_id"] as Int),
            printID: row["print_id"],
            condition: CardCondition(rawValue: row["condition"] ?? "") ?? .nearMint,
            quantity: row["quantity"],
            purchasePrice: row["purchase_price"],
            acquiredAt: (row["acquired_at"] as String?).flatMap {
                ISO8601DateFormatter().date(from: $0)
            },
            locationID: row["location_id"],
            notes: row["notes"])
    }

    static func text(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
