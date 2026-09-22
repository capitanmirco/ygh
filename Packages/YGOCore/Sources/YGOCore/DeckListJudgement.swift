import Foundation

/// One of a deck's cards, as a published Forbidden & Limited List sees it.
public struct ListedDeckCard: Hashable, Sendable, Identifiable {
    public let card: CardIdentifier
    public let name: String
    /// Copies the deck holds, summed across its sections.
    public let held: Int
    /// What the list says, or nil when the list does not name this card.
    public let status: BanlistStatus?
    /// False when the card carries no identifier the lists use, so nothing
    /// could be looked up. Reporting such a card as unrestricted would read
    /// exactly like a correct answer, which is the one thing this must not do.
    public let isMatched: Bool

    public init(
        card: CardIdentifier,
        name: String,
        held: Int,
        status: BanlistStatus?,
        isMatched: Bool = true
    ) {
        self.card = card
        self.name = name
        self.held = held
        self.status = status
        self.isMatched = isMatched
    }

    public var id: CardIdentifier { card }

    /// Copies the list permits. Three when it names no restriction: that is
    /// the ceiling that holds whatever any list says.
    public var permitted: Int {
        switch status {
        case .forbidden: 0
        case .limited: 1
        case .semiLimited: 2
        case nil: 3
        }
    }

    /// Only a matched card can be over an allowance: an unmatched one has no
    /// allowance to be over.
    public var isOverAllowance: Bool { isMatched && held > permitted }

    /// What a screen reader says about the row.
    public var announcement: String {
        guard isMatched else { return "\(name), non abbinabile alla lista, \(held) in mazzo" }
        let verdict = switch status {
        case .forbidden: "vietata"
        case .limited: "limitata"
        case .semiLimited: "semi-limitata"
        case nil: "non elencata"
        }
        return "\(name), \(verdict), \(held) in mazzo, \(permitted) consentite"
    }
}

/// A deck judged against one published list.
///
/// Every total is computed from `cards`, not stored beside it: four numbers
/// kept in step with an array are four ways to disagree with it.
public struct DeckListVerdict: Hashable, Sendable {
    public let list: BanlistRevision
    public let cards: [ListedDeckCard]

    public init(list: BanlistRevision, cards: [ListedDeckCard]) {
        self.list = list
        self.cards = cards
    }

    public var forbidden: Int { cards.count { $0.isMatched && $0.status == .forbidden } }
    public var limited: Int { cards.count { $0.isMatched && $0.status == .limited } }
    public var semiLimited: Int { cards.count { $0.isMatched && $0.status == .semiLimited } }
    public var unmatched: Int { cards.count { !$0.isMatched } }
    public var overAllowance: [ListedDeckCard] { cards.filter(\.isOverAllowance) }

    /// A deck is within a list when no card of it exceeds what the list
    /// permits. A forbidden card held at all is already over.
    public var isWithinList: Bool { overAllowance.isEmpty }

    /// What the verdict is about, so that "legale" is never a claim about
    /// nothing in particular.
    public var listName: String {
        "\(list.format.rawValue.uppercased()) \(list.effectiveDate)"
    }
}

/// Judges a deck against one stored list.
public protocol DeckListJudging: Sendable {
    /// Every distinct card of a deck, judged in one read.
    func judge(
        _ deckID: Int64, against format: BanlistFormat, effectiveDate: String
    ) async throws -> [ListedDeckCard]
}

public extension CardFormat {
    /// The published list a format is played under, when one defines it.
    ///
    /// GOAT and Edison are community formats named after the Forbidden &
    /// Limited List that was in force: March 2005 and March 2010. That is a
    /// judgement about how people play rather than something upstream
    /// publishes, which is why it is a default the user can change and not a
    /// rule they cannot.
    ///
    /// Nil is an answer, not a gap. Judging a Speed Duel deck against the
    /// current TCG list would look authoritative and be wrong.
    var impliedList: (format: BanlistFormat, effectiveDate: String?)? {
        switch self {
        case .tcg: (.tcg, nil)
        case .ocg: (.ocg, nil)
        case .masterDuel: (.masterDuel, nil)
        case .goat: (.tcg, "2005-03-01")
        case .edison: (.tcg, "2010-03-01")
        case .ocgGoat: (.ocg, "2005-03-01")
        case .duelLinks, .speedDuel, .commonCharity: nil
        }
    }
}
