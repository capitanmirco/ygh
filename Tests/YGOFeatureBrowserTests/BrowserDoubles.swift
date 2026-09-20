import Foundation
import YGOCore

/// Counts queries so a test can prove that an action did not cause one.
actor CountingSearchRepository: CardSearching {
    private(set) var searchCount = 0
    private let cards: [Card]

    init(cards: [Card]) {
        self.cards = cards
    }

    func search(_ query: CardQuery) async throws -> CardSearchOutcome {
        searchCount += 1
        return CardSearchOutcome(cards)
    }
}

/// Reports every artwork as absent, which is the state the grid is in before a
/// prefetch has run and the state it stays in offline.
struct NoArtworkAvailable: ArtworkProviding {
    func storedArtworkPath(
        for identifier: ArtworkIdentifier,
        variant: ArtworkVariant
    ) async -> String? { nil }
}

/// Serves artwork from a fixed table of paths.
struct StubArtworkProvider: ArtworkProviding {
    let paths: [ArtworkIdentifier: String]

    func storedArtworkPath(
        for identifier: ArtworkIdentifier,
        variant: ArtworkVariant
    ) async -> String? { paths[identifier] }
}

/// Answers restriction questions without a database.
struct StubBanStatusProvider: CardRepository {
    var statuses: [CardIdentifier: BanStatus] = [:]
    var cards: [Card] = []

    func card(with identifier: CardIdentifier) async throws -> Card? {
        cards.first { $0.id == identifier }
    }

    func card(withArtwork identifier: ArtworkIdentifier) async throws -> Card? {
        cards.first { $0.artworks.contains(identifier) }
    }

    func banStatus(
        for identifier: CardIdentifier,
        in format: CardFormat
    ) async throws -> BanStatus {
        statuses[identifier] ?? .unlimited
    }

    func cardCount() async throws -> Int { cards.count }
}

enum SampleCards {
    /// A translated card and an untranslated one, which is the pairing every
    /// language assertion needs.
    static func make() -> [Card] {
        [
            Card(id: CardIdentifier(55144522),
                 englishName: "Pot of Greed",
                 englishEffect: "Draw 2 cards.",
                 italianName: "Anfora dell'Avidità",
                 italianEffect: "Pesca 2 carte.",
                 frame: .spell,
                 humanReadableType: "Normal Spell",
                 archetype: nil,
                 monsterStats: nil,
                 artworks: [ArtworkIdentifier(55144522)],
                 formats: [.tcg, .goat]),
            Card(id: CardIdentifier(89631139),
                 englishName: "Blue-Eyes White Dragon",
                 englishEffect: "This legendary dragon is a powerful engine of destruction.",
                 italianName: nil,
                 italianEffect: nil,
                 frame: .normal,
                 humanReadableType: "Normal Monster",
                 archetype: "Blue-Eyes",
                 monsterStats: MonsterStats(
                    attribute: .light, race: "Dragon", level: 8,
                    attack: 3000, defense: 2500, linkRating: nil, pendulumScale: nil),
                 artworks: [ArtworkIdentifier(89631139), ArtworkIdentifier(89631140)],
                 formats: [.tcg, .goat, .edison]),
            Card(id: CardIdentifier(46986414),
                 englishName: "Dark Magician",
                 englishEffect: "The ultimate wizard in terms of attack and defense.",
                 italianName: "Mago Nero",
                 italianEffect: "Il mago supremo per attacco e difesa.",
                 frame: .normal,
                 humanReadableType: "Normal Monster",
                 archetype: "Dark Magician",
                 monsterStats: MonsterStats(
                    attribute: .dark, race: "Spellcaster", level: 7,
                    attack: 2500, defense: 2100, linkRating: nil, pendulumScale: nil),
                 artworks: [ArtworkIdentifier(46986414)],
                 formats: [.tcg]),
        ]
    }
}
