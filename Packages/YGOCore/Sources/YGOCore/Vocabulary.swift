import Foundation

/// The catalog's own vocabulary, in Italian.
///
/// The upstream localises two fields and no more: asking for the Italian
/// dataset returns an Italian `name` and `desc` and leaves `type`,
/// `humanReadableCardType`, `race` and `attribute` in English. A card reads
/// *Un Oceano Leggendario* and, under it, *Field Spell*.
///
/// Every lookup takes its argument as its default, so a term this table does
/// not hold reaches the screen in English rather than vanishing from it. The
/// game keeps adding kinds — Pendulum in 2014, Link in 2017 — and meeting one
/// is the normal case, not the edge.
public enum Vocabulary {
    /// The prefix a Duel Links skill card's kind carries before the
    /// character's name.
    static let skillPrefix = "Skill - "
    static let italianSkillPrefix = "Abilità - "

    // MARK: - Card kinds

    /// "Effect Monster" → "Mostro Effetto".
    ///
    /// Whole terms rather than composed ones: `Fusion Pendulum Effect Monster`
    /// is four words, and Italian leads with the noun, so substituting word by
    /// word gives the right words in the wrong order.
    public static func cardKind(_ upstream: String) -> String {
        if let known = cardKinds[upstream] { return known }
        // A skill card's kind carries a character's name, which stays as
        // published. Only the prefix is ours to translate.
        if upstream.hasPrefix(skillPrefix) {
            let name = upstream.dropFirst(skillPrefix.count)
                .trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "Abilità" : italianSkillPrefix + name
        }
        return upstream
    }

    static let cardKinds: [String: String] = [
        // Monsters
        "Monster": "Mostro",
        "Normal Monster": "Mostro Normale",
        "Effect Monster": "Mostro Effetto",
        "Flip Effect Monster": "Mostro Effetto Scoperta",
        "Flip Tuner Effect Monster": "Mostro Tuner Effetto Scoperta",
        "Gemini Effect Monster": "Mostro Effetto Gemini",
        "Spirit Effect Monster": "Mostro Effetto Spirito",
        "Toon Effect Monster": "Mostro Effetto Toon",
        "Tuner Effect Monster": "Mostro Tuner Effetto",
        "Tuner Normal Monster": "Mostro Normale Tuner",
        "Union Effect Monster": "Mostro Effetto Unione",
        // Ritual
        "Ritual Monster": "Mostro Rituale",
        "Ritual Effect Monster": "Mostro Rituale Effetto",
        "Ritual Flip Effect Monster": "Mostro Rituale Effetto Scoperta",
        "Ritual Tuner Effect Monster": "Mostro Rituale Tuner Effetto",
        "Ritual Pendulum Effect Monster": "Mostro Rituale Pendulum Effetto",
        // Extra deck
        "Fusion Monster": "Mostro Fusione",
        "Fusion Effect Monster": "Mostro Fusione Effetto",
        "Fusion Tuner Monster": "Mostro Fusione Tuner",
        "Fusion Tuner Effect Monster": "Mostro Fusione Tuner Effetto",
        "Fusion Toon Effect Monster": "Mostro Fusione Effetto Toon",
        "Fusion Pendulum Effect Monster": "Mostro Fusione Pendulum Effetto",
        "Synchro Monster": "Mostro Synchro",
        "Synchro Effect Monster": "Mostro Synchro Effetto",
        "Synchro Tuner Effect Monster": "Mostro Synchro Tuner Effetto",
        "Synchro Pendulum Effect Monster": "Mostro Synchro Pendulum Effetto",
        "Xyz Monster": "Mostro Xyz",
        "Xyz Effect Monster": "Mostro Xyz Effetto",
        "Xyz Pendulum Effect Monster": "Mostro Xyz Pendulum Effetto",
        "Link Monster": "Mostro Link",
        "Link Effect Monster": "Mostro Link Effetto",
        // Pendulum
        "Pendulum Normal Monster": "Mostro Normale Pendulum",
        "Pendulum Effect Monster": "Mostro Effetto Pendulum",
        "Pendulum Flip Effect Monster": "Mostro Effetto Scoperta Pendulum",
        "Pendulum Tuner Normal Monster": "Mostro Normale Tuner Pendulum",
        "Pendulum Tuner Effect Monster": "Mostro Tuner Effetto Pendulum",
        "Pendulum Spirit Effect Monster": "Mostro Effetto Spirito Pendulum",
        // Spells
        "Normal Spell": "Magia Normale",
        "Continuous Spell": "Magia Continua",
        "Quick-Play Spell": "Magia Rapida",
        "Equip Spell": "Magia Equipaggiamento",
        "Field Spell": "Magia Terreno",
        "Ritual Spell": "Magia Rituale",
        // Traps
        "Normal Trap": "Trappola Normale",
        "Continuous Trap": "Trappola Continua",
        "Counter Trap": "Trappola Contro",
        // Other
        "Token": "Segnalino",
    ]

