import Foundation
import YGOCore

/// Counts queries so a test can prove that an action did not cause one.
actor CountingSearchRepository: CardSearching, CardSearchCounting {
    private(set) var searchCount = 0
    /// The last query it was asked for, so a test can assert what reached it.
    private(set) var lastQuery: CardQuery?
    private let cards: [Card]

    init(cards: [Card]) {
        self.cards = cards
    }

    func search(_ query: CardQuery) async throws -> CardSearchOutcome {
        searchCount += 1
        lastQuery = query
        let page = cards.dropFirst(query.offset).prefix(query.limit)
        return CardSearchOutcome(Array(page))
    }

    func matchCount(for query: CardQuery) async throws -> Int {
        cards.count
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

/// Answers searches for one query text at a time and holds each answer until
/// it is released, so a test can decide which of two loads finishes first.
actor GatedSearchRepository: CardSearching, CardSearchCounting {
    private let cards: [String: [Card]]
    private var gates: [String: CheckedContinuation<Void, Never>] = [:]
    private var held: Set<String> = []

    init(cards: [String: [Card]]) {
        self.cards = cards
    }

    /// Answers for `text` will block until `release(_:)` is called.
    func hold(_ text: String) {
        held.insert(text)
    }

    func release(_ text: String) {
        held.remove(text)
        gates.removeValue(forKey: text)?.resume()
    }

    /// True once a search for `text` has actually reached its gate, so a test
    /// can wait for that rather than hoping a yield was enough.
    func isWaiting(_ text: String) -> Bool {
        gates[text] != nil
    }

    func search(_ query: CardQuery) async throws -> CardSearchOutcome {
        let text = query.normalizedText ?? ""
        if held.contains(text) {
            await withCheckedContinuation { gates[text] = $0 }
        }
        return CardSearchOutcome(cards[text] ?? [])
    }

    func matchCount(for query: CardQuery) async throws -> Int {
        cards[query.normalizedText ?? ""]?.count ?? 0
    }
}

/// Fails every search, which is how a local query failing has to look to the
/// browser: a settled empty answer, not a spinner that never stops.
struct FailingSearchRepository: CardSearching, CardSearchCounting {
    struct Failure: Error {}
    func search(_ query: CardQuery) async throws -> CardSearchOutcome { throw Failure() }
    func matchCount(for query: CardQuery) async throws -> Int { throw Failure() }
}

/// A catalog large enough to page through, with every card distinguishable.
enum BulkCards {
    static func make(_ count: Int) -> [Card] {
        (1...count).map { index in
            Card(id: CardIdentifier(index),
                 englishName: String(format: "Card %04d", index),
                 englishEffect: "effect \(index)",
                 italianName: nil,
                 italianEffect: nil,
                 frame: .spell,
                 humanReadableType: "Normal Spell",
                 archetype: nil,
                 monsterStats: nil,
                 artworks: [ArtworkIdentifier(index)],
                 formats: [.tcg])
        }
    }
}

/// Pages a fixed catalog the way the real repository does, and records the
/// offsets it was asked for.
actor PagingSearchRepository: CardSearching, CardSearchCounting {
    private let cards: [Card]
    private(set) var offsets: [Int] = []
    private var heldOffset: Int?
    private var gate: CheckedContinuation<Void, Never>?

    init(cards: [Card]) {
        self.cards = cards
    }

    func hold(offset: Int) {
        heldOffset = offset
    }

    func release() {
        heldOffset = nil
        gate?.resume()
        gate = nil
    }

    func isWaiting() -> Bool { gate != nil }

    func search(_ query: CardQuery) async throws -> CardSearchOutcome {
        offsets.append(query.offset)
        if heldOffset == query.offset {
            await withCheckedContinuation { gate = $0 }
        }
        let page = cards.dropFirst(query.offset).prefix(query.limit)
        return CardSearchOutcome(Array(page))
    }

    func matchCount(for query: CardQuery) async throws -> Int { cards.count }
}
