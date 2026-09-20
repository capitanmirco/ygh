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
