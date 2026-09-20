import Foundation
import YGOCore

/// Decks and indexes built in memory, because the maths needs neither a
/// database nor a catalog to be checked.
enum Sample {
    static let at = Date(timeIntervalSince1970: 1_758_000_000)

    static func entry(
        _ id: Int,
        name: String? = nil,
        frame: CardFrame = .effect,
        type: String = "Effect Monster",
        level: Int? = 4,
        attribute: CardAttribute? = .dark,
        race: String = "Spellcaster"
    ) -> DeckCardIndex.Entry {
        let resolved = name ?? "Card \(id)"
        return DeckCardIndex.Entry(
            card: CardIdentifier(id), name: resolved, limitName: resolved,
            frame: frame, formats: [.tcg, .goat], banStatus: .unlimited,
            type: type, level: level, attribute: attribute, race: race)
    }

    static func slot(_ card: Int, section: DeckSection = .main,
                     quantity: Int = 1, artwork: Int? = nil) -> DeckSlot {
        DeckSlot(artwork: ArtworkIdentifier(artwork ?? card), card: CardIdentifier(card),
                 section: section, quantity: quantity)
    }

    /// A deck of `size` main-deck cards, holding `copies` of card 1 and
    /// filling the rest with distinct singles.
    static func deck(
        size: Int,
        copies: Int,
        format: CardFormat = .tcg,
        extra: Int = 0
    ) -> (Deck, DeckCardIndex) {
        var slots: [DeckSlot] = []
        var entries: [DeckCardIndex.Entry] = []

        if copies > 0 {
            slots.append(slot(1, quantity: copies))
            entries.append(entry(1, name: "Bersaglio"))
        }
        for filler in 0..<(size - copies) {
            let id = 1_000 + filler
            slots.append(slot(id))
            entries.append(entry(id))
        }
        for extraCard in 0..<extra {
            let id = 5_000 + extraCard
            slots.append(slot(id, section: .extra))
            entries.append(entry(id, frame: .fusion, type: "Fusion Monster", level: 8))
        }

        return (
            Deck(id: 1, name: "Prova", format: format, slots: slots,
                 createdAt: at, updatedAt: at),
            DeckCardIndex(entries: entries))
    }
}
