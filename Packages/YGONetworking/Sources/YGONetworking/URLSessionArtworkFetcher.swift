import Foundation
import YGOCore

/// Downloads card artwork from the upstream image host.
///
/// Every request goes through the same transport, and therefore the same rate
/// limiter, as the catalog itself: the published ceiling counts all requests
/// together, not one budget per kind of resource.
public struct URLSessionArtworkFetcher: ArtworkFetching {
    private let transport: any CatalogTransport

    public init(transport: any CatalogTransport) {
        self.transport = transport
    }

    public func imageData(
        for identifier: ArtworkIdentifier,
        variant: ArtworkVariant
    ) async throws -> Data {
        try await transport.data(from: Self.url(for: identifier, variant: variant))
    }

    /// Thumbnails average about 24 KB and full images about 138 KB, which is
    /// why the two are fetched on different schedules.
    public static func url(for identifier: ArtworkIdentifier, variant: ArtworkVariant) -> URL {
        let folder = variant == .thumbnail ? "cards_small" : "cards"
        return URL(string:
            "https://images.ygoprodeck.com/images/\(folder)/\(identifier.rawValue).jpg")!
    }
}
