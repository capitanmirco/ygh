import Foundation
import YGOCore

/// One thing being valued: some copies of a card, and where they sit.
public struct ValuationItem: Hashable, Sendable {
    public let card: CardIdentifier
    public let quantity: Int
    /// For a collection: the printing's rarity. Absent for a deck, and for
    /// copies recorded against no printing.
    public let rarity: String?
    /// For a collection: where the copies are kept. Absent means unfiled.
    public let location: String?

    public init(
        card: CardIdentifier,
        quantity: Int,
        rarity: String? = nil,
        location: String? = nil
    ) {
        self.card = card
        self.quantity = max(0, quantity)
        self.rarity = rarity
        self.location = location
    }
}

/// A figure, and everything a reader needs to know how far to trust it.
///
/// The qualifications are carried by the type rather than added by whoever
/// displays it, so a total cannot be built without them and `R6` cannot be
/// forgotten in one screen and remembered in another.
public struct Valuation: Hashable, Sendable {
    public let total: Money
    public let source: PriceSource
    /// When the prices behind this figure were seen, which is the last catalog
    /// synchronisation. There is no separate price feed.
    public let observedAt: Date?
    public let copiesValued: Int
    /// Copies the chosen source does not price. Excluded from the total rather
    /// than counted as free.
    public let copiesUnpriced: Int
    public let disputedCards: Int

    public init(
        total: Money,
        source: PriceSource,
        observedAt: Date?,
        copiesValued: Int,
        copiesUnpriced: Int,
        disputedCards: Int
    ) {
        self.total = total
        self.source = source
        self.observedAt = observedAt
        self.copiesValued = copiesValued
        self.copiesUnpriced = copiesUnpriced
        self.disputedCards = disputedCards
    }

    public var totalCopies: Int { copiesValued + copiesUnpriced }
    public var isComplete: Bool { copiesUnpriced == 0 }

    /// Why this is an estimate and not an appraisal.
    ///
    /// The source publishes one figure per card rather than one per printing,
    /// so a Secret Rare and a Common of the same card carry the same price.
    /// No amount of care in the arithmetic changes that.
    public var estimateReason: String {
        "\(source.displayName) pubblica un prezzo per carta, non per stampa: "
            + "una Secret Rare e una Common della stessa carta valgono uguale."
    }

    /// A sentence naming the amount, the source and what it covers.
    public var sentence: String {
        var text = "\(total.formatted) su \(source.displayName)"
        text += copiesUnpriced == 0
            ? ", su tutte le \(totalCopies) copie"
            : ", su \(copiesValued) copie di \(totalCopies) (\(copiesUnpriced) senza prezzo)"
        if disputedCards > 0 {
            text += ", \(disputedCards) carte contestate"
        }
        return text + ". Stima, non perizia."
    }
}

/// Sums money over sets of copies.
///
/// A collection, a deck, the cards a deck still needs and the most valuable
/// things held are the same sum over different sets, so there is one function
/// and four callers.
public enum Valuer {
    public static func value(
        _ items: [ValuationItem],
        quotes: [CardIdentifier: PriceQuote],
        source: PriceSource
    ) -> Valuation {
        var cents = 0
        var valued = 0
        var unpriced = 0
        var disputed: Set<CardIdentifier> = []
        var observed: Date?

        for item in items where item.quantity > 0 {
            guard let quote = quotes[item.card], let price = quote.price else {
                unpriced += item.quantity
                continue
            }

            cents += price.cents * item.quantity
            valued += item.quantity
            if quote.isDisputed { disputed.insert(item.card) }
            if let at = quote.observedAt, observed == nil || at > observed! { observed = at }
        }

        return Valuation(
            total: Money(cents: cents, currency: source.currency),
            source: source,
            observedAt: observed,
            copiesValued: valued,
            copiesUnpriced: unpriced,
            disputedCards: disputed.count)
    }