    // MARK: - Attributes

    /// The game writes them in capitals in Italian too.
    public static func attribute(_ upstream: String) -> String {
        attributes[upstream] ?? upstream
    }

    static let attributes: [String: String] = [
        "DARK": "OSCURITÀ",
        "LIGHT": "LUCE",
        "EARTH": "TERRA",
        "WATER": "ACQUA",
        "FIRE": "FUOCO",
        "WIND": "VENTO",
        "DIVINE": "DIVINO",
    ]

    // MARK: - Monster types

    /// The same column holds a monster's type, a spell's or trap's kind, and a
    /// skill card's character. One map, because the upstream's column is one.
    public static func monsterType(_ upstream: String) -> String {
        monsterTypes[upstream] ?? upstream
    }

    static let monsterTypes: [String: String] = [
        "Aqua": "Acqua",
        "Beast": "Bestia",
        "Beast-Warrior": "Bestia Guerriera",
        "Creator God": "Dio Creatore",
        "Cyberse": "Cyberso",
        "Dinosaur": "Dinosauro",
        "Divine-Beast": "Divinità Bestia",
        "Dragon": "Drago",
        "Fairy": "Fata",
        "Fiend": "Demone",
        "Fish": "Pesce",
        "Illusion": "Illusione",
        "Insect": "Insetto",
        "Machine": "Macchina",
        "Plant": "Pianta",
        "Psychic": "Psichico",
        "Pyro": "Piro",
        "Reptile": "Rettile",
        "Rock": "Roccia",
        "Sea Serpent": "Serpente Marino",
        "Spellcaster": "Incantatore",
        "Thunder": "Tuono",
        "Warrior": "Guerriero",
        "Winged Beast": "Bestia Alata",
        "Wyrm": "Wyrm",
        "Zombie": "Zombie",
        // Spell and trap kinds share this column.
        "Normal": "Normale",
        "Continuous": "Continua",
        "Counter": "Contro",
        "Equip": "Equipaggiamento",
        "Field": "Terreno",
        "Quick-Play": "Rapida",
        "Ritual": "Rituale",
    ]

    // MARK: - Rarities

    /// Translated only where the Italian market renames them. "Secret Rare" is
    /// what it is called here, and translating it would invent a term nobody
    /// uses.
    public static func rarity(_ upstream: String) -> String {
        rarities[upstream] ?? upstream
    }

    static let rarities: [String: String] = [
        "Common": "Comune",
        "Rare": "Rara",
        "Short Print": "Stampa Breve",
        "Super Short Print": "Stampa Molto Breve",
        "Duel Terminal Normal Parallel Rare": "Duel Terminal Normale Parallel Rare",
    ]

    // MARK: - Coverage

    /// Which of these terms the table does not hold, ignoring the ones it
    /// deliberately leaves alone: a skill's character name is a proper name,
    /// not a gap.
    public static func untranslated(kinds: [String], types: [String]) -> [String] {
        let missingKinds = kinds.filter {
            cardKinds[$0] == nil && !$0.hasPrefix(skillPrefix)
        }
        let missingTypes = types.filter {
            monsterTypes[$0] == nil && !$0.isEmpty && !isProperName($0)
        }
        return (missingKinds + missingTypes).sorted()
    }

    /// A character's name rather than a type. The catalog's skill cards put
    /// one in the type column, and the upstream truncates it to thirteen
    /// characters — `Bastion Misaw`, `Chazz Princet`. Completing them would be
    /// inventing data.
    static func isProperName(_ value: String) -> Bool {
        skillCharacterTypes.contains(value)
    }

    static let skillCharacterTypes: Set<String> = [
        "Abidos the Th", "Adrian Gecko", "Alexis Rhodes", "Amnael", "Andrew",
        "Arkana", "Aster Phoenix", "Axel Brodie", "Bastion Misaw", "Bonz",
        "Camula", "Chazz Princet", "Christine", "Chumley Huffi", "David",
        "Don Zaloog", "Dr. Vellian C", "Emma", "Espa Roba", "Ishizu",
        "Ishizu Ishtar", "Jaden Yuki", "Jesse Anderso", "Joey", "Joey Wheeler",
        "Kagemaru", "Kaiba", "Keith", "Lumis Umbra", "Lumis and Umb", "Mai",
        "Mai Valentine", "Mako", "Nightshroud", "Odion", "Paradox Broth",
        "Pegasus", "Rex", "Seto Kaiba", "Syrus Truesda", "Tania", "Tea Gardner",
        "The Supreme K", "Thelonious Vi", "Titan", "Tyranno Hassl", "Weevil",
        "Yami Bakura", "Yami Marik", "Yami Yugi", "Yubel", "Yugi",
        "Zane Truesdal",
    ]
}
