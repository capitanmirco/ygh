import Foundation
import YGOCore

/// Brings the stored history up to what the source publishes.
///
/// The set of stored dates is the cursor: the run fetches whatever the
/// enumeration returned minus what is already held, so there is no incremental
/// bookmark that could fall out of step with the tables.
///
/// A failure is reported per format rather than thrown, because losing the OCG
/// is no reason to lose the TCG, and because R1.AC5 asks for the lists already
/// stored to be kept.
public struct BanlistHistorySynchronizer: Sendable {
    private let client: any BanlistFetching
    private let store: any BanlistHistoryWriting
    private let source: String
    private let now: @Sendable () -> Date

    public init(
        client: any BanlistFetching,
        store: any BanlistHistoryWriting,
        source: String,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.store = store
        self.source = source
        self.now = now
    }

    public func synchronize(
        formats: [BanlistFormat] = BanlistFormat.allCases
    ) async -> BanlistSyncReport {
        var stored: [BanlistFormat: Int] = [:]
        var alreadyHeld: [BanlistFormat: Int] = [:]
        var unmatched = 0
        var failures: [BanlistFormat: String] = [:]

        for format in formats {
            do {
                let published = try await client.availableDates(for: format)
                let held = try store.heldDates(for: format)
                let missing = published.filter { !held.contains($0) }

                alreadyHeld[format] = published.count - missing.count
                stored[format] = 0

                for date in missing {
                    let list = try await client.fetchList(format, effectiveDate: date)
                    unmatched += try store.store(
                        list, format: format, source: source, fetchedAt: now())
                    stored[format, default: 0] += 1
                }
            } catch {
                failures[format] = String(describing: error)
            }
        }

        return BanlistSyncReport(
            stored: stored, alreadyHeld: alreadyHeld,
            unmatchedKonamiIDs: unmatched, failures: failures)
    }
}
