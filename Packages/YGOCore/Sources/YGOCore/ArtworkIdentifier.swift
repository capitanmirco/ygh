/// Identifies one printed artwork of a card.
///
/// A card with several artworks publishes one of these per artwork, and only
/// one of them usually equals the card's own identifier. Deck files produced by
/// other tools reference artworks, not cards, which is why resolving one to the
/// other is a catalog responsibility rather than an arithmetic one.
public struct ArtworkIdentifier: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }
}

extension ArtworkIdentifier: CustomStringConvertible {
    public var description: String { String(rawValue) }
}
