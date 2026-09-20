/// How many copies of a card a format permits.
///
/// The upstream catalog publishes only the three restricting statuses; a card
/// with no entry is unrestricted. `unlimited` therefore has no stored form, and
/// `storedValue` returns `nil` for it.
public enum BanStatus: Hashable, Sendable, Codable, CaseIterable {
    case forbidden
    case limited
    case semiLimited
    case unlimited

    /// The value written to the catalog, or `nil` when the status is expressed
    /// by the absence of a row.
    public var storedValue: String? {
        switch self {
        case .forbidden: "forbidden"
        case .limited: "limited"
        case .semiLimited: "semi_limited"
        case .unlimited: nil
        }
    }

    /// Reconstructs a status from its stored form. A missing row means the card
    /// is unrestricted in that format.
    public init(storedValue: String?) {
        switch storedValue {
        case "forbidden": self = .forbidden
        case "limited": self = .limited
        case "semi_limited": self = .semiLimited
        default: self = .unlimited
        }
    }

    /// The number of copies this status permits across a whole deck.
    public var copyAllowance: CopyAllowance {
        switch self {
        case .forbidden: .none
        case .limited: .one
        case .semiLimited: .two
        case .unlimited: .three
        }
    }
}

/// How many copies of one card a deck may hold.
///
/// Wrapping the count keeps deck validation from comparing bare integers whose
/// meaning depends on which rule produced them.
public struct CopyAllowance: Hashable, Sendable, Codable, Comparable {
    public let maximumCopies: Int

    public init(maximumCopies: Int) {
        self.maximumCopies = max(0, maximumCopies)
    }

    public static let none = CopyAllowance(maximumCopies: 0)
    public static let one = CopyAllowance(maximumCopies: 1)
    public static let two = CopyAllowance(maximumCopies: 2)
    public static let three = CopyAllowance(maximumCopies: 3)

    public static func < (lhs: CopyAllowance, rhs: CopyAllowance) -> Bool {
        lhs.maximumCopies < rhs.maximumCopies
    }

    /// Whether a deck holding `count` copies stays within this allowance.
    public func permits(_ count: Int) -> Bool { count <= maximumCopies }
}
