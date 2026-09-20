import Foundation
import YGOCore

/// Prices held in memory, because a sum is checkable without a database.
struct StubPriceLookup: PriceLookup {
    var table: [CardIdentifier: [RecordedPrice]] = [:]

    func prices(
        forCards cards: Set<CardIdentifier>
    ) async throws -> [CardIdentifier: [RecordedPrice]] {
        table.filter { cards.contains($0.key) }
    }
}

enum Sample {
    static let observedAt = Date(timeIntervalSince1970: 1_758_000_000)

    static func price(_ source: PriceSource, _ amount: Double) -> RecordedPrice {
        RecordedPrice(
            source: source,
            money: Money(amount: amount, currency: source.currency),
            observedAt: observedAt)
    }

    /// The real shape of the worst case in the user's catalog: Gate Guardian,
    /// €0.02 on Cardmarket and €999.99 on Amazon.
    static let gateGuardian: [RecordedPrice] = [
        price(.cardmarket, 0.02), price(.tcgplayer, 0.22),
        price(.coolstuffinc, 0.79), price(.ebay, 1.58), price(.amazon, 999.99),
    ]

    /// A card the sources broadly agree on.
    static let agreed: [RecordedPrice] = [
        price(.cardmarket, 2.00), price(.tcgplayer, 2.40),
        price(.coolstuffinc, 2.10), price(.ebay, 3.00),
    ]
}
