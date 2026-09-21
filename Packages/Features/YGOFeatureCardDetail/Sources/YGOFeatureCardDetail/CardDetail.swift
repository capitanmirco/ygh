import Foundation
import YGOBanlistHistory
import YGOCore

/// One part of a detail, which is either there, known to be empty, or could
/// not be read.
///
/// An enum rather than an optional because six of this feature's criteria are
/// about saying that something is missing. A view cannot render "no printing
/// recorded" as an empty table by forgetting a branch, because there is no
/// branch to forget.
public enum DetailSection<Value: Hashable & Sendable>: Hashable, Sendable {
    case loaded(Value)
    /// Read successfully, and there is nothing. The reason is what the panel
    /// shows the reader.
    case empty(reason: String)
    /// The read itself failed. Different from empty, and never shown as it.
    case failed(reason: String)

    public var value: Value? {
        if case let .loaded(value) = self { return value }
        return nil
    }

    public var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    /// What the panel prints when there is nothing to draw.
    public var message: String? {
        switch self {
        case .loaded: nil
        case .empty(let reason), .failed(let reason): reason
        }
    }
}

/// What a card's restriction history amounts to.
///
/// Three answers, not two. "Never restricted" and "we cannot tell" read alike
/// in a panel and mean entirely different things, and 203 of the catalog's
/// 14,566 cards are in the second case.
public enum CardHistorySection: Hashable, Sendable {
    case timeline(BanlistTimeline)
    case neverRestricted(format: BanlistFormat)
    case unavailable(reason: String)

    public var timelineValue: BanlistTimeline? {
        if case let .timeline(timeline) = self { return timeline }
        return nil
    }

    public var changes: [BanlistChange] {
        timelineValue?.changes ?? []
    }
}

/// A source's figure for a card, or the statement that it has none.
public struct CardPriceLine: Hashable, Sendable {
    public let source: PriceSource
    /// `nil` means the source holds no price. It never means zero: 289 cards
    /// have no price from anybody, and free is not what that means.
    public let money: Money?
    public let observedAt: Date?

    public init(source: PriceSource, money: Money?, observedAt: Date?) {
        self.source = source
        self.money = money
        self.observedAt = observedAt
    }

    public var isUnpriced: Bool { money == nil }
    public var currency: Currency { source.currency }
}

/// Everything the panel shows about one card, assembled once.
public struct CardDetail: Hashable, Sendable {
    public let card: Card
    public let language: CardLanguage
    public let text: CardText
    public let release: CardRelease
    public let printings: DetailSection<[CardPrinting]>
    public let prices: [CardPriceLine]
    public let holdings: DetailSection<[CardHolding]>
    public let deckUses: DetailSection<[DeckUse]>
    public let currentStatus: BanStatus
    public let history: CardHistorySection
    public let disagreement: BanlistDisagreement?

    public init(
        card: Card,
        language: CardLanguage,
        text: CardText,
        release: CardRelease,
        printings: DetailSection<[CardPrinting]>,
        prices: [CardPriceLine],
        holdings: DetailSection<[CardHolding]>,
        deckUses: DetailSection<[DeckUse]>,
        currentStatus: BanStatus,
        history: CardHistorySection,
        disagreement: BanlistDisagreement?
    ) {
        self.card = card
        self.language = language
        self.text = text
        self.release = release
        self.printings = printings
        self.prices = prices
        self.holdings = holdings
        self.deckUses = deckUses
        self.currentStatus = currentStatus
        self.history = history
        self.disagreement = disagreement
    }

    /// A price describes the card, not a particular printing. Blue-Eyes White
    /// Dragon has 78 printings and one figure per source, so a panel showing
    /// both side by side has to say which of them the figure is about.
    public static let priceScopeNotice =
        "I prezzi sono per carta, non per stampa: rarità diverse portano la stessa cifra."

    /// The most recent moment any of the figures was observed, which is what
    /// the panel dates them by. Not the moment the panel opened.
    public var pricesObservedAt: Date? {
        prices.compactMap(\.observedAt).max()
    }

    public var isUntranslated: Bool { text.isFallbackToEnglish }
}
