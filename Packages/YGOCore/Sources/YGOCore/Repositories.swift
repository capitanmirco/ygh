import Foundation

/// Read access to the stored catalog.
///
/// Feature modules depend on this protocol rather than on the persistence
/// module, so they compile and test without SQLite.
public protocol CardRepository: Sendable {
    func card(with identifier: CardIdentifier) async throws -> Card?

    /// Resolves an artwork identifier to the card it depicts, or `nil` when the
    /// catalog holds no such artwork.
    func card(withArtwork identifier: ArtworkIdentifier) async throws -> Card?

    /// The card's status in `format`. A card with no restriction recorded is
    /// reported as `.unlimited`.
    func banStatus(for identifier: CardIdentifier, in format: CardFormat) async throws -> BanStatus

    func cardCount() async throws -> Int
}

/// Records restrictions for the formats the upstream catalog does not publish.
public protocol BanListEditing: Sendable {
    func setUserBanStatus(
        _ status: BanStatus,
        for identifier: CardIdentifier,
        in format: CardFormat
    ) async throws
}

/// Drives catalog acquisition and updates.
public protocol CatalogSyncing: Sendable {
    /// Seeds an empty catalog, or updates a populated one when the upstream
    /// version differs. Never throws for an unreachable upstream when a stored
    /// catalog is usable.
    func synchronize() async throws -> CatalogSyncOutcome
}

/// What a synchronisation attempt did.
public enum CatalogSyncOutcome: Hashable, Sendable {
    case seeded(cardCount: Int)
    case updated(cardCount: Int)
    case alreadyCurrent
    /// Upstream was unreachable and the stored catalog was kept.
    case keptStoredCatalog(reason: String)
}

/// Serves card artwork from the local store.
public protocol ArtworkProviding: Sendable {
    /// The file location of a stored artwork, or `nil` when it is not stored.
    /// Never returns a remote address: the upstream host forbids hotlinking.
    func storedArtworkPath(for identifier: ArtworkIdentifier, variant: ArtworkVariant) async -> String?
}

/// Which rendition of an artwork is wanted.
public enum ArtworkVariant: String, Hashable, Sendable, Codable, CaseIterable {
    case thumbnail = "thumb"
    case full
}

/// How many cards a query matches, regardless of how many are shown.
///
/// A separate port rather than a method on `CardSearching`: every offline stub
/// conforms to that protocol, and widening it would break each of them for one
/// number.
public protocol CardSearchCounting: Sendable {
    func matchCount(for query: CardQuery) async throws -> Int
}

/// The values a filter can offer, read from the catalog rather than hard-coded.
///
/// 87 monster types and 662 archetypes: too many for a menu, and both grow
/// whenever the catalog does.
public protocol CardVocabularyReading: Sendable {
    func monsterTypes() async throws -> [String]
    func archetypes() async throws -> [String]
}

/// What the stored catalog is, for a screen that reports it.
///
/// Three of its four facts are already kept in `sync_state` and have never
/// been shown anywhere.
public struct CatalogStatus: Hashable, Sendable {
    public let version: String
    /// The date upstream itself last changed the dataset.
    public let upstreamUpdatedAt: Date?
    /// When this application last stored a dataset. A check that finds nothing
    /// new does not move it, because nothing was stored.
    public let lastSyncAt: Date?
    public let cardCount: Int

    public init(
        version: String,
        upstreamUpdatedAt: Date?,
        lastSyncAt: Date?,
        cardCount: Int
    ) {
        self.version = version
        self.upstreamUpdatedAt = upstreamUpdatedAt
        self.lastSyncAt = lastSyncAt
        self.cardCount = cardCount
    }
}

/// Reads what the stored catalog is.
///
/// A protocol of its own rather than three more methods on `CatalogStore`:
/// every offline stub in the suite conforms to that one, and widening it
/// breaks all of them for the sake of one read.
public protocol CatalogStatusReading: Sendable {
    /// Nil when this database has never synchronised, which is not an error.
    func catalogStatus() async throws -> CatalogStatus?
}

/// One synchronisation, whoever asked for it.
///
/// The live binding is the launch's own flow, so a manual check cannot become
/// a second implementation that drifts from the one that runs at startup.
public protocol CatalogRefreshing: Sendable {
    func refresh() async -> CatalogSyncOutcome
}

/// What the artwork store occupies on disk.
public struct ArtworkFootprint: Hashable, Sendable {
    public let files: Int
    public let bytes: Int

    public init(files: Int, bytes: Int) {
        self.files = files
        self.bytes = bytes
    }
}

/// Measuring and emptying the image cache.
///
/// Separate from `ArtworkProviding`, which is what a view uses to draw a card:
/// nothing that draws should be able to empty the store.
public protocol ArtworkMaintaining: Sendable {
    func storedFootprint() async -> ArtworkFootprint
    func purge() async throws
}

/// What the application occupies on disk, as a settings panel reports it.
public struct StorageFootprint: Hashable, Sendable {
    public let artworkFiles: Int
    public let artworkBytes: Int
    /// The database file alone. The write-ahead log is excluded: it is not a
    /// second copy of the data, and it moves for reasons the user cannot act on.
    public let databaseBytes: Int
    /// Nil when no pre-migration backup is present, which is the ordinary case
    /// on a machine that has never migrated.
    public let backupBytes: Int?

    public init(
        artworkFiles: Int,
        artworkBytes: Int,
        databaseBytes: Int,
        backupBytes: Int?
    ) {
        self.artworkFiles = artworkFiles
        self.artworkBytes = artworkBytes
        self.databaseBytes = databaseBytes
        self.backupBytes = backupBytes
    }

    public var totalBytes: Int { artworkBytes + databaseBytes + (backupBytes ?? 0) }
}

/// Reading what is stored, and reclaiming the parts that can be fetched again.
///
/// Nothing here reaches user-authored data: the deck and collection tables are
/// the one thing in this application that cannot be downloaded a second time.
public protocol StorageInventorying: Sendable {
    func footprint() async -> StorageFootprint
    func purgeArtwork() async throws
    func deleteBackup() async throws
}
