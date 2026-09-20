import Foundation
import GRDB
import YGOCore

/// Why a backup file could not be read.
public enum CollectionBackupError: Error, Equatable {
    case unreadableText
    case missingHeader
    case malformedRow(line: Int)
}

/// What an import restored, and what it could not.
public struct CollectionImportResult: Sendable {
    public let restored: Int
    /// Rows naming a printing the catalog no longer holds. The rest of the
    /// file is imported anyway: losing a whole collection because one set was
    /// renamed upstream is not a service.
    public let unresolved: [String]

    public var isComplete: Bool { unresolved.isEmpty }
}

/// Reads and writes the collection as CSV.
///
/// CSV, not the application's own format, because a backup nobody can open is
/// a backup nobody checks. The collection is hand-entered and exists nowhere
/// else, so being able to see it in a spreadsheet is the property that matters.
public enum CollectionBackup {
    static let header = [
        "card_id", "card_name", "set_code", "rarity", "condition",
        "quantity", "price_per_copy", "acquired_at", "location", "notes",
    ]

    // MARK: - Writing

    public static func csv(rows: [BackupRow]) -> String {
        ([header.joined(separator: ",")] + rows.map(line)).joined(separator: "\n") + "\n"
    }

    private static func line(_ row: BackupRow) -> String {
        [
            String(row.cardID),
            row.cardName,
            row.setCode ?? "",
            row.rarity ?? "",
            row.condition.rawValue,
            String(row.quantity),
            row.pricePerCopy.map { String(format: "%.2f", $0) } ?? "",
            row.acquiredAt ?? "",
            row.location ?? "",
            row.notes ?? "",
        ].map(escape).joined(separator: ",")
    }

    /// Card names hold commas and apostrophes, and set names hold quotation
    /// marks. A backup that mangles them is not a backup.
    static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Reading

    /// Parses a whole file before anything is written, so a corrupt one cannot
    /// leave a half-restored collection behind.
    public static func parse(_ text: String) throws -> [BackupRow] {
        let lines = splitRows(text)
        guard let headerLine = lines.first else { throw CollectionBackupError.missingHeader }
        guard parseFields(headerLine) == header else {
            throw CollectionBackupError.missingHeader
        }

        return try lines.dropFirst().enumerated().compactMap { offset, line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let fields = parseFields(line)
            guard fields.count == header.count,
                  let cardID = Int(fields[0]),
                  let condition = CardCondition(rawValue: fields[4]),
                  let quantity = Int(fields[5]), quantity > 0 else {
                throw CollectionBackupError.malformedRow(line: offset + 2)
            }

            return BackupRow(
                cardID: cardID,
                cardName: fields[1],
                setCode: fields[2].isEmpty ? nil : fields[2],
                rarity: fields[3].isEmpty ? nil : fields[3],
                condition: condition,
                quantity: quantity,
                pricePerCopy: Double(fields[6]),
                acquiredAt: fields[7].isEmpty ? nil : fields[7],
                location: fields[8].isEmpty ? nil : fields[8],
                notes: fields[9].isEmpty ? nil : fields[9])
        }
    }

