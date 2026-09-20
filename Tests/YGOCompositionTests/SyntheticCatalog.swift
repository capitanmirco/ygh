import Foundation
import YGOCore
import YGONetworking

/// Builds a catalog the size of the real one.
///
/// The measurements these tests make are meaningless against the 35-card
/// fixture, so the shape is taken from the live dataset and scaled up: 14,566
/// cards, 14,730 artworks, about eight printings each, roughly two thirds of
/// them monsters, and effect text of a realistic length. Nothing is written
/// into the repository; the payload is built in memory and the database lands
/// in a temporary directory.
enum SyntheticCatalog {
    static let cardCount = 14_566
    static let artworkCount = 14_730

    private static let effectText = """
        Once per turn, you can target 1 monster your opponent controls; banish \
        that target until the End Phase, also you cannot Special Summon monsters \
        for the rest of this turn, except from the Extra Deck. If this card is \
        sent to the GY: You can add 1 card that mentions this card from your Deck \
        to your hand, also you take no further actions this turn.
        """

    private static let races = [
        "Dragon", "Spellcaster", "Warrior", "Machine", "Fiend", "Zombie",
        "Aqua", "Beast", "Winged Beast", "Fairy", "Normal", "Continuous",
    ]
    private static let attributes = ["DARK", "LIGHT", "EARTH", "WATER", "FIRE", "WIND"]
    private static let frames = ["effect", "normal", "spell", "trap", "fusion",
                                 "synchro", "xyz", "link", "ritual"]
    private static let formats = ["TCG", "OCG", "Master Duel", "GOAT", "Edison"]
    private static let banStatuses = ["Forbidden", "Limited", "Semi-Limited"]

    static func payload() throws -> [CatalogCardPayload] {
        var cards: [[String: Any]] = []
        cards.reserveCapacity(cardCount)
        var extraArtworks = artworkCount - cardCount

        for index in 0..<cardCount {
            let id = 10_000_000 + index
            let frame = frames[index % frames.count]
            let isMonster = !["spell", "trap"].contains(frame)

            var images: [[String: Any]] = [["id": id]]
            if extraArtworks > 0, index % 90 == 0 {
                images.append(["id": 90_000_000 + index])
                extraArtworks -= 1
            }

            var card: [String: Any] = [
                "id": id,
                "name": "Synthetic Card \(index) of the Eternal Vanguard",
                "type": isMonster ? "Effect Monster" : "Spell Card",
                "humanReadableCardType": isMonster ? "Effect Monster" : "Normal Spell",
                "frameType": frame,
                "desc": effectText,
                "race": races[index % races.count],
                "card_images": images,
                "card_prices": [[
                    "cardmarket_price": "\(Double(index % 400) / 10 + 0.1)",
                    "tcgplayer_price": "\(Double(index % 250) / 10 + 0.2)",
                ]],
                "misc_info": [[
                    "formats": Array(formats.prefix(1 + index % formats.count)),
                    "has_effect": isMonster ? 1 : 0,
                    "tcg_date": "2015-03-\(String(format: "%02d", 1 + index % 28))",
                ]],
            ]

            if index % 3 == 0 {
                card["name_it"] = nil
            }
            if isMonster {
                card["attribute"] = attributes[index % attributes.count]
                card["level"] = 1 + index % 12
                card["atk"] = (index % 40) * 100
                card["def"] = (index % 30) * 100
            }
            if index % 6 == 0 {
                card["archetype"] = "Archetype \(index % 400)"
            }
            // Two per cent of the real pool carries a restriction.
            if index % 50 == 0 {
                card["banlist_info"] = ["ban_tcg": banStatuses[index % banStatuses.count]]
            }
            // The real dataset averages about eight printings per card.
            card["card_sets"] = (0..<8).map { printing in
                [
                    "set_name": "Synthetic Set \(printing)",
                    "set_code": "SY\(printing)-EN\(String(format: "%03d", index % 1000))",
                    "set_rarity": printing % 2 == 0 ? "Common" : "Super Rare",
                    "set_rarity_code": printing % 2 == 0 ? "(C)" : "(SR)",
                    "set_price": "\(Double(index % 90) / 10)",
                ]
            }

            cards.append(card)
        }

        let data = try JSONSerialization.data(withJSONObject: ["data": cards])
        return try YGOProDeckCatalogClient.decodeDataset(data)
    }

    /// The Italian half: roughly three quarters of the pool, as upstream ships.
    static func italianPayload(from english: [CatalogCardPayload]) throws -> [CatalogCardPayload] {
        let translated = english.enumerated().filter { $0.offset % 4 != 0 }
        let cards: [[String: Any]] = translated.map { _, card in
            [
                "id": card.id,
                "name": "Carta Sintetica \(card.id) della Guardia Eterna",
                "type": card.type,
                "humanReadableCardType": card.humanReadableCardType,
                "frameType": card.frameType,
                "desc": "Una volta per turno, puoi scegliere come bersaglio 1 mostro "
                    + "controllato dal tuo avversario; bandisci quel bersaglio fino alla "
                    + "Fine Phase, inoltre non puoi Evocare Specialmente mostri per il "
                    + "resto di questo turno, eccetto dall'Extra Deck.",
                "race": card.race,
                "name_en": card.name,
                "card_images": [["id": card.id]],
                "card_prices": [[:]],
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: ["data": cards])
        return try YGOProDeckCatalogClient.decodeDataset(data)
    }
}
