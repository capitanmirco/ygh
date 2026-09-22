import Foundation
import GRDB
import YGOCore

/// Stores and reads the published Forbidden & Limited Lists.
///
/// Entries are keyed by the `konami_id` the source published rather than
/// resolved to a card at write time. Resolving would make queries a plain join
/// and would also discard every entry for a card the catalog has not caught up
/// with; re-fetching would then be the only way to recover them.
public struct SQLiteBanlistHistory: BanlistHistoryWriting {
    private let database: any DatabaseWriter

    public init(database: any DatabaseWriter) {
        self.database = database
    }

    public func heldDates(for format: BanlistFormat) throws -> Set<String> {
        try database.read { db in
            try String.fetchSet(db, sql: """
                SELECT effective_date FROM banlist_revision WHERE format_code = ?
                """, arguments: [format.rawValue])
        }
    }

    @discardableResult
    public func store(
        _ list: PublishedBanlist, format: BanlistFormat,
        source: String, fetchedAt: Date
    ) throws -> Int {
        try database.write { db in
            // Re-storing a date replaces that revision's entries rather than
            // adding a second revision, which is what a corrected republication
            // of an existing list needs.
            try db.execute(sql: """
                DELETE FROM banlist_revision WHERE format_code = ? AND effective_date = ?
                """, arguments: [format.rawValue, list.effectiveDate])

            try db.execute(sql: """
                INSERT INTO banlist_revision
                    (format_code, effective_date, source, fetched_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [format.rawValue, list.effectiveDate, source,
                                 Self.timestamp(fetchedAt)])
            let revisionID = db.lastInsertedRowID

            for konamiID in list.statuses.keys.sorted() {
                try db.execute(sql: """
                    INSERT INTO banlist_entry (revision_id, konami_id, status)
                    VALUES (?, ?, ?)
                    """, arguments: [revisionID, konamiID,
                                     list.statuses[konamiID]!.storedValue])
            }

            return try Self.unmatchedCount(db, konamiIDs: Array(list.statuses.keys))
        }
    }

    /// How many of a list's identifiers the catalog cannot name. Reported at
    /// the moment of storing, which is a different and more useful statement
    /// than silently dropping them (`R1.AC6`).
    static func unmatchedCount(_ db: Database, konamiIDs: [Int]) throws -> Int {
        guard !konamiIDs.isEmpty else { return 0 }
        let placeholders = databaseQuestionMarks(count: konamiIDs.count)
        let matched = try Int.fetchOne(db, sql: """
            SELECT COUNT(DISTINCT konami_id) FROM card WHERE konami_id IN (\(placeholders))
            """, arguments: StatementArguments(konamiIDs)) ?? 0
        return Set(konamiIDs).count - matched
    }

    static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

extension SQLiteBanlistHistory: BanlistHistoryReading {
    public func revisions(for format: BanlistFormat) throws -> [BanlistRevision] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT r.effective_date, r.source, r.fetched_at,
                       COUNT(e.konami_id) AS entry_count
                FROM banlist_revision r
                LEFT JOIN banlist_entry e ON e.revision_id = r.id
                WHERE r.format_code = ?
                GROUP BY r.id
                ORDER BY r.effective_date
                """, arguments: [format.rawValue])
            .map { row in
                BanlistRevision(
                    format: format,
                    effectiveDate: row["effective_date"],
                    source: row["source"],
                    fetchedAt: row["fetched_at"],
                    entryCount: row["entry_count"])
            }
        }
    }

