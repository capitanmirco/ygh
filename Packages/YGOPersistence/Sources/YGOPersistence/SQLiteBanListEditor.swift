import Foundation
import GRDB
import YGOCore

public enum BanListEditingError: Error, Equatable {
    /// The format's restrictions come from upstream and are replaced on every
    /// catalog update, so a hand-written entry there would be both overwritten
    /// and, because one card may hold only one row per format, in the way of
    /// the update that overwrites it.
    case formatIsMaintainedUpstream(CardFormat)
    case unknownCard(CardIdentifier)
}

/// Records the restrictions the upstream catalog does not publish.
///
/// Edison and Master Duel expose which cards belong to them but no ban list at
/// all, so those lists can only come from the user. Entries written here are
/// tagged `source = 'user'` and a catalog update never touches them.
public struct SQLiteBanListEditor: BanListEditing {
    private let database: any DatabaseWriter

    public init(database: any DatabaseWriter) {
        self.database = database
    }

    public func setUserBanStatus(
        _ status: BanStatus,
        for identifier: CardIdentifier,
        in format: CardFormat
    ) async throws {
        guard !format.hasUpstreamBanList else {
            throw BanListEditingError.formatIsMaintainedUpstream(format)
        }

        try await database.write { db in
            let exists = try Bool.fetchOne(db, sql:
                "SELECT EXISTS(SELECT 1 FROM card WHERE id = ?)",
                arguments: [identifier.rawValue]) ?? false
            guard exists else { throw BanListEditingError.unknownCard(identifier) }

            guard let stored = status.storedValue else {
                // Unrestricted is the absence of a row, so amending a card back
                // to unlimited removes its entry rather than storing a fourth
                // status the schema does not accept.
                try db.execute(sql: """
                    DELETE FROM ban_status
                    WHERE card_id = ? AND format_code = ? AND source = 'user'
                    """, arguments: [identifier.rawValue, format.rawValue])
                return
            }

            try db.execute(sql: """
                INSERT INTO ban_status (card_id, format_code, status, source)
                VALUES (?, ?, ?, 'user')
                ON CONFLICT(card_id, format_code) DO UPDATE SET
                    status = excluded.status, source = 'user'
                """, arguments: [identifier.rawValue, format.rawValue, stored])
        }
    }
}
