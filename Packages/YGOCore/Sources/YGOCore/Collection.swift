import Foundation

/// The physical state of a card, on the scale the trading-card market uses.
///
/// Not in the catalog: these five grades are the ones shops and marketplaces
/// price against, and this application defines them.
public enum CardCondition: String, Hashable, Sendable, Codable, CaseIterable {
    case nearMint = "near_mint"
    case lightlyPlayed = "lightly_played"
    case moderatelyPlayed = "moderately_played"
    case heavilyPlayed = "heavily_played"
    case damaged

    /// Best first, which is the order a collector thinks in.
    public static let byQuality: [CardCondition] = [
        .nearMint, .lightlyPlayed, .moderatelyPlayed, .heavilyPlayed, .damaged,
    ]

    public var italianName: String {
        switch self {
        case .nearMint: "Come nuova"
        case .lightlyPlayed: "Poco giocata"
        case .moderatelyPlayed: "Giocata"
        case .heavilyPlayed: "Molto giocata"
        case .damaged: "Danneggiata"
        }
    }

    /// The short form shops abbreviate to, kept because a collector reading
    /// their own records recognises it faster than a full phrase.
    public var abbreviation: String {
        switch self {
        case .nearMint: "NM"
        case .lightlyPlayed: "LP"
        case .moderatelyPlayed: "MP"
        case .heavilyPlayed: "HP"
        case .damaged: "DMG"
        }
    }
}

/// A binder, a box, a shelf.
public struct StorageLocation: Hashable, Sendable, Identifiable {
    public let id: Int64
    public var name: String
    public var notes: String?

    public init(id: Int64, name: String, notes: String? = nil) {
        self.id = id
        self.name = name
        self.notes = notes
    }
}

/// A group of identical copies acquired together.
///
/// Not one row per physical card: a collector who bought three commons in one
/// go has no interest in three rows, and every question asked of a collection
/// is an aggregate. Copies that genuinely differ - a played copy beside a mint
/// one, or two purchases at different prices - are different lots.
public struct CollectionEntry: Hashable, Sendable, Identifiable {
    public let id: Int64
    public let card: CardIdentifier
    /// Absent for the 552 cards the catalog lists no printing for, thirty of
    /// which are legal in TCG and would otherwise be impossible to own.
    public let printID: Int64?
    public var condition: CardCondition
    public var quantity: Int
    /// What one copy cost. Absent means unrecorded, which is not free.
    public var purchasePrice: Double?
    public var acquiredAt: Date?
    public var locationID: Int64?
    public var notes: String?

    public init(
        id: Int64,
        card: CardIdentifier,
        printID: Int64?,
        condition: CardCondition,
        quantity: Int,
        purchasePrice: Double? = nil,
        acquiredAt: Date? = nil,
        locationID: Int64? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.card = card
        self.printID = printID
        self.condition = condition
        self.quantity = max(0, quantity)
        self.purchasePrice = purchasePrice
        self.acquiredAt = acquiredAt
        self.locationID = locationID
        self.notes = notes
    }

    /// What this lot cost in total, or `nil` when its price is unrecorded.
    public var lotCost: Double? {
        purchasePrice.map { $0 * Double(quantity) }
    }
}

/// What a collection amounts to.
public struct CollectionTotals: Hashable, Sendable {
    public let distinctCards: Int
    public let totalCopies: Int
    /// The sum of what was recorded as paid. Lots with no recorded price
    /// contribute nothing, so this is a sum of what is known rather than a
    /// valuation of the whole.
    public let recordedSpend: Double

    public init(distinctCards: Int, totalCopies: Int, recordedSpend: Double) {
        self.distinctCards = distinctCards
        self.totalCopies = totalCopies
        self.recordedSpend = recordedSpend
    }

    public var isEmpty: Bool { totalCopies == 0 }
}

/// One owned card as the list shows it.
public struct OwnedCardItem: Identifiable, Hashable, Sendable {
    public let id: CardIdentifier
    public let name: String
    public let copies: Int

    public init(id: CardIdentifier, name: String, copies: Int) {
        self.id = id
        self.name = name
        self.copies = copies
    }

    public var accessibilityLabel: String {
        copies == 1 ? "\(name), 1 copia" : "\(name), \(copies) copie"
    }
}

/// What the collection view needs from storage, declared here so the feature
/// compiles and is tested without SQLite.
public protocol CollectionReading: Sendable {
    func ownedCardItems(matching query: String) async throws -> [OwnedCardItem]
    func collectionTotals() async throws -> CollectionTotals
    func ownedCopiesByCard() async throws -> [CardIdentifier: Int]
}
