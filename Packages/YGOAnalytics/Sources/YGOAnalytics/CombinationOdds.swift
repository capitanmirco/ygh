import YGOCore

/// A piece of a combination: a card, and how many copies of it are wanted.
public struct ComboPiece: Hashable, Sendable {
    public let card: CardIdentifier
    public let cardName: String
    /// Copies the deck holds in its main section.
    public let copies: Int
    /// Copies the hand must contain for the combination to work.
    public let required: Int

    public init(card: CardIdentifier, cardName: String, copies: Int, required: Int = 1) {
        self.card = card
        self.cardName = cardName
        self.copies = copies
        self.required = max(1, required)
    }
}

/// The odds of a combination arriving whole.
public struct ComboOdds: Hashable, Sendable {
    public let pieces: [ComboPiece]
    public let probability: Double
    public let hand: OpeningHand

    public init(pieces: [ComboPiece], probability: Double, hand: OpeningHand) {
        self.pieces = pieces
        self.probability = probability
        self.hand = hand
    }

    public var sentence: String {
        let names = pieces.map(\.cardName).joined(separator: " + ")
        let percent = String(format: "%.1f", probability * 100)
        return "\(names): \(percent)% di aprirle insieme (\(hand.description))."
    }
}

extension Hypergeometric {
    /// The chance of drawing at least the required copies of every piece.
    ///
    /// Enumerated directly rather than by inclusion-exclusion. Inclusion-
    /// exclusion is shorter for "at least one of each" but does not extend to
    /// a piece that needs two copies, and that is a question duelists ask.
    /// With a hand of six the enumeration has a few dozen terms.
    ///
    /// A combination is far rarer than its parts: three copies each of two
    /// cards open together in 9.8% of five-card hands, against 33.8% for
    /// either alone.
    public static func probabilityOfCombination(
        _ pieces: [(copies: Int, required: Int)],
        population: Int,
        drawn: Int
    ) -> Double {
        guard population > 0, drawn > 0, !pieces.isEmpty else { return 0 }
        // A piece the deck cannot supply makes the whole combination impossible.
        guard pieces.allSatisfy({ $0.copies >= $0.required && $0.required > 0 })
        else { return 0 }

        let named = pieces.reduce(0) { $0 + $1.copies }
        guard named <= population else { return 0 }

        let drawn = min(drawn, population)
        // A combination is asked about a real deck, so the exact path always
        // applies; an input outside that domain gives up rather than traps.
        guard let total = binomial(population, choose: drawn), total > 0 else { return 0 }

        var favourable = 0

        /// Walks the pieces, choosing how many copies of each the hand holds.
        func walk(_ index: Int, drawnSoFar: Int, ways: Int) {
            guard index < pieces.count else {
                // The rest of the hand comes from the cards nobody named.
                let remaining = drawn - drawnSoFar
                guard let fillers = binomial(population - named, choose: remaining) else { return }
                favourable += ways * fillers
                return
            }

            let piece = pieces[index]
            let mostFromThisPiece = min(piece.copies, drawn - drawnSoFar)
            guard piece.required <= mostFromThisPiece else { return }

            for count in piece.required...mostFromThisPiece {
                guard let waysForCount = binomial(piece.copies, choose: count) else { continue }
                walk(index + 1,
                     drawnSoFar: drawnSoFar + count,
                     ways: ways * waysForCount)
            }
        }

        walk(0, drawnSoFar: 0, ways: 1)
        return max(0, min(1, Double(favourable) / Double(total)))
    }

    /// The odds of a combination in a deck, as the interface shows them.
    public static func odds(
        forCombination requirements: [(card: CardIdentifier, required: Int)],
        in deck: Deck,
        index: DeckCardIndex,
        playingFirst: Bool
    ) -> ComboOdds {
        let hand = OpeningHand(format: deck.format, playingFirst: playingFirst)

        let pieces = requirements.map { requirement in
            ComboPiece(
                card: requirement.card,
                cardName: index[requirement.card]?.name ?? "Carta \(requirement.card.rawValue)",
                copies: deck.mainDeckCopies(of: requirement.card),
                required: requirement.required)
        }

        let probability = probabilityOfCombination(
            pieces.map { (copies: $0.copies, required: $0.required) },
            population: deck.drawablePopulation,
            drawn: hand.size)

        return ComboOdds(pieces: pieces, probability: probability, hand: hand)
    }
}
