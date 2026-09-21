import Foundation
import YGOCore

/// A card's status on one published list.
public struct BanlistTimelineEntry: Hashable, Sendable {
    public let effectiveDate: String
    public let status: BanStatus

    public init(effectiveDate: String, status: BanStatus) {
        self.effectiveDate = effectiveDate
        self.status = status
    }
}

/// A list on which a card's status differed from the one before it.
public struct BanlistChange: Hashable, Sendable {
    public let effectiveDate: String
    public let from: BanStatus
    public let to: BanStatus

    public init(effectiveDate: String, from: BanStatus, to: BanStatus) {
        self.effectiveDate = effectiveDate
        self.from = from
        self.to = to
    }
}

/// What the game has thought of one card in one format.
///
/// Built from dated statuses and nothing else, which is what makes it provable
/// without a database: the whole of `R2` is arithmetic over `entries`.
public struct BanlistTimeline: Hashable, Sendable {
    public let format: BanlistFormat
    /// Oldest first, one per list published while the card existed.
    public let entries: [BanlistTimelineEntry]

    public init(format: BanlistFormat, entries: [BanlistTimelineEntry]) {
        self.format = format
        self.entries = entries
    }

    /// The lists on which the status differed from the previous one.
    ///
    /// The baseline before the first list is unrestricted, so a card that is
    /// already forbidden on the first list it appears on changed there. This is
    /// one pass over `entries` rather than a second query.
    public var changes: [BanlistChange] {
        var result: [BanlistChange] = []
        var previous: BanStatus = .unlimited
        for entry in entries where entry.status != previous {
            result.append(BanlistChange(
                effectiveDate: entry.effectiveDate, from: previous, to: entry.status))
            previous = entry.status
        }
        return result
    }

    /// True when no list of this format ever restricted the card.
    public var wasNeverRestricted: Bool {
        entries.allSatisfy { $0.status == .unlimited }
    }

    public var currentStatus: BanStatus? {
        entries.last?.status
    }
}

public enum BanlistTimelineBuilder {
    /// Builds a card's timeline from the lists of one format.
    ///
    /// - Parameters:
    ///   - revisionDates: every list the format published, any order.
    ///   - statuses: the dates on which this card was named, and how.
    ///   - releaseDate: when the card became available in this format. A list
    ///     published before it says nothing about the card, so it is left out
    ///     rather than reported as unrestricted (`R2.AC3`). A nil release date
    ///     is unknown rather than ancient, so no list is dropped.
    public static func timeline(
        format: BanlistFormat,
        revisionDates: [String],
        statuses: [String: BanlistStatus],
        releaseDate: String?
    ) -> BanlistTimeline {
        let entries = revisionDates
            .sorted()
            .filter { date in
                guard let releaseDate else { return true }
                return date >= releaseDate
            }
            .map { date in
                // Absence from a list is what carries "unrestricted" (`C3`).
                BanlistTimelineEntry(
                    effectiveDate: date,
                    status: statuses[date]?.banStatus ?? .unlimited)
            }
        return BanlistTimeline(format: format, entries: entries)
    }
}
