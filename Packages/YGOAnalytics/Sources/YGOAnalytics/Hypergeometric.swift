import YGOCore

/// Exact opening-hand probabilities.
///
/// Every binomial coefficient this needs has `k ≤ 6`, because an opening hand
/// is five or six cards. The largest one a sixty-card deck can produce is
/// `C(60, 6) = 50,063,860`, eleven orders of magnitude below `Int` capacity.
///
/// So the coefficients are exact integers and the probability is one division
/// at the end. There is no overflow to guard, no logarithms, and no rounding
/// accumulating through a sum: a test can assert a figure to as many decimals
/// as it likes.
///
/// A general hypergeometric library must reach for log-gamma, because a
/// general `k` can be half the population and `C(60, 30)` is 1.18 × 10¹⁷.
/// This one never needs that. Converting it to floating point would trade an
/// exact answer for nothing.
public enum Hypergeometric {
    /// `C(n, k)` for the small `k` an opening hand produces, or `nil` when it
    /// would not fit in an `Int`.
    ///
    /// Multiplicative rather than factorial: the running value is the true
    /// binomial at every step, so nothing large is formed and divided back down.
    ///
    /// It returns an optional rather than trapping because it is public. Inside
    /// this feature `k` never exceeds six and the result never approaches the
    /// ceiling, but a total function cannot be crashed by a caller who passes
    /// something else.
    public static func binomial(_ n: Int, choose k: Int) -> Int? {
        guard k >= 0, k <= n, n >= 0 else { return 0 }
        let k = min(k, n - k)
        var result = 1
        for step in 0..<k {
            let (multiplied, overflowed) = result.multipliedReportingOverflow(by: n - step)
            guard !overflowed else { return nil }
            result = multiplied / (step + 1)
        }
        return result
    }

    /// The same coefficient in floating point, for the inputs the exact path
    /// cannot hold.
    ///
    /// Never reached by a real deck: an opening hand caps `k` at six, and
    /// `C(60, 6)` is fifty million. It exists so the function is total.
    static func binomialAsDouble(_ n: Int, choose k: Int) -> Double {
        guard k >= 0, k <= n, n >= 0 else { return 0 }
        let k = min(k, n - k)
        var result = 1.0
        for step in 0..<k {
            result = result * Double(n - step) / Double(step + 1)
        }
        return result
    }

    /// The chance of drawing exactly `successes` copies.
    ///
    /// - Parameters:
    ///   - population: cards in the main section.
    ///   - copies: copies of the card in it.
    ///   - drawn: cards in the opening hand.
    public static func probabilityOfExactly(
        _ successes: Int,
        population: Int,
        copies: Int,
        drawn: Int
    ) -> Double {
        guard population > 0, drawn > 0, copies >= 0 else { return 0 }
        // A hand larger than the deck draws the whole deck.
        let drawn = min(drawn, population)
        guard successes >= 0, successes <= copies, successes <= drawn else { return 0 }

        // The exact path, which is the one a real deck always takes.
        if let chosenCopies = binomial(copies, choose: successes),
           let chosenOthers = binomial(population - copies, choose: drawn - successes),
           let total = binomial(population, choose: drawn),
           total > 0,
           case let (favourable, overflowed) =
               chosenCopies.multipliedReportingOverflow(by: chosenOthers),
           !overflowed {
            return Double(favourable) / Double(total)
        }

        // Out of the domain this feature works in, so exactness is not on
        // offer; being finite and in range still is.
        let total = binomialAsDouble(population, choose: drawn)
        guard total > 0, total.isFinite else { return 0 }
        let favourable = binomialAsDouble(copies, choose: successes)
            * binomialAsDouble(population - copies, choose: drawn - successes)
        guard favourable.isFinite else { return 0 }
        return max(0, min(1, favourable / total))
    }

    /// The chance of drawing at least `successes` copies.
    ///
    /// Computed as one minus the chance of drawing fewer, which is the shorter
    /// sum whenever the threshold is low, and low is the case duelists ask
    /// about.
    public static func probabilityOfAtLeast(
        _ successes: Int,
        population: Int,
        copies: Int,
        drawn: Int
    ) -> Double {
        guard successes > 0 else { return copies > 0 ? 1 : 0 }
        guard copies > 0, population > 0 else { return 0 }
        // Drawing the whole deck draws every copy of everything in it.
        if drawn >= population { return successes <= copies ? 1 : 0 }
        guard successes <= copies else { return 0 }

        let shortfall = (0..<successes).reduce(0.0) { total, count in
            total + probabilityOfExactly(
                count, population: population, copies: copies, drawn: drawn)
        }
        return max(0, min(1, 1 - shortfall))
    }
}

/// A probability, and what it assumed.
///
/// The hand size travels with the figure because a reader cannot otherwise
/// tell a GOAT calculation from a TCG one, and they differ by 5.7 points.
public struct DrawOdds: Hashable, Sendable {
    public let card: CardIdentifier
    public let cardName: String
    public let copies: Int
    /// Index `i` is the chance of drawing at least `i + 1` copies.
    public let atLeast: [Double]
    public let hand: OpeningHand

    public init(
        card: CardIdentifier,
        cardName: String,
        copies: Int,
        atLeast: [Double],
        hand: OpeningHand
    ) {
        self.card = card
        self.cardName = cardName
        self.copies = copies
        self.atLeast = atLeast
        self.hand = hand
    }

    public var atLeastOne: Double { atLeast.first ?? 0 }

    /// A sentence naming the card, the chance and the hand it assumed.
    public var sentence: String {
        let percent = String(format: "%.1f", atLeastOne * 100)
        return "\(cardName): \(percent)% di aprirla (\(hand.description))."
    }
}

extension Deck {
    /// Cards the opening hand is drawn from. The extra and side sections are
    /// not part of it.
    public var drawablePopulation: Int { count(in: .main) }

    /// Copies of a card in the main section, across every printing.
    public func mainDeckCopies(of card: CardIdentifier) -> Int {
        slots(in: .main).filter { $0.card == card }.reduce(0) { $0 + $1.quantity }
    }
}

extension Hypergeometric {
    /// The odds of opening a card in a deck, as the interface shows them.
    public static func odds(
        for card: CardIdentifier,
        in deck: Deck,
        index: DeckCardIndex,
        playingFirst: Bool
    ) -> DrawOdds {
        let hand = OpeningHand(format: deck.format, playingFirst: playingFirst)
        let copies = deck.mainDeckCopies(of: card)
        let population = deck.drawablePopulation

        let atLeast = (1...max(1, copies)).map { threshold in
            probabilityOfAtLeast(threshold, population: population,
                                 copies: copies, drawn: hand.size)
        }

        return DrawOdds(
            card: card,
            cardName: index[card]?.name ?? "Carta \(card.rawValue)",
            copies: copies,
            atLeast: copies > 0 ? atLeast : [0],
            hand: hand)
    }
}
