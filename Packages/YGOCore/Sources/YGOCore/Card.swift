/// The shape of a card, which decides where it may be placed in a deck and how
/// it is drawn in the interface.
public enum CardFrame: String, Hashable, Sendable, Codable, CaseIterable {
    case normal, effect, ritual, fusion, synchro, xyz, link
    case normalPendulum = "normal_pendulum"
    case effectPendulum = "effect_pendulum"
    case ritualPendulum = "ritual_pendulum"
    case fusionPendulum = "fusion_pendulum"
    case synchroPendulum = "synchro_pendulum"
    case xyzPendulum = "xyz_pendulum"
    case spell, trap, token, skill

    /// Whether a card of this shape belongs in the Extra Deck.
    public var belongsInExtraDeck: Bool {
        switch self {
        case .fusion, .synchro, .xyz, .link,
             .fusionPendulum, .synchroPendulum, .xyzPendulum: true
        default: false
        }
    }
}

/// A monster's elemental attribute.
public enum CardAttribute: String, Hashable, Sendable, Codable, CaseIterable {
    case dark = "DARK", light = "LIGHT", earth = "EARTH", water = "WATER"
    case fire = "FIRE", wind = "WIND", divine = "DIVINE"
}

/// The combat and summoning numbers a monster card carries. Absent for spells
/// and traps, which is why it is a separate optional value rather than a set of
/// optional fields on `Card`.
public struct MonsterStats: Hashable, Sendable {
    public let attribute: CardAttribute?
    public let race: String
    public let level: Int?
    public let attack: Int?
    public let defense: Int?
    public let linkRating: Int?
    public let pendulumScale: Int?

    public init(
        attribute: CardAttribute?,
        race: String,
        level: Int?,
        attack: Int?,
        defense: Int?,
        linkRating: Int?,
        pendulumScale: Int?
    ) {
        self.attribute = attribute
        self.race = race
        self.level = level
        self.attack = attack
        self.defense = defense
        self.linkRating = linkRating
        self.pendulumScale = pendulumScale
    }
}

/// One card in the catalog, carrying both stored languages so that presentation
/// can pick one without another query.
public struct Card: Hashable, Sendable, Identifiable {
    public let id: CardIdentifier
    public let englishName: String
    public let englishEffect: String
    public let italianName: String?
    public let italianEffect: String?
    public let frame: CardFrame
    public let humanReadableType: String
    public let archetype: String?
    public let monsterStats: MonsterStats?
    public let artworks: [ArtworkIdentifier]
    public let formats: Set<CardFormat>

    public init(
        id: CardIdentifier,
        englishName: String,
        englishEffect: String,
        italianName: String?,
        italianEffect: String?,
        frame: CardFrame,
        humanReadableType: String,
        archetype: String?,
        monsterStats: MonsterStats?,
        artworks: [ArtworkIdentifier],
        formats: Set<CardFormat>
    ) {
        self.id = id
        self.englishName = englishName
        self.englishEffect = englishEffect
        self.italianName = italianName
        self.italianEffect = italianEffect
        self.frame = frame
        self.humanReadableType = humanReadableType
        self.archetype = archetype
        self.monsterStats = monsterStats
        self.artworks = artworks
        self.formats = formats
    }

    /// The card's text in `language`, falling back to English when the
    /// requested language has no translation for this card.
    public func text(in language: CardLanguage) -> CardText {
        switch language {
        case .english:
            CardText(name: englishName, effect: englishEffect, isFallbackToEnglish: false)
        case .italian:
            if let italianName, let italianEffect {
                CardText(name: italianName, effect: italianEffect, isFallbackToEnglish: false)
            } else {
                CardText(name: englishName, effect: englishEffect, isFallbackToEnglish: true)
            }
        }
    }
}
