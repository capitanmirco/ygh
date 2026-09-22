import YGOCore

public extension AppSection {
    /// What the section is called on screen. The stored raw value is a stable
    /// key, so a reworded label cannot invalidate a saved preference.
    var title: String {
        switch self {
        case .catalog: "Catalogo"
        case .decks: "Mazzi"
        case .collection: "Collezione"
        case .analytics: "Statistiche"
        case .banlist: "Banlist"
        case .value: "Valore"
        }
    }

    /// The symbol the sidebar draws beside it.
    var symbol: String {
        switch self {
        case .catalog: "square.grid.2x2"
        case .decks: "rectangle.stack"
        case .collection: "tray.full"
        case .analytics: "chart.bar"
        case .banlist: "hand.raised"
        case .value: "eurosign.circle"
        }
    }
}
