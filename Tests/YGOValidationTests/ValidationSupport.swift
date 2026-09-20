import Foundation
import YGOCore

/// Builds decks and indexes without a database, which is the point of keeping
/// the rules free of one.
enum Sample {
    static let at = Date(timeIntervalSince1970: 1_758_000_000)

    static func entry(
        _ id: Int,
        name: String? = nil,
        limitName: String? = nil,
        frame: CardFrame = .effect,
        formats: Set<CardFormat> = [.tcg, .goat],
        ban: BanStatus = .unlimited
    ) -> DeckCardIndex.Entry {
        let resolved = name ?? "Card \(id)"
        return DeckCardIndex.Entry(
            card: CardIdentifier(id),
            name: resolved,
            limitName: limitName ?? resolved,
            frame: frame,
            formats: formats,
            banStatus: ban)
    }

    static func deck(
        format: CardFormat = .tcg,
        _ slots: [DeckSlot]
    ) -> Deck {
        Deck(id: 1, name: "Prova", format: format, slots: slots, createdAt: at, updatedAt: at)
    }

    /// `count` distinct cards, one copy each, all in one section.
    static func filler(
        _ count: Int,
        section: DeckSection = .main,
        startingAt first: Int = 1_000
    ) -> (slots: [DeckSlot], entries: [DeckCardIndex.Entry]) {
        let frame: CardFrame = section == .extra ? .fusion : .effect
        let ids = (0..<count).map { first + $0 }
        return (
            ids.map { DeckSlot(artwork: ArtworkIdentifier($0), card: CardIdentifier($0),
                               section: section, quantity: 1) },
            ids.map { entry($0, frame: frame) })
    }

    static func slot(
        _ id: Int,
        section: DeckSection = .main,
        quantity: Int = 1,
        artwork: Int? = nil
    ) -> DeckSlot {
        DeckSlot(artwork: ArtworkIdentifier(artwork ?? id), card: CardIdentifier(id),
                 section: section, quantity: quantity)
    }
}
