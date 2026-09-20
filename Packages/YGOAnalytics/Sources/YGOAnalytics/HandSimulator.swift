import YGOCore

/// A generator that can be seeded.
///
/// Swift's own cannot be, so a simulated figure could never be reproduced,
/// compared between runs, or asserted in a test. SplitMix64 is short, is
/// specified exactly, and gives the same sequence on every machine.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Deals real hands from a deck's main section.
///
/// A percentage tells a duelist how often something happens; a hand shows them
/// what it looks like. Both are worth having, and neither replaces the other.
public struct HandSimulator: Sendable {
    /// Every drawable card, one entry per copy.
    private let cards: [CardIdentifier]
    public let hand: OpeningHand

    public init(deck: Deck, playingFirst: Bool) {
        cards = deck.slots(in: .main).flatMap { slot in
            Array(repeating: slot.card, count: slot.quantity)
        }
        hand = OpeningHand(format: deck.format, playingFirst: playingFirst)
    }

    public var population: Int { cards.count }

    /// One shuffled deck, mid-game: what has been drawn and what is left.
    public struct Deal: Sendable {
        public private(set) var drawn: [CardIdentifier]
        private var remaining: [CardIdentifier]

        init(shuffled: [CardIdentifier], openingSize: Int) {
            let opening = min(openingSize, shuffled.count)
            drawn = Array(shuffled.prefix(opening))
            remaining = Array(shuffled.dropFirst(opening))
        }

        public var remainingCount: Int { remaining.count }

        /// Takes the next card off what is left, or nothing if the deck is out.
        @discardableResult
        public mutating func draw() -> CardIdentifier? {
            guard !remaining.isEmpty else { return nil }
            let card = remaining.removeFirst()
            drawn.append(card)
            return card
        }

        public func copies(of card: CardIdentifier) -> Int {
            drawn.filter { $0 == card }.count
        }

        public func holds(_ card: CardIdentifier) -> Bool {
            drawn.contains(card)
        }
    }

    /// Deals one opening hand.
    public func deal(using generator: inout some RandomNumberGenerator) -> Deal {
        Deal(shuffled: cards.shuffled(using: &generator), openingSize: hand.size)
    }

    /// Deals from a seed, so the same seed always gives the same hand.
    public func deal(seed: UInt64) -> Deal {
        var generator = SplitMix64(seed: seed)
        return deal(using: &generator)
    }
}

/// A figure measured by dealing hands rather than computed exactly.
///
/// Carries its sample count, because a share measured over a hundred hands and
/// one measured over a hundred thousand are not the same claim, and nothing in
/// the number itself says which it is.
public struct SimulatedOdds: Hashable, Sendable {
    public let share: Double
    public let hands: Int
    public let hand: OpeningHand

    public init(share: Double, hands: Int, hand: OpeningHand) {
        self.share = share
        self.hands = hands
        self.hand = hand
    }

    /// Roughly how far the true figure may lie from this one: the standard
    /// error of a proportion, doubled.
    public var margin: Double {
        guard hands > 0 else { return 1 }
        return 2 * (share * (1 - share) / Double(hands)).squareRoot()
    }

    public var sentence: String {
        let percent = String(format: "%.1f", share * 100)
        return "\(percent)% su \(hands) mani simulate (\(hand.description))."
    }
}

extension HandSimulator {
    /// Deals `hands` hands and reports the share that met `condition`.
    ///
    /// For anything the closed form covers, the closed form is used instead.
    /// This exists for conditions it does not cover, and for showing a duelist
    /// that a percentage is made of hands.
    public func measure(
        hands: Int,
        seed: UInt64 = 0,
        condition: (Deal) -> Bool
    ) -> SimulatedOdds {
        guard hands > 0 else {
            return SimulatedOdds(share: 0, hands: 0, hand: hand)
        }

        var generator = SplitMix64(seed: seed)
        var met = 0
        for _ in 0..<hands where condition(deal(using: &generator)) {
            met += 1
        }

        return SimulatedOdds(
            share: Double(met) / Double(hands), hands: hands, hand: hand)
    }
}
