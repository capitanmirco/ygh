import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
import YGOValidation
@testable import YGOSync

/// Edison and Master Duel publish which cards belong to them but no ban list at
/// all, so a verdict in those formats rests entirely on what the user has
/// recorded. The application must apply it and must not pretend it is
/// authoritative.
@Suite("User-maintained formats")
struct UserMaintainedFormatTests {
    private let validator = DeckValidator()

    private func copyViolations(_ deck: Deck, _ repository: SQLiteDeckRepository) async throws
        -> [DeckViolation] {
        validator.violations(in: deck, using: try await repository.cardIndex(for: deck))
            .filter { if case .overCopyLimit = $0 { true } else { false } }
    }

    /// Evidence for R4.AC5: a hand-written limit is enforced while it stands
    /// and stops being enforced once it is cleared.
    @Test func appliesUserRecordedRestrictionAndClearsWithIt() async throws {
        let (database, repository) = try RealDeck.seededRepository()
        let editor = SQLiteBanListEditor(database: database)
        let cards = try RealDeck.cards()

        let card = try #require(cards.first { ($0.misc?.formats ?? []).contains("Edison") })
        let artwork = ArtworkIdentifier(try #require(card.cardImages.first).id)

        let deck = try await repository.createDeck(name: "Edison", format: .edison)
        try await repository.addCard(artwork: artwork, section: .main, to: deck.id)
        try await repository.addCard(artwork: artwork, section: .main, to: deck.id)

        // With nothing recorded, two copies are simply two copies.
        var built = try #require(try await repository.deck(with: deck.id))
        #expect(try await copyViolations(built, repository).isEmpty)

        // The user marks it Limited for Edison.
        try await editor.setUserBanStatus(.limited, for: CardIdentifier(card.id), in: .edison)
        built = try #require(try await repository.deck(with: deck.id))
        let restricted = try await copyViolations(built, repository)

        #expect(restricted.count == 1)
        guard case .overCopyLimit(_, let held, let permitted, let reason)? = restricted.first
        else { Issue.record("attesa una violazione"); return }
        #expect(held == 2)
        #expect(permitted == 1)
        #expect(reason == .banStatus(.limited))

        // Clearing it removes the verdict with it.
        try await editor.setUserBanStatus(.unlimited, for: CardIdentifier(card.id), in: .edison)
        built = try #require(try await repository.deck(with: deck.id))
        #expect(try await copyViolations(built, repository).isEmpty)
    }

    /// Evidence for R4.AC6: the verdict says where its authority comes from,
    /// without the interface having to inspect the stored rows.
    @Test func marksAVerdictAsUserMaintainedForFormatsWithoutAnUpstreamList() async throws {
        let (_, repository) = try RealDeck.seededRepository()

        let published: [CardFormat] = [.tcg, .ocg, .goat]
        let selfMaintained: [CardFormat] = [.edison, .masterDuel, .duelLinks,
                                            .speedDuel, .ocgGoat, .commonCharity]

        for format in published {
            let deck = try await repository.createDeck(name: "Deck", format: format)
            let legality = validator.legality(
                of: deck, using: try await repository.cardIndex(for: deck))
            #expect(!legality.restrictionsAreUserMaintained,
                    "\(format.rawValue) ha una banlist pubblicata")
        }

        for format in selfMaintained {
            let deck = try await repository.createDeck(name: "Deck", format: format)
            let legality = validator.legality(
                of: deck, using: try await repository.cardIndex(for: deck))
            #expect(legality.restrictionsAreUserMaintained,
                    "\(format.rawValue) non ha banlist upstream, il verdetto è dell'utente")
        }
    }

    /// A restriction the user records for one format must not leak into another.
    @Test func userRestrictionAppliesOnlyToItsOwnFormat() async throws {
        let (database, repository) = try RealDeck.seededRepository()
        let editor = SQLiteBanListEditor(database: database)
        let cards = try RealDeck.cards()

        let card = try #require(cards.first { card in
            let formats = card.misc?.formats ?? []
            return formats.contains("Edison") && formats.contains("Master Duel")
                && card.banlistInfo == nil
        })
        let artwork = ArtworkIdentifier(try #require(card.cardImages.first).id)
        try await editor.setUserBanStatus(.forbidden, for: CardIdentifier(card.id), in: .edison)

        let edisonDeck = try await repository.createDeck(name: "Edison", format: .edison)
        try await repository.addCard(artwork: artwork, section: .main, to: edisonDeck.id)
        let edison = try #require(try await repository.deck(with: edisonDeck.id))
        #expect(try await copyViolations(edison, repository).count == 1)

        let masterDuelDeck = try await repository.createDeck(name: "MD", format: .masterDuel)
        try await repository.addCard(artwork: artwork, section: .main, to: masterDuelDeck.id)
        let masterDuel = try #require(try await repository.deck(with: masterDuelDeck.id))
        #expect(try await copyViolations(masterDuel, repository).isEmpty,
                "una restrizione Edison non deve valere in Master Duel")
    }
}
