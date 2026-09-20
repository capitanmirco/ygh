import Foundation
import YGOCore

/// Everything known about one card's price.
///
/// Carries every source rather than only the chosen one, because the spread is
/// the most useful thing the data has to say: for cards priced by three or more
/// sources, the median ratio between highest and lowest is 74, and the worst is
/// 50,000.
public struct PriceQuote: Hashable, Sendable {
    public let card: CardIdentifier
    public let cardName: String
    public let chosenSource: PriceSource
    /// Absent when the chosen source does not price this card. Absent is not
    /// zero: 289 of 14,566 cards carry no price from any source.
    public let price: Money?
    public let allSources: [RecordedPrice]
    public let observedAt: Date?

    public init(
        card: CardIdentifier,
        cardName: String,
        chosenSource: PriceSource,
        allSources: [RecordedPrice]
    ) {
        self.card = card
        self.cardName = cardName
        self.chosenSource = chosenSource
        self.allSources = allSources.sorted { $0.source.rawValue < $1.source.rawValue }

        let chosen = allSources.first { $0.source == chosenSource }
        self.price = chosen?.money
        self.observedAt = chosen?.observedAt ?? allSources.first?.observedAt
    }

    public var isPriced: Bool { price != nil }

    /// How far the sources disagree, as the ratio between the highest and the
    /// lowest figure either side of the chosen one.
    ///
    /// A card is disputed when another source exceeds the chosen one tenfold.
    /// Its chosen-source price still counts in every total: deciding which of
    /// two figures is wrong would be inventing data.
    public static let disputeFactor = 10.0

    public var dispute: PriceDispute? {
        guard let price, price.cents > 0 else { return nil }

        let worst = allSources
            .filter { $0.source != chosenSource }
            .map { (record: $0, ratio: Double($0.money.cents) / Double(price.cents)) }
            .filter { $0.ratio >= Self.disputeFactor }
            .max { $0.ratio < $1.ratio }

        guard let worst else { return nil }
        return PriceDispute(
            disagreeingSource: worst.record.source,
            disagreeingPrice: worst.record.money,
            chosenPrice: price,
            ratio: worst.ratio)
    }

    public var isDisputed: Bool { dispute != nil }

    /// A sentence naming the card, the amount and the source.
    public var sentence: String {
        guard let price else {
            return "\(cardName): nessun prezzo su \(chosenSource.displayName)."
        }
        var text = "\(cardName): \(price.formatted) su \(chosenSource.displayName)"
        if let dispute { text += ", ma \(dispute.summary)" }
        return text + "."
    }
}

/// One source disagreeing sharply with the chosen one.
public struct PriceDispute: Hashable, Sendable {
    public let disagreeingSource: PriceSource
    public let disagreeingPrice: Money
    public let chosenPrice: Money
    public let ratio: Double

    public var summary: String {
        let times = ratio >= 100
            ? String(format: "%.0f", ratio)
            : String(format: "%.1f", ratio)
        return "\(disagreeingSource.displayName) dice \(disagreeingPrice.formatted), "
            + "\(times) volte tanto"
    }
}

/// Builds quotes for a set of cards from one lookup.
public struct PriceQuoter: Sendable {
    private let lookup: any PriceLookup
    public let source: PriceSource

    public init(lookup: any PriceLookup, source: PriceSource = .default) {
        self.lookup = lookup
        self.source = source
    }

    public func quotes(
        for cards: Set<CardIdentifier>,
        names: [CardIdentifier: String] = [:]
    ) async throws -> [CardIdentifier: PriceQuote] {
        let prices = try await lookup.prices(forCards: cards)

        return cards.reduce(into: [:]) { result, card in
            result[card] = PriceQuote(
                card: card,
                cardName: names[card] ?? "Carta \(card.rawValue)",
                chosenSource: source,
                allSources: prices[card] ?? [])
        }
    }
}
