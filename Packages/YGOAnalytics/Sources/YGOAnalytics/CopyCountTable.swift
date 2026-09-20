import YGOCore

/// What running one, two or three copies would do.
///
/// The question behind every probability a duelist looks up is really a
/// decision, and a single figure does not answer it. Three rows do.
public struct CopyCountTable: Hashable, Sendable {
    public struct Row: Hashable, Sendable {
        public let copies: Int
        public let atLeastOne: Double
        /// How much this row gains over the one before it. The third copy is
        /// always worth less than the second, and seeing that is the point.
        public let gainOverPrevious: Double

        public var sentence: String {
            let percent = String(format: "%.1f", atLeastOne * 100)
            let gain = String(format: "%+.1f", gainOverPrevious * 100)
            return copies == 1
                ? "1 copia: \(percent)%"
                : "\(copies) copie: \(percent)% (\(gain) punti)"
        }
    }

    public let cardName: String
    public let rows: [Row]
    public let hand: OpeningHand
    public let population: Int

    public init(cardName: String, rows: [Row], hand: OpeningHand, population: Int) {
        self.cardName = cardName
        self.rows = rows
        self.hand = hand
        self.population = population
    }
}

extension Hypergeometric {
    /// The table for a card in a deck, from one copy to `upTo`.
    ///
    /// Built from the same function the single-card figure uses, so the table
    /// cannot drift away from the number shown beside it.
    public static func copyCountTable(
        for card: CardIdentifier,
        in deck: Deck,
        index: DeckCardIndex,
        playingFirst: Bool,
        upTo maximumCopies: Int = 3,
        populationOverride: Int? = nil
    ) -> CopyCountTable {
        let hand = OpeningHand(format: deck.format, playingFirst: playingFirst)
        let population = populationOverride ?? deck.drawablePopulation

        var rows: [CopyCountTable.Row] = []
        var previous = 0.0

        for copies in 1...max(1, maximumCopies) {
            let probability = probabilityOfAtLeast(
                1, population: population, copies: copies, drawn: hand.size)
            rows.append(CopyCountTable.Row(
                copies: copies,
                atLeastOne: probability,
                gainOverPrevious: probability - previous))
            previous = probability
        }

        return CopyCountTable(
            cardName: index[card]?.name ?? "Carta \(card.rawValue)",
            rows: rows, hand: hand, population: population)
    }

    /// The same card at a different deck size, so the cost of the forty-first
    /// card is visible before it is added.
    public static func probabilityAtDeckSize(
        _ population: Int,
        copies: Int,
        hand: OpeningHand
    ) -> Double {
        probabilityOfAtLeast(1, population: population, copies: copies, drawn: hand.size)
    }
}
