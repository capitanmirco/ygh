/// The passcode printed on a physical card, and the primary key of the catalog.
///
/// A card may be depicted by several artworks, each carrying its own identifier
/// of this same shape. Resolving an artwork identifier to the card it depicts is
/// the job of the catalog, not of this type.
public struct CardIdentifier: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }
}

extension CardIdentifier: CustomStringConvertible {
    public var description: String { String(rawValue) }
}
