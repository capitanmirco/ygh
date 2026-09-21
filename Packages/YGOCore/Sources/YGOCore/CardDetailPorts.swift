import Foundation

/// One printing of a card: where it appeared, under what code, at what rarity.
public struct CardPrinting: Hashable, Sendable {
    public let setName: String
    public let setCode: String
    public let rarity: String
    /// What the upstream listed for this printing, when it listed anything.
    /// Absent is absent; it is never zero.
    public let listedPrice: Double?

    public init(setName: String, setCode: String, rarity: String, listedPrice: Double?) {
        self.setName = setName
        self.setCode = setCode
        self.rarity = rarity
        self.listedPrice = listedPrice
    }
}

/// When a card became available, by region.
///
/// 85 of the catalog's 14,566 cards carry neither date. `unknown` says that,
/// where an empty string or a zero date would pretend to an answer.
public enum CardRelease: Hashable, Sendable {
    case known(tcg: String?, ocg: String?)
    case unknown

    public init(tcg: String?, ocg: String?) {
        if tcg == nil, ocg == nil {
            self = .unknown
        } else {
            self = .known(tcg: tcg, ocg: ocg)
        }
    }

    /// The date that applies in a format, when the catalog holds one. The
    /// restriction history needs it to tell "unrestricted on that list" from
    /// "not printed yet".
    public func date(for format: BanlistFormat) -> String? {
        guard case let .known(tcg, ocg) = self else { return nil }
        switch format {
        case .tcg: return tcg
        case .ocg, .masterDuel, .rush: return ocg ?? tcg
        }
    }

    public var isKnown: Bool {
        if case .known = self { return true }
        return false
    }
}

/// The parts of a card the browser does not need and a detail panel does.
///
/// Separate from `CardRepository` because `Card` carries what search and deck
/// building need, and widening it for two fields one panel reads would touch a
/// type five certified specifications construct.
public protocol CardDetailReading: Sendable {
    func printings(forCard identifier: CardIdentifier) async throws -> [CardPrinting]
    func release(forCard identifier: CardIdentifier) async throws -> CardRelease
    /// The identifier the published ban lists use, when the catalog holds one.
    func konamiID(forCard identifier: CardIdentifier) async throws -> Int?
}

/// Copies of a card held, grouped as the collection stores them: a lot of
/// identical copies in one condition, in one place.
public struct CardHolding: Hashable, Sendable {
    public let quantity: Int
    public let condition: CardCondition
    /// The place the copies are kept, or `nil` when they are unfiled. A
    /// deleted location releases its copies rather than taking them with it.
    public let location: String?

    public init(quantity: Int, condition: CardCondition, location: String?) {
        self.quantity = quantity
        self.condition = condition
        self.location = location
    }

    public var locationName: String { location ?? "Non archiviata" }
}

/// A card's place in one deck, in one of its sections.
///
/// Reported per section rather than summed: a card held three times in the
/// main deck and once in the side is two facts, and collapsing them would hide
/// the one that matters when taking the card back out.
public struct DeckUse: Hashable, Sendable {
    public let deckID: Int64
    public let deckName: String
    public let section: DeckSection
    public let quantity: Int

    public init(deckID: Int64, deckName: String, section: DeckSection, quantity: Int) {
        self.deckID = deckID
        self.deckName = deckName
        self.section = section
        self.quantity = quantity
    }
}

/// Where the copies of a card are: owned, and in play.
public protocol CardUsageReading: Sendable {
    func holdings(forCard identifier: CardIdentifier) async throws -> [CardHolding]
    func deckUses(forCard identifier: CardIdentifier) async throws -> [DeckUse]
}
