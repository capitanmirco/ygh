import Foundation

/// Reads published lists from the history upstream.
///
/// The seam lives here, next to the types it speaks in, so neither persistence
/// nor a feature module has to know which host serves them.
public protocol BanlistFetching: Sendable {
    /// The effective dates the source publishes for a format, oldest first.
    func availableDates(for format: BanlistFormat) async throws -> [String]

    /// One published list.
    func fetchList(
        _ format: BanlistFormat, effectiveDate: String
    ) async throws -> PublishedBanlist
}

/// What a synchronisation did, reported rather than logged.
public struct BanlistSyncReport: Hashable, Sendable {
    /// Lists written by this run, per format.
    public let stored: [BanlistFormat: Int]
    /// Lists that were already held and therefore never fetched.
    public let alreadyHeld: [BanlistFormat: Int]
    /// Distinct `konami_id`s named by a stored list that the catalog does not
    /// hold. Their entries are stored anyway (`R1.AC6`).
    public let unmatchedKonamiIDs: Int
    /// Formats whose acquisition failed, with the reason.
    public let failures: [BanlistFormat: String]

    public init(
        stored: [BanlistFormat: Int],
        alreadyHeld: [BanlistFormat: Int],
        unmatchedKonamiIDs: Int,
        failures: [BanlistFormat: String]
    ) {
        self.stored = stored
        self.alreadyHeld = alreadyHeld
        self.unmatchedKonamiIDs = unmatchedKonamiIDs
        self.failures = failures
    }

    public var storedTotal: Int { stored.values.reduce(0, +) }
    public var fetchedNothing: Bool { storedTotal == 0 }
    public var succeeded: Bool { failures.isEmpty }
}

/// Writes published lists and reports what is already held.
public protocol BanlistHistoryWriting: Sendable {
    /// The effective dates already stored for a format.
    func heldDates(for format: BanlistFormat) throws -> Set<String>

    /// Stores one list with its entries, returning how many of its
    /// identifiers the catalog does not hold.
    @discardableResult
    func store(
        _ list: PublishedBanlist, format: BanlistFormat,
        source: String, fetchedAt: Date
    ) throws -> Int
}

/// One stored list, with what it came from.
public struct BanlistRevision: Hashable, Sendable {
    public let format: BanlistFormat
    public let effectiveDate: String
    public let source: String
    public let fetchedAt: String
    public let entryCount: Int

    public init(
        format: BanlistFormat, effectiveDate: String,
        source: String, fetchedAt: String, entryCount: Int
    ) {
        self.format = format
        self.effectiveDate = effectiveDate
        self.source = source
        self.fetchedAt = fetchedAt
        self.entryCount = entryCount
    }
}

/// A card named on a list. The name is absent when the catalog holds no card
/// for that identifier, which is what `R1.AC6` stores rather than discards.
public struct BanlistListEntry: Hashable, Sendable {
    public let konamiID: Int
    public let cardID: Int?
    public let name: String?
    public let italianName: String?
    public let status: BanlistStatus
    /// What the card is, for grouping a list by kind. Nil when the catalog
    /// cannot match the entry — the same condition that leaves `cardID` and
    /// `name` nil.
    public let frame: CardFrame?

    public init(
        konamiID: Int, cardID: Int?, name: String?,
        italianName: String?, status: BanlistStatus, frame: CardFrame? = nil
    ) {
        self.konamiID = konamiID
        self.cardID = cardID
        self.name = name
        self.italianName = italianName
        self.status = status
        self.frame = frame
    }

    public var displayName: String {
        italianName ?? name ?? "konami_id \(konamiID)"
    }
}

/// A card whose status differs between two lists.
public struct BanlistDifference: Hashable, Sendable {
    public let konamiID: Int
    public let name: String?
    public let before: BanStatus
    public let after: BanStatus

    public init(konamiID: Int, name: String?, before: BanStatus, after: BanStatus) {
        self.konamiID = konamiID
        self.name = name
        self.before = before
        self.after = after
    }
}

/// Reads stored history. Every question is answered from stored rows, with no
/// network (`NFR3`).
public protocol BanlistHistoryReading: Sendable {
    /// The lists held for a format, oldest first.
    func revisions(for format: BanlistFormat) throws -> [BanlistRevision]

    /// Every card named on one list.
    func list(_ format: BanlistFormat, effectiveDate: String) throws -> [BanlistListEntry]

    /// The cards whose status differs between two lists, including those
    /// newly named and those dropped.
    func difference(
        _ format: BanlistFormat, from earlier: String, to later: String
    ) throws -> [BanlistDifference]

    /// A card's status on each list of a format that named it.
    func statuses(
        forKonamiID konamiID: Int, format: BanlistFormat
    ) throws -> [String: BanlistStatus]
}

/// Where a stored history came from and when it was read.
///
/// Carried by the rows rather than assumed by the reader, so a history can say
/// it is not the catalog talking (`R4.AC1`) and how stale it is (`R4.AC2`).
public struct BanlistProvenance: Hashable, Sendable {
    public let format: BanlistFormat
    public let sources: [String]
    public let lastSynchronised: String?
    public let revisionCount: Int
    public let newestList: String?

    public init(
        format: BanlistFormat, sources: [String], lastSynchronised: String?,
        revisionCount: Int, newestList: String?
    ) {
        self.format = format
        self.sources = sources
        self.lastSynchronised = lastSynchronised
        self.revisionCount = revisionCount
        self.newestList = newestList
    }

    public var isEmpty: Bool { revisionCount == 0 }
}

/// A card the two sources describe differently.
///
/// Reported, never reconciled: the catalog's `ban_status` is `card-catalog`'s
/// certified contract and the history is a second opinion, so the honest answer
/// names both rather than picking one (`R4.AC3`).
public struct BanlistDisagreement: Hashable, Sendable {
    public let cardID: Int
    public let konamiID: Int
    public let name: String?
    public let catalogStatus: BanStatus
    public let historyStatus: BanStatus
    public let historyEffectiveDate: String
    public let historySource: String

    public init(
        cardID: Int, konamiID: Int, name: String?,
        catalogStatus: BanStatus, historyStatus: BanStatus,
        historyEffectiveDate: String, historySource: String
    ) {
        self.cardID = cardID
        self.konamiID = konamiID
        self.name = name
        self.catalogStatus = catalogStatus
        self.historyStatus = historyStatus
        self.historyEffectiveDate = historyEffectiveDate
        self.historySource = historySource
    }
}

/// States where a history came from, and where it differs from the catalog.
public protocol BanlistProvenanceReporting: Sendable {
    func provenance(for format: BanlistFormat) throws -> BanlistProvenance

    /// Cards whose status on the newest stored list differs from the one the
    /// catalog currently holds.
    func disagreements(for format: BanlistFormat) throws -> [BanlistDisagreement]
}