    /// Splits on newlines that are not inside a quoted field.
    private static func splitRows(_ text: String) -> [String] {
        var rows: [String] = []
        var current = ""
        var insideQuotes = false

        for character in text {
            if character == "\"" { insideQuotes.toggle() }
            if character == "\n", !insideQuotes {
                rows.append(current)
                current = ""
            } else if character != "\r" {
                current.append(character)
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    static func parseFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var insideQuotes = false
        var characters = Array(line)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if insideQuotes {
                if character == "\"" {
                    // A doubled quote inside a quoted field is one quote.
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        current.append("\"")
                        index += 1
                    } else {
                        insideQuotes = false
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                insideQuotes = true
            } else if character == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        fields.append(current)
        _ = characters
        return fields
    }
}

/// One line of a backup: what was recorded, in the form a person can read.
///
/// Printings are named by their set code rather than by the catalog's internal
/// identifier, so a backup survives the catalog being rebuilt from scratch.
public struct BackupRow: Hashable, Sendable {
    public let cardID: Int
    public let cardName: String
    public let setCode: String?
    public let rarity: String?
    public let condition: CardCondition
    public let quantity: Int
    public let pricePerCopy: Double?
    public let acquiredAt: String?
    public let location: String?
    public let notes: String?

    public init(
        cardID: Int, cardName: String, setCode: String?, rarity: String?,
        condition: CardCondition, quantity: Int, pricePerCopy: Double?,
        acquiredAt: String?, location: String?, notes: String?
    ) {
        self.cardID = cardID
        self.cardName = cardName
        self.setCode = setCode
        self.rarity = rarity
        self.condition = condition
        self.quantity = quantity
        self.pricePerCopy = pricePerCopy
        self.acquiredAt = acquiredAt
        self.location = location
        self.notes = notes
    }
}

extension SQLiteCollectionRepository {
    /// Every recorded lot, in the form the backup file carries.
    public func backupRows() async throws -> [BackupRow] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT collection_entry.card_id AS card_id,
                       card.name_en AS card_name,
                       card_print.set_code AS set_code,
                       card_print.rarity AS rarity,
                       collection_entry.condition AS condition,
                       collection_entry.quantity AS quantity,
                       collection_entry.purchase_price AS price,
                       collection_entry.acquired_at AS acquired_at,
                       storage_location.name AS location,
                       collection_entry.notes AS notes
                FROM collection_entry
                JOIN card ON card.id = collection_entry.card_id
                LEFT JOIN card_print ON card_print.id = collection_entry.print_id
                LEFT JOIN storage_location ON storage_location.id = collection_entry.location_id
                ORDER BY collection_entry.id
                """).map { row in
                BackupRow(
                    cardID: row["card_id"],
                    cardName: row["card_name"],
                    setCode: row["set_code"],
                    rarity: row["rarity"],
                    condition: CardCondition(rawValue: row["condition"] ?? "") ?? .nearMint,
                    quantity: row["quantity"],
                    pricePerCopy: row["price"],
                    acquiredAt: row["acquired_at"],
                    location: row["location"],
                    notes: row["notes"])
            }
        }
    }

    public func exportCSV() async throws -> String {
        CollectionBackup.csv(rows: try await backupRows())
    }

    /// Restores a backup.
    ///
    /// The file is parsed in full before the first write, so a corrupt one
    /// leaves the existing collection exactly as it was. A row naming a
    /// printing the catalog no longer holds is reported rather than failing the
    /// import: one renamed set must not cost a whole collection.
    @discardableResult
    public func importCSV(_ text: String, replacingExisting: Bool = false) async throws
        -> CollectionImportResult {
        let rows = try CollectionBackup.parse(text)

        return try await writer.write { db in
            if replacingExisting {
                try db.execute(sql: "DELETE FROM collection_entry")
            }

            var restored = 0
            var unresolved: [String] = []

            for row in rows {
                let cardExists = try Bool.fetchOne(db, sql:
                    "SELECT EXISTS(SELECT 1 FROM card WHERE id = ?)",
                    arguments: [row.cardID]) ?? false
                guard cardExists else {
                    unresolved.append("\(row.cardName) (carta \(row.cardID))")
                    continue
                }

                // Printings are matched by set code and rarity, not by the
                // catalog's internal identifier, so a backup survives the
                // catalog being rebuilt.
                var printID: Int64?
                if let setCode = row.setCode {
                    printID = try Int64.fetchOne(db, sql: """
                        SELECT id FROM card_print
                        WHERE card_id = ? AND set_code = ? AND rarity IS ?
                        ORDER BY id LIMIT 1
                        """, arguments: [row.cardID, setCode, row.rarity])
                    guard printID != nil else {
                        unresolved.append("\(row.cardName) — \(setCode)")
                        continue
                    }
                }

                var locationID: Int64?
                if let location = row.location {
                    locationID = try Int64.fetchOne(db, sql:
                        "SELECT id FROM storage_location WHERE name = ?", arguments: [location])
                    if locationID == nil {
                        try db.execute(sql: "INSERT INTO storage_location (name) VALUES (?)",
                                       arguments: [location])
                        locationID = db.lastInsertedRowID
                    }
                }

                try db.execute(sql: """
                    INSERT INTO collection_entry
                        (card_id, print_id, condition, quantity, purchase_price,
                         acquired_at, location_id, notes)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        row.cardID, printID, row.condition.rawValue, row.quantity,
                        row.pricePerCopy, row.acquiredAt, locationID, row.notes,
                    ])
                restored += 1
            }

            return CollectionImportResult(restored: restored, unresolved: unresolved)
        }
    }

    /// Empties the collection. Hand-entered data, so never a side effect.
    public func clearCollection(confirmed: Bool) async throws {
        guard confirmed else { throw CollectionError.removalNotConfirmed }
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM collection_entry")
        }
    }
}
