import Foundation

/// The card properties a search can narrow on.
///
/// Every filter is a set or a range, and an empty one means "do not narrow on
/// this". Applying several narrows conjunctively: a card must satisfy all of
/// them, not any of them.
public struct CardFilters: Hashable, Sendable {
    public var frames: Set<CardFrame> = []
    public var attributes: Set<CardAttribute> = []
    public var races: Set<String> = []
    public var archetypes: Set<String> = []
    public var levels: ClosedRange<Int>?
    public var attack: ClosedRange<Int>?
    public var defense: ClosedRange<Int>?
    public var linkRatings: ClosedRange<Int>?
    public var pendulumScales: ClosedRange<Int>?
    /// Monster, spell or trap. Expands to frames before it reaches storage.
    public var cardTypes: Set<CardType> = []
    /// Cards released within these years, by the catalog's own dates.
    public var releaseYears: ClosedRange<Int>?
    /// Only cards whose attack or defence prints "?".
    ///
    /// Separate from the numeric ranges rather than a value inside them: the
    /// catalog stores `-1` for "?", and a range from 0 that admitted it would
    /// answer "weak monsters" with monsters nobody can measure.
    public var unknownStatsOnly = false
    /// A published Forbidden & Limited List, by format and effective date.
    ///
    /// Narrows to the cards that list named, and makes the grid show each
    /// card's status **on that list** rather than its current one. The two
    /// never mix: blending a 2005 list with today's statuses would state
    /// something neither source says.
    public var publishedList: PublishedListSelection?
    /// Only cards the collection holds at least one copy of.
    public var ownedOnly = false
    /// Restricts to cards legal in this format.
    public var format: CardFormat?
    /// Restricts to cards holding one of these statuses in `format`. Requires a
    /// format, since a status has no meaning without one.
    public var banStatuses: Set<BanStatus> = []

    public init() {}

    public var isEmpty: Bool {
        frames.isEmpty && attributes.isEmpty && races.isEmpty && archetypes.isEmpty
            && levels == nil && attack == nil && defense == nil
            && linkRatings == nil && pendulumScales == nil
            && format == nil && banStatuses.isEmpty
            && cardTypes.isEmpty && releaseYears == nil && !unknownStatsOnly
            && publishedList == nil && !ownedOnly
    }
}

/// One search: optional text, optional narrowing, and a page to return.
public struct CardQuery: Hashable, Sendable {
    public var text: String?
    public var filters: CardFilters
    public var limit: Int
    public var offset: Int

    public init(
        text: String? = nil,
        filters: CardFilters = CardFilters(),
        limit: Int = 100,
        offset: Int = 0
    ) {
        self.text = text
        self.filters = filters
        self.limit = limit
        self.offset = offset
    }

    /// The query text with surrounding whitespace removed, or `nil` when there
    /// is nothing to match on.
    public var normalizedText: String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// What a search found.
///
/// `noMatches` is a settled answer, not an absence of one: the interface can
/// tell it apart from a search still in flight without inspecting a count.
public enum CardSearchOutcome: Hashable, Sendable {
    case matches([Card])
    case noMatches

    public init(_ cards: [Card]) {
        self = cards.isEmpty ? .noMatches : .matches(cards)
    }

    public var cards: [Card] {
        switch self {
        case .matches(let cards): cards
        case .noMatches: []
        }
    }
}

/// Searches the stored catalog. Resolved entirely locally: no query reaches
/// upstream, so search works with no network at all.
public protocol CardSearching: Sendable {
    func search(_ query: CardQuery) async throws -> CardSearchOutcome
}

extension CardFilters {
    /// What is narrowing the results, in sentences rather than flags.
    ///
    /// Sentences because an empty grid has to name what emptied it, and
    /// because a screen reader needs something to read. A filter that is not
    /// applied is absent rather than present and empty.
    public var descriptions: [String] {
        var parts: [String] = []
        if !cardTypes.isEmpty {
            parts.append("tipo: " + cardTypes.map(\.italianName).sorted().joined(separator: ", "))
        }
        if !attributes.isEmpty {
            parts.append("attributo: " + attributes.map(\.rawValue).sorted().joined(separator: ", "))
        }
        if let levels {
            parts.append(levels.lowerBound == levels.upperBound
                         ? "livello \(levels.lowerBound)"
                         : "livello da \(levels.lowerBound) a \(levels.upperBound)")
        }
        if !races.isEmpty { parts.append("tipo mostro: " + races.sorted().joined(separator: ", ")) }
        if !archetypes.isEmpty { parts.append("archetipo: " + archetypes.sorted().joined(separator: ", ")) }
        if let attack { parts.append("attacco da \(attack.lowerBound) a \(attack.upperBound)") }
        if let defense { parts.append("difesa da \(defense.lowerBound) a \(defense.upperBound)") }
        if unknownStatsOnly { parts.append("attacco o difesa \"?\"") }
        if let releaseYears {
            parts.append(releaseYears.lowerBound == releaseYears.upperBound
                         ? "uscita nel \(releaseYears.lowerBound)"
                         : "uscita fra \(releaseYears.lowerBound) e \(releaseYears.upperBound)")
        }
        if let format { parts.append("formato: \(format.rawValue)") }
        if !banStatuses.isEmpty {
            parts.append("stato: " + banStatuses.map(\.italianName).sorted().joined(separator: ", "))
        }
        if let publishedList {
            parts.append("lista \(publishedList.format.displayName) del \(publishedList.effectiveDate)")
        }
        if ownedOnly { parts.append("solo carte possedute") }
        return parts
    }
}

extension CardType {
    public var italianName: String {
        switch self {
        case .monster: "mostro"
        case .spell: "magia"
        case .trap: "trappola"
        case .other: "altro"
        }
    }
}

/// One published list, chosen by the format that published it and the day it
/// took effect.
public struct PublishedListSelection: Hashable, Sendable {
    public let format: BanlistFormat
    public let effectiveDate: String

    public init(format: BanlistFormat, effectiveDate: String) {
        self.format = format
        self.effectiveDate = effectiveDate
    }
}

/// What kind of card this is, for a user who thinks in three kinds rather
/// than seventeen frames.
///
/// Derived rather than stored: the catalog holds a frame, and monster, spell
/// and trap are groupings of it. A column would be a second source of truth
/// for something the frame already says.
public enum CardType: String, Hashable, Sendable, CaseIterable {
    case monster, spell, trap, other

    /// The frames this type covers. The filter expands to these before it
    /// reaches SQL, so it reuses the frame condition that already works.
    public var frames: [CardFrame] {
        CardFrame.allCases.filter { $0.cardType == self }
    }
}

extension CardType {
    /// Monsters, then spells, then traps. A decklist is read in that order,
    /// so every list that groups cards by kind takes its rank from here
    /// rather than each one deciding for itself.
    public var listingOrder: Int {
        switch self {
        case .monster: 0
        case .spell: 1
        case .trap: 2
        case .other: 3
        }
    }
}

extension CardFrame {
    public var cardType: CardType {
        switch self {
        case .spell: .spell
        case .trap: .trap
        case .token, .skill: .other
        default: .monster
        }
    }
}
