import Foundation
import YGOBanlistHistory
import YGOCore

enum DetailCards {
    /// Translated, several artworks, and carrying a Konami identifier.
    static let blueEyes = Card(
        id: CardIdentifier(89_631_139),
        englishName: "Blue-Eyes White Dragon",
        englishEffect: "This legendary dragon is a powerful engine of destruction.",
        italianName: "Drago Bianco Occhi Blu",
        italianEffect: "Questo drago leggendario è una potente macchina di distruzione.",
        frame: .normal,
        humanReadableType: "Normal Monster",
        archetype: "Blue-Eyes",
        monsterStats: MonsterStats(
            attribute: .light, race: "Dragon", level: 8,
            attack: 3000, defense: 2500, linkRating: nil, pendulumScale: nil),
        artworks: [ArtworkIdentifier(89_631_139),
                   ArtworkIdentifier(89_631_140),
                   ArtworkIdentifier(89_631_141)],
        formats: [.tcg, .goat])

    /// One of the 2,981 cards with no Italian text, and one artwork only.
    static let untranslated = Card(
        id: CardIdentifier(70_368_879),
        englishName: "Upstart Goblin",
        englishEffect: "Draw 1 card, then your opponent gains 1000 LP.",
        italianName: nil,
        italianEffect: nil,
        frame: .spell,
        humanReadableType: "Normal Spell",
        archetype: nil,
        monsterStats: nil,
        artworks: [ArtworkIdentifier(70_368_879)],
        formats: [.tcg])
}

struct StubCardRepository: CardRepository {
    var statuses: [CardIdentifier: BanStatus] = [:]
    var cards: [Card] = []

    func card(with identifier: CardIdentifier) async throws -> Card? {
        cards.first { $0.id == identifier }
    }
    func card(withArtwork identifier: ArtworkIdentifier) async throws -> Card? {
        cards.first { $0.artworks.contains(identifier) }
    }
    func banStatus(for identifier: CardIdentifier, in format: CardFormat) async throws -> BanStatus {
        statuses[identifier] ?? .unlimited
    }
    func cardCount() async throws -> Int { cards.count }
}

struct StubDetailReader: CardDetailReading {
    struct Failure: Error {}
    var printings: [CardIdentifier: [CardPrinting]] = [:]
    var releases: [CardIdentifier: CardRelease] = [:]
    var konamiIDs: [CardIdentifier: Int] = [:]
    var failPrintings = false

    func printings(forCard identifier: CardIdentifier) async throws -> [CardPrinting] {
        if failPrintings { throw Failure() }
        return printings[identifier] ?? []
    }
    func release(forCard identifier: CardIdentifier) async throws -> CardRelease {
        releases[identifier] ?? .unknown
    }
    func konamiID(forCard identifier: CardIdentifier) async throws -> Int? {
        konamiIDs[identifier]
    }
}

struct StubUsageReader: CardUsageReading {
    struct Failure: Error {}
    var holdings: [CardIdentifier: [CardHolding]] = [:]
    var uses: [CardIdentifier: [DeckUse]] = [:]
    var failHoldings = false

    func holdings(forCard identifier: CardIdentifier) async throws -> [CardHolding] {
        if failHoldings { throw Failure() }
        return holdings[identifier] ?? []
    }
    func deckUses(forCard identifier: CardIdentifier) async throws -> [DeckUse] {
        uses[identifier] ?? []
    }
}

struct StubPriceLookup: PriceLookup {
    var recorded: [CardIdentifier: [RecordedPrice]] = [:]

    func prices(
        forCards cards: Set<CardIdentifier>
    ) async throws -> [CardIdentifier: [RecordedPrice]] {
        recorded.filter { cards.contains($0.key) }
    }
}

/// Answers history questions from tables held in memory, so the panel is
/// provable with no database at all.
struct StubBanlistHistory: BanlistHistoryReading, BanlistProvenanceReporting {
    struct Failure: Error {}
    var revisionDates: [BanlistFormat: [String]] = [:]
    var statuses: [Int: [String: BanlistStatus]] = [:]
    var source = "yaml-yugi-limit-regulation"
    var failRevisions = false

    func revisions(for format: BanlistFormat) throws -> [BanlistRevision] {
        if failRevisions { throw Failure() }
        return (revisionDates[format] ?? []).sorted().map {
            BanlistRevision(format: format, effectiveDate: $0, source: source,
                            fetchedAt: "2026-09-21T09:00:00Z", entryCount: 1)
        }
    }
    func list(_ format: BanlistFormat, effectiveDate: String) throws -> [BanlistListEntry] { [] }
    func difference(
        _ format: BanlistFormat, from earlier: String, to later: String
    ) throws -> [BanlistDifference] { [] }
    func statuses(
        forKonamiID konamiID: Int, format: BanlistFormat
    ) throws -> [String: BanlistStatus] {
        statuses[konamiID] ?? [:]
    }

    func provenance(for format: BanlistFormat) throws -> BanlistProvenance {
        let dates = (revisionDates[format] ?? []).sorted()
        return BanlistProvenance(
            format: format, sources: dates.isEmpty ? [] : [source],
            lastSynchronised: dates.isEmpty ? nil : "2026-09-21T09:00:00Z",
            revisionCount: dates.count, newestList: dates.last)
    }
    func disagreements(for format: BanlistFormat) throws -> [BanlistDisagreement] { [] }
}

/// Serves whichever variants it was given, so a test can put a card in the
/// state the live store is actually in: thumbnail present, full absent.
struct StubArtworkStore: ArtworkProviding {
    var thumbnails: Set<ArtworkIdentifier> = []
    var fullImages: Set<ArtworkIdentifier> = []

    func storedArtworkPath(
        for identifier: ArtworkIdentifier, variant: ArtworkVariant
    ) async -> String? {
        switch variant {
        case .full:
            fullImages.contains(identifier) ? "/store/full/\(identifier.rawValue).jpg" : nil
        case .thumbnail:
            thumbnails.contains(identifier) ? "/store/thumb/\(identifier.rawValue).jpg" : nil
        }
    }
}
