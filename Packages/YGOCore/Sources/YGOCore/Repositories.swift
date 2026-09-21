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