    /// The same sum, split by whatever `key` returns. The parts add up to the
    /// whole because they are the same arithmetic over a partition of it.
    public static func value<Key: Hashable>(
        _ items: [ValuationItem],
        quotes: [CardIdentifier: PriceQuote],
        source: PriceSource,
        groupedBy key: (ValuationItem) -> Key
    ) -> [Key: Valuation] {
        Dictionary(grouping: items, by: key).mapValues {
            value($0, quotes: quotes, source: source)
        }
    }
}

/// A card and what the copies held are worth together.
public struct ValuedCard: Hashable, Sendable, Identifiable {
    public let card: CardIdentifier
    public let cardName: String
    public let copies: Int
    public let unitPrice: Money
    public let totalValue: Money
    public let locations: [String]
    public let isDisputed: Bool

    public var id: CardIdentifier { card }

    public var sentence: String {
        let places = locations.isEmpty ? "non archiviate" : locations.joined(separator: ", ")
        var text = "\(cardName): \(copies)× \(unitPrice.formatted) = \(totalValue.formatted), \(places)"
        if isDisputed { text += ", prezzo contestato" }
        return text + "."
    }
}

extension Valuer {
    /// The cards worth the most, ranked by what the copies held are worth
    /// together rather than by unit price: two at ten beats one at fifteen.
    public static func ranked(
        _ items: [ValuationItem],
        quotes: [CardIdentifier: PriceQuote],
        source: PriceSource,
        limit: Int = 25
    ) -> [ValuedCard] {
        var copiesByCard: [CardIdentifier: Int] = [:]
        var placesByCard: [CardIdentifier: Set<String>] = [:]

        for item in items where item.quantity > 0 {
            copiesByCard[item.card, default: 0] += item.quantity
            if let location = item.location {
                placesByCard[item.card, default: []].insert(location)
            }
        }

        return copiesByCard
            .compactMap { card, copies -> ValuedCard? in
                guard let quote = quotes[card], let price = quote.price else { return nil }
                return ValuedCard(
                    card: card,
                    cardName: quote.cardName,
                    copies: copies,
                    unitPrice: price,
                    totalValue: price.times(copies),
                    locations: (placesByCard[card] ?? []).sorted(),
                    isDisputed: quote.isDisputed)
            }
            .sorted { lhs, rhs in
                lhs.totalValue.cents == rhs.totalValue.cents
                    ? lhs.cardName < rhs.cardName
                    : lhs.totalValue.cents > rhs.totalValue.cents
            }
            .prefix(limit)
            .map { $0 }
    }
}

extension Valuer {
    /// What a deck would cost to build, counting every copy in every section.
    public static func cost(
        of deck: Deck,
        quotes: [CardIdentifier: PriceQuote],
        source: PriceSource
    ) -> Valuation {
        value(items(in: deck), quotes: quotes, source: source)
    }

    /// What finishing a deck would cost, counting only the copies the
    /// collection does not already hold.
    ///
    /// Takes the shortfall `collection-tracker` computed rather than counting
    /// the missing copies again. A second implementation of a proven rule would
    /// eventually disagree with it about a card the user owns.
    public static func completionCost(
        shortfall: [ShortfallEntry],
        quotes: [CardIdentifier: PriceQuote],
        source: PriceSource
    ) -> Valuation {
        value(
            shortfall.map { ValuationItem(card: $0.card, quantity: $0.missing) },
            quotes: quotes, source: source)
    }

    /// A deck's cards ranked by what they contribute to its cost.
    public static func dearestCards(
        in deck: Deck,
        quotes: [CardIdentifier: PriceQuote],
        source: PriceSource,
        limit: Int = 10
    ) -> [ValuedCard] {
        ranked(items(in: deck), quotes: quotes, source: source, limit: limit)
    }

    /// A deck's slots as copies of cards. Sections do not matter to a price:
    /// a side-deck copy costs what a main-deck copy costs.
    static func items(in deck: Deck) -> [ValuationItem] {
        deck.slots.map { ValuationItem(card: $0.card, quantity: $0.quantity) }
    }
}
