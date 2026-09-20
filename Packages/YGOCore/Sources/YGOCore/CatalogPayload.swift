/// The ingestion contract between whatever fetches the catalog and whatever
/// stores it.
///
/// These types live in `YGOCore` so that the networking module can produce them
/// and the persistence module can consume them without either depending on the
/// other. They mirror the upstream wire format, including its spellings, and
/// are deliberately forgiving: every field the upstream source omits for some
/// cards is optional here.
///
/// Field obligations were taken from the live dataset rather than assumed.
/// Present for every one of the 14,566 cards: `id`, `name`, `type`,
/// `humanReadableCardType`, `frameType`, `desc`, `race`, `card_images`,
/// `card_prices`, `misc_info`. Present for fewer: `card_sets` (96%),
/// `atk`/`def`/`level`/`attribute` (64%), `banlist_info` (2%).
public struct CatalogCardPayload: Hashable, Sendable, Codable {
    public let id: Int
    public let name: String
    public let type: String
    public let humanReadableCardType: String
    public let frameType: String
    public let desc: String
    public let race: String

    /// Only the localised responses carry this; it is how a translated record
    /// is matched back to its English original when identifiers are not used.
    public let nameEn: String?

    public let archetype: String?
    public let attribute: String?
    public let level: Int?
    public let atk: Int?
    public let def: Int?
    public let linkValue: Int?
    public let linkMarkers: [String]?
    public let pendulumScale: Int?

    public let cardSets: [CardSetPayload]?
    public let cardImages: [CardImagePayload]
    public let cardPrices: [CardPricePayload]
    public let banlistInfo: BanlistPayload?
    public let miscInfo: [MiscInfoPayload]?

    enum CodingKeys: String, CodingKey {
        case id, name, type, humanReadableCardType, frameType, desc, race
        case archetype, attribute, level, atk, def
        case nameEn = "name_en"
        case linkValue = "linkval"
        case linkMarkers = "linkmarkers"
        case pendulumScale = "scale"
        case cardSets = "card_sets"
        case cardImages = "card_images"
        case cardPrices = "card_prices"
        case banlistInfo = "banlist_info"
        case miscInfo = "misc_info"
    }

    /// The first `misc_info` entry, which is where the upstream source puts
    /// format membership and release dates.
    public var misc: MiscInfoPayload? { miscInfo?.first }
}

public struct CardSetPayload: Hashable, Sendable, Codable {
    public let setName: String
    public let setCode: String
    public let setRarity: String?
    public let setRarityCode: String?
    /// Sent as a string, and very often "0", which means unpriced rather than free.
    public let setPrice: String?

    enum CodingKeys: String, CodingKey {
        case setName = "set_name"
        case setCode = "set_code"
        case setRarity = "set_rarity"
        case setRarityCode = "set_rarity_code"
        case setPrice = "set_price"
    }
}

public struct CardImagePayload: Hashable, Sendable, Codable {
    /// One card may publish several of these, each with its own identifier.
    /// Deck files reference exactly these numbers.
    public let id: Int
    public let imageUrl: String?
    public let imageUrlSmall: String?
    public let imageUrlCropped: String?

    enum CodingKeys: String, CodingKey {
        case id
        case imageUrl = "image_url"
        case imageUrlSmall = "image_url_small"
        case imageUrlCropped = "image_url_cropped"
    }
}

/// Prices arrive per card and per marketplace, never per printing.
public struct CardPricePayload: Hashable, Sendable, Codable {
    public let cardmarketPrice: String?
    public let tcgplayerPrice: String?
    public let ebayPrice: String?
    public let amazonPrice: String?
    public let coolstuffincPrice: String?

    enum CodingKeys: String, CodingKey {
        case cardmarketPrice = "cardmarket_price"
        case tcgplayerPrice = "tcgplayer_price"
        case ebayPrice = "ebay_price"
        case amazonPrice = "amazon_price"
        case coolstuffincPrice = "coolstuffinc_price"
    }

    /// The marketplace prices as (source, value) pairs, dropping the ones the
    /// upstream source reports as absent or unparseable.
    public var bySource: [(source: String, value: Double)] {
        let raw: [(String, String?)] = [
            ("cardmarket", cardmarketPrice), ("tcgplayer", tcgplayerPrice),
            ("ebay", ebayPrice), ("amazon", amazonPrice),
            ("coolstuffinc", coolstuffincPrice),
        ]
        return raw.compactMap { source, text in
            guard let text, let value = Double(text), value > 0 else { return nil }
            return (source, value)
        }
    }
}

/// Only the three restricting statuses appear here, and only for the formats
/// the upstream source publishes a list for.
public struct BanlistPayload: Hashable, Sendable, Codable {
    public let banTcg: String?
    public let banOcg: String?
    public let banGoat: String?

    enum CodingKeys: String, CodingKey {
        case banTcg = "ban_tcg"
        case banOcg = "ban_ocg"
        case banGoat = "ban_goat"
    }
}

public struct MiscInfoPayload: Hashable, Sendable, Codable {
    public let formats: [String]?
    public let hasEffect: Int?
    public let tcgDate: String?
    public let ocgDate: String?
    public let konamiId: Int?
    public let mdRarity: String?
    /// Cards whose text counts as another card's name for deck limits.
    public let treatedAs: String?

    enum CodingKeys: String, CodingKey {
        case formats
        case hasEffect = "has_effect"
        case tcgDate = "tcg_date"
        case ocgDate = "ocg_date"
        case konamiId = "konami_id"
        case mdRarity = "md_rarity"
        case treatedAs = "treated_as"
    }
}

/// The upstream catalog's version stamp, used to decide whether a dataset needs
/// downloading at all.
public struct CatalogVersion: Hashable, Sendable, Codable {
    public let databaseVersion: String
    public let lastUpdate: String

    enum CodingKeys: String, CodingKey {
        case databaseVersion = "database_version"
        case lastUpdate = "last_update"
    }

    public init(databaseVersion: String, lastUpdate: String) {
        self.databaseVersion = databaseVersion
        self.lastUpdate = lastUpdate
    }
}

/// Fetches catalog data from upstream.
public protocol CatalogFetching: Sendable {
    func fetchVersion() async throws -> CatalogVersion
    func fetchDataset(language: CardLanguage) async throws -> [CatalogCardPayload]
}
