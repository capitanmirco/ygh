import Foundation
import YGOCore

/// Turns a stored deck back into the formats the rest of the ecosystem reads.
///
/// Export reads each slot's artwork, not its card, so a deck that has been
/// through this application comes out holding the printings the user put in it.
/// Substituting a card's primary artwork would quietly rewrite their collection.
public enum DeckExporter {
    /// A deck flattened into passcodes, copies repeated as the formats expect.
    public static func list(from deck: Deck) -> DeckList {
        var list = DeckList()
        for section in DeckSection.allCases {
            list[section] = deck.slots(in: section)
                .sorted { $0.artwork.rawValue < $1.artwork.rawValue }
                .flatMap { slot in
                    Array(repeating: slot.artwork.rawValue, count: slot.quantity)
                }
        }
        return list
    }

    public static func ydkText(for deck: Deck) -> String {
        YDKFile.write(list(from: deck))
    }

    public static func ydkeLink(for deck: Deck) -> String {
        YDKeCodec.encode(list(from: deck))
    }

    /// Writes a `.ydk` beside whatever the user chose. Legality is not checked:
    /// an unfinished deck is exactly the kind a duelist wants to carry between
    /// machines.
    public static func write(_ deck: Deck, to url: URL) throws {
        try ydkText(for: deck).write(to: url, atomically: true, encoding: .utf8)
    }
}
