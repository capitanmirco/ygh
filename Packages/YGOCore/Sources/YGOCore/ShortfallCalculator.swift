/// One card a deck asks for more of than the collection holds.
public struct ShortfallEntry: Hashable, Sendable, Identifiable {
    public let card: CardIdentifier
    public let cardName: String
    /// Copies the deck asks for, across every section.
    public let required: Int
    /// Copies held, across every printing.
    public let owned: Int

    public var id: CardIdentifier { card }
    public var missing: Int { max(0, required - owned) }

    public init(card: CardIdentifier, cardName: String, required: Int, owned: Int) {
        self.card = card
        self.cardName = cardName
        self.required = required
        self.owned = owned
    }

    /// A sentence naming the card and how many are still needed, so that the
    /// interface renders it and a screen reader reads it without either
    /// knowing how the figure was reached.
    public var sentence: String {
        let copies = missing == 1 ? "1 copia" : "\(missing) copie"
        return owned == 0
            ? "\(cardName): ne servono \(copies), non ne hai."
            : "\(cardName): ne servono altre \(copies), ne hai \(owned) su \(required)."
    }
}

/// What a deck still needs before it can be built from the cards on hand.
///
/// Deliberately counts **cards, not limit names**. Deck validation groups
/// copies by limit name, because `Harpie Lady 1`, `2` and `3` share one
/// allowance. Owning three copies of `Harpie Lady 2` does not let anyone play
/// a deck that lists `Harpie Lady 1`: those are different pieces of cardboard,
/// and reusing the validator's tally here would report a deck as buildable
/// when it is not.
///
/// What the two do share, and must agree on, is that copies are summed across
/// every section of a deck and across every printing in a collection.
public enum ShortfallCalculator {
    /// How many copies of each card a deck asks for, counting all three
    /// sections and every printing the deck holds.
    public static func required(in deck: Deck) -> [CardIdentifier: Int] {
        deck.slots.reduce(into: [:]) { totals, slot in
            totals[slot.card, default: 0] += slot.quantity
        }
    }

    /// The cards a deck is short of, worst shortfall first.
    ///
    /// Reads both arguments and mutates nothing: asking what a deck needs must
    /// never change the deck or the collection.
    public static func shortfall(
        deck: Deck,
        names: [CardIdentifier: String],
        owned: [CardIdentifier: Int]
    ) -> [ShortfallEntry] {
        required(in: deck)
            .compactMap { card, required -> ShortfallEntry? in
                let held = owned[card] ?? 0
                guard required > held else { return nil }
                return ShortfallEntry(
                    card: card,
                    name: names[card] ?? "Carta \(card.rawValue)",
                    required: required,
                    owned: held)
            }
            .sorted { lhs, rhs in
                lhs.missing == rhs.missing
                    ? lhs.cardName < rhs.cardName
                    : lhs.missing > rhs.missing
            }
    }
}

extension ShortfallEntry {
    init(card: CardIdentifier, name: String, required: Int, owned: Int) {
        self.init(card: card, cardName: name, required: required, owned: owned)
    }
}
