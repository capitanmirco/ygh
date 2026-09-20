import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
import YGOValidation
@testable import YGOSync

/// Judged against the user's own deck files rather than invented ones, because
/// the mistake this rule exists to prevent is a real deck being called broken.
@Suite("Format legality")
struct FormatLegalityTests {
    private let validator = DeckValidator()

    private func violations(_ deck: Deck, _ repository: SQLiteDeckRepository) async throws
        -> [DeckViolation] {
        validator.violations(in: deck, using: try await repository.cardIndex(for: deck))
    }

    /// Evidence for R4.AC1: the same cards, judged against two formats, give
    /// two different answers. Both of these decks are full of cards that GOAT
    /// allows and modern TCG forbids.
    @Test func judgesEachCardAgainstTheDecksOwnFormat() async throws {
        let (_, repository) = try RealDeck.seededRepository()

        for name in RealDeck.names {
            let inTCG = try await RealDeck.build(name, format: .tcg, using: repository)
            let tcgBans = try await violations(inTCG, repository)
                .filter { if case .overCopyLimit = $0 { true } else { false } }

            let inGOAT = try await RealDeck.build(name, format: .goat, using: repository)
            let goatBans = try await violations(inGOAT, repository)
                .filter { if case .overCopyLimit = $0 { true } else { false } }

            #expect(!tcgBans.isEmpty, "\(name) dovrebbe infrangere la banlist TCG")
            #expect(goatBans.isEmpty,
                    "\(name) è legale in GOAT, trovate \(goatBans.map(\.sentence))")

            // Same cards on both sides: only the verdict moved.
            #expect(inTCG.slots.count == inGOAT.slots.count)
            #expect(inTCG.totalCount == inGOAT.totalCount)
        }
    }

    /// Evidence for R4.AC2: a format is a card pool, not only a ban list.
    @Test func reportsCardOutsideTheFormatsPoolByName() async throws {
        let (_, repository) = try RealDeck.seededRepository()
        let cards = try RealDeck.cards()

        // A card released two decades after the GOAT era.
        let modern = try #require(cards.first { card in
            let formats = card.misc?.formats ?? []
            return !formats.contains("GOAT")
        })
        let artwork = ArtworkIdentifier(try #require(modern.cardImages.first).id)

        let deck = try await RealDeck.build("Lockdown Burn", format: .goat, using: repository)
        try await repository.addCard(artwork: artwork, section: .main, to: deck.id)
        let withModern = try #require(try await repository.deck(with: deck.id))

        let pool = try await violations(withModern, repository)
            .filter { if case .outsideFormatPool = $0 { true } else { false } }

        #expect(pool.count == 1)
        guard case .outsideFormatPool(_, let name, let format)? = pool.first else { return }
        #expect(name == modern.name)
        #expect(format == .goat)
        #expect(pool[0].sentence.contains(modern.name))
    }

    /// Evidence for R4.AC3: the decks the user already owns come out legal.
    /// This is the assertion the whole format-aware design exists for.
    @Test func reportsRealGoatDecksAsLegalInGoat() async throws {
        let (_, repository) = try RealDeck.seededRepository()

        for name in RealDeck.names {
            let deck = try await RealDeck.build(name, format: .goat, using: repository)
            let found = try await violations(deck, repository)

            #expect(found.isEmpty,
                    "\(name) doveva risultare legale in GOAT, trovate: \(found.map(\.sentence))")

            let legality = validator.legality(
                of: deck, using: try await repository.cardIndex(for: deck))
            #expect(legality.isLegal)
            #expect(!legality.restrictionsAreUserMaintained, "GOAT ha una banlist upstream")
        }
    }

    /// Evidence for R4.AC4: a duelist fixing a deck gets the whole list.
    @Test func reportsEveryViolationRatherThanTheFirst() async throws {
        let (_, repository) = try RealDeck.seededRepository()

        // An undersized deck, over-copied cards, and a card in the wrong section.
        let deck = try await repository.createDeck(name: "Rotto", format: .goat)
        let cards = try RealDeck.cards()
        let first = try #require(cards.first)
        let second = try #require(cards.dropFirst().first)

        for _ in 0..<4 {
            try await repository.addCard(
                artwork: ArtworkIdentifier(try #require(first.cardImages.first).id),
                section: .main, to: deck.id)
        }
        for _ in 0..<4 {
            try await repository.addCard(
                artwork: ArtworkIdentifier(try #require(second.cardImages.first).id),
                section: .main, to: deck.id)
        }

        let broken = try #require(try await repository.deck(with: deck.id))
        let found = try await violations(broken, repository)

        let sizeIssues = found.filter { if case .sectionSize = $0 { true } else { false } }
        let copyIssues = found.filter { if case .overCopyLimit = $0 { true } else { false } }

        #expect(sizeIssues.count == 1, "otto carte sono un deck principale troppo corto")
        #expect(copyIssues.count == 2, "due carte oltre le tre copie, non una")
        #expect(found.count >= 3, "attese almeno tre violazioni, trovate \(found.count)")

        // Each one reads as its own sentence.
        for violation in found { #expect(!violation.sentence.isEmpty) }
    }
}
