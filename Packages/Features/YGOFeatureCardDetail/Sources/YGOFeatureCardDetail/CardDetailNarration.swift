import Foundation
import YGOCore

/// The sentences the panel prints and reads aloud.
///
/// Kept apart from the view so that what a screen reader hears is the same
/// string the eye reads, and so both can be proven without rendering anything.
/// Every one of them names what the figure is and where it came from: a bare
/// "2,89 €" tells a listener nothing.
public enum CardDetailNarration {
    public static func price(_ line: CardPriceLine) -> String {
        guard let money = line.money else {
            return "\(line.source.displayName): nessun prezzo disponibile"
        }
        return "\(line.source.displayName): \(money.formatted)"
    }

    public static func release(_ release: CardRelease) -> String {
        switch release {
        case .unknown:
            "Data di uscita sconosciuta"
        case let .known(tcg, ocg):
            [tcg.map { "Uscita TCG \($0)" }, ocg.map { "Uscita OCG \($0)" }]
                .compactMap { $0 }
                .joined(separator: ", ")
        }
    }

    public static func status(_ status: BanStatus) -> String {
        switch status {
        case .forbidden: "Vietata"
        case .limited: "Limitata"
        case .semiLimited: "Semi-limitata"
        case .unlimited: "Illimitata"
        }
    }

    public static func change(_ change: BanlistChangeNarration) -> String {
        "Il \(change.date) è passata da \(status(change.from)) a \(status(change.to))"
    }

    public static func holding(_ holding: CardHolding) -> String {
        "\(holding.quantity) copie in \(holding.locationName)"
    }

    public static func deckUse(_ use: DeckUse) -> String {
        "\(use.deckName), \(sectionName(use.section)), \(use.quantity) copie"
    }

    public static func printing(_ printing: CardPrinting) -> String {
        "\(printing.setName), codice \(printing.setCode), rarità \(printing.rarity)"
    }

    public static func disagreement(_ disagreement: BanlistDisagreement) -> String {
        "Le due fonti non concordano: il catalogo dice \(status(disagreement.catalogStatus)), "
            + "\(disagreement.historySource) dice \(status(disagreement.historyStatus)) "
            + "dal \(disagreement.historyEffectiveDate)."
    }

    public static func sectionName(_ section: DeckSection) -> String {
        switch section {
        case .main: "Main Deck"
        case .extra: "Extra Deck"
        case .side: "Side Deck"
        }
    }
}

/// A status change reduced to what a sentence needs.
public struct BanlistChangeNarration: Hashable, Sendable {
    public let date: String
    public let from: BanStatus
    public let to: BanStatus

    public init(date: String, from: BanStatus, to: BanStatus) {
        self.date = date
        self.from = from
        self.to = to
    }
}

/// The parts of the panel a keyboard moves between, in the order it moves.
public enum CardDetailFocusRegion: String, Hashable, Sendable, CaseIterable {
    case artwork
    case effect
    case release
    case banlist
    case printings
    case prices
    case holdings
    case decks

    public var title: String {
        switch self {
        case .artwork: "Illustrazione"
        case .effect: "Effetto"
        case .release: "Uscita"
        case .banlist: "Banlist"
        case .printings: "Stampe"
        case .prices: "Prezzi"
        case .holdings: "Le tue copie"
        case .decks: "Nei tuoi mazzi"
        }
    }
}
