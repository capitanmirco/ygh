import Foundation

/// The currency a figure is published in.
///
/// Never converted. Cardmarket publishes in euro and TCGplayer in dollars, and
/// the application has no rate it could date or defend, so it reports what the
/// source said.
public enum Currency: String, Hashable, Sendable, Codable, CaseIterable {
    case eur = "EUR"
    case usd = "USD"

    public var symbol: String {
        switch self {
        case .eur: "€"
        case .usd: "$"
        }
    }
}

/// An amount of money, held as whole cents.
///
/// Summing prices as `Double` accumulates error: ten thousand additions of
/// `0.89` gives `8900.000000000853`. That vanishes when rounded for display,
/// which is exactly what makes it the kind of thing nobody notices going
/// wrong, and money is where a reader trusts the last digit.
///
/// Two amounts in different currencies cannot be added. The type refuses it
/// rather than a comment asking a reviewer to notice.
public struct Money: Hashable, Sendable {
    public let cents: Int
    public let currency: Currency

    public init(cents: Int, currency: Currency) {
        self.cents = cents
        self.currency = currency
    }

    /// Rounds a published figure to the nearest cent on the way in, which is
    /// the only place rounding happens.
    public init(amount: Double, currency: Currency) {
        self.cents = Int((amount * 100).rounded())
        self.currency = currency
    }

    public static func zero(_ currency: Currency) -> Money {
        Money(cents: 0, currency: currency)
    }

    public var amount: Double { Double(cents) / 100 }

    public var formatted: String {
        String(format: "%@%.2f", currency.symbol, amount)
    }

    /// Adds two amounts, or returns `nil` when their currencies differ.
    ///
    /// A total in no currency is worse than no total, so this cannot silently
    /// produce one.
    public func adding(_ other: Money) -> Money? {
        guard currency == other.currency else { return nil }
        return Money(cents: cents + other.cents, currency: currency)
    }

    public func times(_ quantity: Int) -> Money {
        Money(cents: cents * max(0, quantity), currency: currency)
    }

    public func subtracting(_ other: Money) -> Money? {
        guard currency == other.currency else { return nil }
        return Money(cents: cents - other.cents, currency: currency)
    }
}

extension Money: Comparable {
    /// Amounts in different currencies are not ordered relative to one another,
    /// so the comparison falls back to the currency's own order to stay a
    /// strict weak ordering rather than claiming a conversion.
    public static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.currency == rhs.currency
            ? lhs.cents < rhs.cents
            : lhs.currency.rawValue < rhs.currency.rawValue
    }
}

extension Sequence where Element == Money {
    /// Sums amounts sharing one currency, or returns `nil` if they do not.
    public func total(in currency: Currency) -> Money? {
        var cents = 0
        for money in self {
            guard money.currency == currency else { return nil }
            cents += money.cents
        }
        return Money(cents: cents, currency: currency)
    }
}

/// Where a price came from.
public enum PriceSource: String, Hashable, Sendable, Codable, CaseIterable {
    case cardmarket, tcgplayer, ebay, amazon, coolstuffinc

    public var currency: Currency {
        switch self {
        case .cardmarket: .eur
        case .tcgplayer, .ebay, .amazon, .coolstuffinc: .usd
        }
    }

    /// Whether this source publishes what sellers ask rather than what cards
    /// change hands for.
    ///
    /// Not decoration. Measured against the user's own catalog, eBay exceeds
    /// Cardmarket tenfold on 7,096 of 12,069 cards and Amazon on 4,208 of
    /// 11,761, while TCGplayer does so on 289 of 13,949. Recording it in the
    /// type is what stops a later reader adding all five to an average.
    public var carriesAskingPrices: Bool {
        switch self {
        case .ebay, .amazon: true
        case .cardmarket, .tcgplayer, .coolstuffinc: false
        }
    }

    public var displayName: String {
        switch self {
        case .cardmarket: "Cardmarket"
        case .tcgplayer: "TCGplayer"
        case .ebay: "eBay"
        case .amazon: "Amazon"
        case .coolstuffinc: "CoolStuffInc"
        }
    }

    /// The European market, which is where the user buys. A default, not a
    /// judgement about which marketplace is correct.
    public static let `default`: PriceSource = .cardmarket
}

/// A price as it was recorded, with when it was seen.
public struct RecordedPrice: Hashable, Sendable {
    public let source: PriceSource
    public let money: Money
    public let observedAt: Date

    public init(source: PriceSource, money: Money, observedAt: Date) {
        self.source = source
        self.money = money
        self.observedAt = observedAt
    }
}

/// Supplies prices for a set of cards.
///
/// One call for a whole collection rather than one per card, which is what
/// keeps a ten-thousand-copy valuation a matter of arithmetic over rows
/// already in memory.
public protocol PriceLookup: Sendable {
    func prices(
        forCards cards: Set<CardIdentifier>
    ) async throws -> [CardIdentifier: [RecordedPrice]]
}
