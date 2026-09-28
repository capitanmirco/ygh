import YGOCore

/// What the "Cosa manca" panel says, as one value.
///
/// Every sentence the panel can draw is a case here, so a state nobody
/// modelled cannot reach the screen. "Nothing to buy" is only `.satisfied`,
/// and only a computation that read the deck and the collection and found
/// nothing missing produces it. The panel used to draw an empty list as that
/// sentence, with no deck chosen at all.
public enum ShortfallReport: Hashable, Sendable {
    /// The library holds no deck, so there is nothing to compare against.
    case noDecks
    /// Decks exist and none is chosen yet.
    case chooseADeck
    /// A read failed. The deck's name when it is known.
    case unavailable(deckName: String?)
    /// The chosen deck can be built from the cards on hand.
    case satisfied(deckName: String)
    /// What the chosen deck still needs, worst shortfall first.
    case missing(deckName: String, entries: [ShortfallEntry])

    /// The deck the report is about, when there is one.
    public var deckName: String? {
        switch self {
        case .noDecks, .chooseADeck: nil
        case .unavailable(let name): name
        case .satisfied(let name), .missing(let name, _): name
        }
    }

    /// The cards still needed. Empty in every case but `.missing`.
    public var entries: [ShortfallEntry] {
        if case .missing(_, let entries) = self { entries } else { [] }
    }

    /// The panel's first line, and what a screen reader says first.
    public var headline: String {
        switch self {
        case .noDecks:
            "Nessun mazzo salvato: non c'è niente da confrontare con la collezione."
        case .chooseADeck:
            "Scegli un mazzo per sapere cosa manca."
        case .unavailable(let name):
            "Non riesco a leggere \(name ?? "il mazzo") o la collezione: "
                + "la risposta non è disponibile."
        case .satisfied(let name):
            "Niente da comprare per \(name)."
        case .missing(let name, let entries):
            "Per \(name) mancano \(Self.count(entries.reduce(0) { $0 + $1.missing }, "copia", "copie")) "
                + "di \(Self.count(entries.count, "carta", "carte"))."
        }
    }

    private static func count(_ value: Int, _ one: String, _ many: String) -> String {
        value == 1 ? "1 \(one)" : "\(value) \(many)"
    }
}
