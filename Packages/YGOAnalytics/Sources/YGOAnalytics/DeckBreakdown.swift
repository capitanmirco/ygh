import YGOCore

/// The shape of a deck, counted from its own cards.
///
/// One pass over the slots accumulating into dictionaries. There is no chart
/// model and no series type: the view groups what it is given, and a figure
/// nobody displays costs nothing to have computed.
public struct DeckBreakdown: Hashable, Sendable {
    /// Monsters, spells and traps. Keyed by the broad kind rather than by the
    /// catalog's full wording, because "Normal Spell" and "Quick-Play Spell"
    /// are both spells when you are counting a deck's shape.
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case monster, spell, trap, other

        public var italianName: String {
            switch self {
            case .monster: "Mostri"
            case .spell: "Magie"
            case .trap: "Trappole"
            case .other: "Altro"
            }
        }
    }

    public let section: DeckSection
    public let totalCards: Int
    public let byKind: [Kind: Int]
    /// Monsters only. Cards with no level - spells, traps and links - are
    /// absent rather than counted under zero.
    public let byLevel: [Int: Int]
    public let byAttribute: [CardAttribute: Int]
    public let byRace: [String: Int]

    public init(deck: Deck, section: DeckSection, index: DeckCardIndex) {
        self.section = section

        var total = 0
        var kinds: [Kind: Int] = [:]
        var levels: [Int: Int] = [:]
        var attributes: [CardAttribute: Int] = [:]
        var races: [String: Int] = [:]

        for slot in deck.slots(in: section) {
            // Copies count, not distinct cards: three of one monster are three
            // cards in its level, which is what a curve is about.
            let copies = slot.quantity
            total += copies

            guard let entry = index[slot.card] else {
                kinds[.other, default: 0] += copies
                continue
            }

            kinds[Self.kind(of: entry), default: 0] += copies
            if let level = entry.level { levels[level, default: 0] += copies }
            if let attribute = entry.attribute { attributes[attribute, default: 0] += copies }
            if !entry.race.isEmpty { races[entry.race, default: 0] += copies }
        }

        self.totalCards = total
        self.byKind = kinds
        self.byLevel = levels
        self.byAttribute = attributes
        self.byRace = races
    }

    /// The catalog names many kinds of spell and trap; the shape of a deck
    /// only cares which of the three a card is.
    static func kind(of entry: DeckCardIndex.Entry) -> Kind {
        switch entry.frame {
        case .spell: .spell
        case .trap: .trap
        case .token, .skill: .other
        default: .monster
        }
    }

    public var monsterCount: Int { byKind[.monster] ?? 0 }
    public var spellCount: Int { byKind[.spell] ?? 0 }
    public var trapCount: Int { byKind[.trap] ?? 0 }

    /// The level curve, lowest first, for drawing.
    public var levelCurve: [(level: Int, count: Int)] {
        byLevel.sorted { $0.key < $1.key }.map { (level: $0.key, count: $0.value) }
    }
}

extension Deck {
    public func breakdown(of section: DeckSection, using index: DeckCardIndex) -> DeckBreakdown {
        DeckBreakdown(deck: self, section: section, index: index)
    }
}