    public func list(
        _ format: BanlistFormat, effectiveDate: String
    ) throws -> [BanlistListEntry] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT e.konami_id, e.status, c.id AS card_id,
                       c.name_en, c.name_it, c.frame_type
                FROM banlist_entry e
                JOIN banlist_revision r ON r.id = e.revision_id
                LEFT JOIN card c ON c.konami_id = e.konami_id
                WHERE r.format_code = ? AND r.effective_date = ?
                ORDER BY e.status, c.name_en, e.konami_id
                """, arguments: [format.rawValue, effectiveDate])
            .compactMap { row in
                guard let status = BanlistStatus(storedValue: row["status"]) else { return nil }
                return BanlistListEntry(
                    konamiID: row["konami_id"],
                    cardID: row["card_id"],
                    name: row["name_en"],
                    italianName: row["name_it"],
                    status: status,
                    frame: (row["frame_type"] as String?).flatMap(CardFrame.init(rawValue:)))
            }
        }
    }

    public func difference(
        _ format: BanlistFormat, from earlier: String, to later: String
    ) throws -> [BanlistDifference] {
        let before = try statusesByKonamiID(format, effectiveDate: earlier)
        let after = try statusesByKonamiID(format, effectiveDate: later)
        let names = try self.names(forKonamiIDs: Set(before.keys).union(after.keys))

        // A card dropped from a list left no row, and that is still a change:
        // it went free. Taking the union is what catches it.
        return Set(before.keys).union(after.keys)
            .compactMap { konamiID -> BanlistDifference? in
                let from = before[konamiID]?.banStatus ?? .unlimited
                let to = after[konamiID]?.banStatus ?? .unlimited
                guard from != to else { return nil }
                return BanlistDifference(
                    konamiID: konamiID, name: names[konamiID], before: from, after: to)
            }
            .sorted { ($0.name ?? "", $0.konamiID) < ($1.name ?? "", $1.konamiID) }
    }

    public func statuses(
        forKonamiID konamiID: Int, format: BanlistFormat
    ) throws -> [String: BanlistStatus] {
        try database.read { db in
            var result: [String: BanlistStatus] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT r.effective_date, e.status
                FROM banlist_entry e
                JOIN banlist_revision r ON r.id = e.revision_id
                WHERE e.konami_id = ? AND r.format_code = ?
                """, arguments: [konamiID, format.rawValue]) {
                if let status = BanlistStatus(storedValue: row["status"]) {
                    result[row["effective_date"] as String] = status
                }
            }
            return result
        }
    }

    private func statusesByKonamiID(
        _ format: BanlistFormat, effectiveDate: String
    ) throws -> [Int: BanlistStatus] {
        try database.read { db in
            var result: [Int: BanlistStatus] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT e.konami_id, e.status
                FROM banlist_entry e
                JOIN banlist_revision r ON r.id = e.revision_id
                WHERE r.format_code = ? AND r.effective_date = ?
                """, arguments: [format.rawValue, effectiveDate]) {
                if let status = BanlistStatus(storedValue: row["status"]) {
                    result[row["konami_id"] as Int] = status
                }
            }
            return result
        }
    }

    private func names(forKonamiIDs konamiIDs: Set<Int>) throws -> [Int: String] {
        guard !konamiIDs.isEmpty else { return [:] }
        return try database.read { db in
            var result: [Int: String] = [:]
            let placeholders = databaseQuestionMarks(count: konamiIDs.count)
            for row in try Row.fetchAll(db, sql: """
                SELECT konami_id, COALESCE(name_it, name_en) AS name
                FROM card WHERE konami_id IN (\(placeholders))
                """, arguments: StatementArguments(Array(konamiIDs))) {
                result[row["konami_id"] as Int] = row["name"]
            }
            return result
        }
    }
}

extension SQLiteBanlistHistory: BanlistProvenanceReporting {
    public func provenance(for format: BanlistFormat) throws -> BanlistProvenance {
        try database.read { db in
            let sources = try String.fetchAll(db, sql: """
                SELECT DISTINCT source FROM banlist_revision
                WHERE format_code = ? ORDER BY source
                """, arguments: [format.rawValue])

            let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) AS n, MAX(fetched_at) AS last_fetch,
                       MAX(effective_date) AS newest
                FROM banlist_revision WHERE format_code = ?
                """, arguments: [format.rawValue])

            return BanlistProvenance(
                format: format,
                sources: sources,
                lastSynchronised: row?["last_fetch"],
                revisionCount: row?["n"] ?? 0,
                newestList: row?["newest"])
        }
    }

    public func disagreements(for format: BanlistFormat) throws -> [BanlistDisagreement] {
        guard let cardFormat = format.cardFormat else { return [] }

        return try database.read { db in
            // The newest stored list is the history's current word.
            guard let newest = try Row.fetchOne(db, sql: """
                SELECT id, effective_date, source FROM banlist_revision
                WHERE format_code = ? ORDER BY effective_date DESC LIMIT 1
                """, arguments: [format.rawValue])
            else { return [] }

            let revisionID: Int64 = newest["id"]
            let effectiveDate: String = newest["effective_date"]
            let source: String = newest["source"]

            // Every card either source names, joined on konami_id. A card
            // named by one and not the other is a disagreement too: absence
            // means unrestricted on both sides.
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.id AS card_id, c.konami_id,
                       COALESCE(c.name_it, c.name_en) AS name,
                       b.status AS catalog_status, e.status AS history_status
                FROM card c
                LEFT JOIN ban_status b
                    ON b.card_id = c.id AND b.format_code = ?
                LEFT JOIN banlist_entry e
                    ON e.konami_id = c.konami_id AND e.revision_id = ?
                WHERE c.konami_id IS NOT NULL
                  AND (b.status IS NOT NULL OR e.status IS NOT NULL)
                ORDER BY name, c.id
                """, arguments: [cardFormat.rawValue, revisionID])

            return rows.compactMap { row in
                let catalog = BanStatus(storedValue: row["catalog_status"])
                let history = BanStatus(storedValue: row["history_status"])
                guard catalog != history else { return nil }
                return BanlistDisagreement(
                    cardID: row["card_id"],
                    konamiID: row["konami_id"],
                    name: row["name"],
                    catalogStatus: catalog,
                    historyStatus: history,
                    historyEffectiveDate: effectiveDate,
                    historySource: source)
            }
        }
    }
}

extension SQLiteBanlistHistory: DeckListJudging {
    /// Every distinct card of a deck, judged against one stored list.
    ///
    /// One statement: the deck's slots joined to the catalog and left-joined
    /// to the list's entries, with copies summed per card. A deck holds at
    /// most ninety distinct cards, so this is small by construction and needs
    /// no lookup per card.
    ///
    /// The join is a `LEFT JOIN` on purpose. A card the list does not name has
    /// to come back — as unrestricted — rather than fall out of the result and
    /// leave the deck looking smaller than it is.
    public func judge(
        _ deckID: Int64, against format: BanlistFormat, effectiveDate: String
    ) async throws -> [ListedDeckCard] {
        try await database.read { db -> [ListedDeckCard] in
            guard let revisionID = try Int64.fetchOne(db, sql: """
                SELECT id FROM banlist_revision
                WHERE format_code = ? AND effective_date = ?
                """, arguments: [format.rawValue, effectiveDate])
            else { return [] }

            return try Row.fetchAll(db, sql: """
                SELECT card.id AS card_id,
                       COALESCE(card.name_it, card.name_en) AS name,
                       card.konami_id AS konami_id,
                       SUM(deck_slot.quantity) AS held,
                       banlist_entry.status AS status
                FROM deck_slot
                JOIN card ON card.id = deck_slot.card_id
                LEFT JOIN banlist_entry
                       ON banlist_entry.konami_id = card.konami_id
                      AND banlist_entry.revision_id = ?
                WHERE deck_slot.deck_id = ?
                GROUP BY card.id
                ORDER BY name COLLATE NOCASE
                """, arguments: [revisionID, deckID]).map { row in
                let konamiID: Int? = row["konami_id"]
                let stored: String? = row["status"]
                return ListedDeckCard(
                    card: CardIdentifier(row["card_id"]),
                    name: row["name"] ?? "",
                    held: row["held"] ?? 0,
                    status: stored.flatMap(BanlistStatus.init(storedValue:)),
                    isMatched: konamiID != nil)
            }
        }
    }
}
