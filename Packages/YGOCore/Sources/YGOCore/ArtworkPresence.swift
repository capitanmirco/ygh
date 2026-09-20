import Foundation

/// Tracks which artwork files the local store already holds.
///
/// Presence is recorded in the catalog database rather than discovered from
/// the filesystem, so resuming an interrupted prefetch is one anti-join instead
/// of fourteen thousand filesystem probes at every start.
///
/// Declared here so the image store can use it without depending on the
/// persistence module.
public protocol ArtworkPresenceTracking: Sendable {
    func isStored(_ identifier: ArtworkIdentifier, variant: ArtworkVariant) async throws -> Bool

    func recordStored(
        _ identifier: ArtworkIdentifier,
        variant: ArtworkVariant,
        byteSize: Int,
        at date: Date
    ) async throws

    /// Removes one presence record, used to repair the table when a file has
    /// been deleted behind the application's back.
    func forget(_ identifier: ArtworkIdentifier, variant: ArtworkVariant) async throws

    func forgetAll() async throws

    /// Artwork identifiers with no record for this variant, oldest card first.
    func missing(variant: ArtworkVariant, limit: Int?) async throws -> [ArtworkIdentifier]

    func storedCount(variant: ArtworkVariant) async throws -> Int
    func totalArtworkCount() async throws -> Int
}

/// What to draw for a card's artwork.
///
/// A card with no usable image is still an identifiable element rather than a
/// blank one, which is what keeps the grid readable offline.
public enum ArtworkPresentation: Hashable, Sendable {
    case stored(path: String)
    case placeholder(cardName: String)
}

/// Retrieves artwork bytes from upstream.
///
/// Separate from the store so that a test can drive prefetching, resumption and
/// failure handling without a network, and so that every retrieval passes the
/// one rate limiter on its way out.
public protocol ArtworkFetching: Sendable {
    func imageData(
        for identifier: ArtworkIdentifier,
        variant: ArtworkVariant
    ) async throws -> Data
}
