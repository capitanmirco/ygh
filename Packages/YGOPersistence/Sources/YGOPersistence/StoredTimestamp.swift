import Foundation

/// Reads the two date shapes the database actually holds.
///
/// `last_sync_at` is written by this application as ISO 8601; the upstream's
/// own `last_update` arrives as `2026-09-16 00:05:12` and is stored verbatim.
/// A panel reporting both has to read both, and an unparseable value is
/// reported as absent rather than as an error: a date nobody can read is not a
/// reason to refuse to show the version beside it.
///
/// The formatter is built per call rather than held in a static. A cached
/// `DateFormatter` is shared mutable state that Swift 6 rejects, and this is
/// read when a settings panel opens, not in a loop.
enum StoredTimestamp {
    static func date(from text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        if let parsed = try? Date(text, strategy: .iso8601) { return parsed }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)
    }
}
