import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOSync

/// Tuning a list over weeks means experimenting. An experiment that cannot be
/// undone is not one.
@Suite("Deck versions")
struct DeckVersionTests {
    private func rig() async throws -> (SQLiteDeckRepository, Deck, [ArtworkIdentifier]) {
        let (_, repository) = try RealDeck.seededRepository()
        let cards = try RealDeck.cards()
        let artworks = try cards.prefix(4).map { ArtworkIdentifier(try #require($0.cardImages.first).id) }

        let deck = try await repository.createDeck(name: "Tuning", format: .goat)
        for artwork in artworks.prefix(2) {
            try await repository.addCard(artwork: artwork, section: .main, to: deck.id)
            try await repository.addCard(artwork: artwork, section: .main, to: deck.id)
        }
        return (repository, try #require(try await repository.deck(with: deck.id)), Array(artworks))
    }

    /// Evidence for R8.AC1: the version keeps what was, not what is.
    @Test func savedVersionKeepsPreEditCounts() async throws {
        let (repository, deck, artworks) = try await rig()
        #expect(deck.count(in: .main) == 4)

        try await repository.saveVersion(of: deck.id, label: "Prima")
        try await repository.addCard(artwork: artworks[2], section: .main, to: deck.id)
        try await repository.addCard(artwork: artworks[3], section: .side, to: deck.id)

        let now = try #require(try await repository.deck(with: deck.id))
        #expect(now.count(in: .main) == 5)
        #expect(now.count(in: .side) == 1)

        let versions = try await repository.versions(of: deck.id)
        #expect(versions.count == 1)
        let saved = try #require(versions.first)
        #expect(saved.label == "Prima")
        #expect(saved.slots.reduce(0) { $0 + $1.quantity } == 4,
                "la versione deve ricordare le quattro carte di prima, non le sei di adesso")
        #expect(!saved.slots.contains { $0.section == .side })
    }

    /// Evidence for R8.AC2: restoring returns exactly what was saved.
    @Test func restoringAVersionReturnsExactlyItsCounts() async throws {
        let (repository, deck, artworks) = try await rig()
        let versionID = try await repository.saveVersion(of: deck.id, label: "Punto fermo")
        let before = try #require(try await repository.deck(with: deck.id)).slots

        // Change it substantially.
        try await repository.addCard(artwork: artworks[2], section: .extra, to: deck.id)
        try await repository.removeCard(artwork: artworks[0], section: .main, from: deck.id)
        try await repository.removeCard(artwork: artworks[0], section: .main, from: deck.id)
        let changed = try #require(try await repository.deck(with: deck.id))
        #expect(changed.slots != before)

        try await repository.restore(versionID: versionID)

        let restored = try #require(try await repository.deck(with: deck.id))
        #expect(Set(restored.slots) == Set(before))
        #expect(restored.count(in: .main) == 4)
        #expect(restored.count(in: .extra) == 0)
    }

    /// Evidence for R8.AC3: a restore is itself reversible.
    @Test func restoringStoresTheReplacedStateAsAVersion() async throws {
        let (repository, deck, artworks) = try await rig()
        let firstVersion = try await repository.saveVersion(of: deck.id, label: "Iniziale")

        try await repository.addCard(artwork: artworks[2], section: .main, to: deck.id)
        let experimental = try #require(try await repository.deck(with: deck.id)).slots

        try await repository.restore(versionID: firstVersion)

        let versions = try await repository.versions(of: deck.id)
        #expect(versions.count == 2, "il ripristino deve salvare ciò che sostituisce")

        let replaced = try #require(versions.last)
        #expect(Set(replaced.slots) == Set(experimental),
                "lo stato scartato deve essere recuperabile")

        // And it really is recoverable.
        try await repository.restore(versionID: replaced.id)
        let back = try #require(try await repository.deck(with: deck.id))
        #expect(Set(back.slots) == Set(experimental))
    }

    /// Evidence for R8.AC4: history outlives unrelated churn.
    @Test func versionsSurviveUnrelatedDeletionsAndAReopen() async throws {
        let (repository, deck, _) = try await rig()
        try await repository.saveVersion(of: deck.id, label: "Uno")
        try await repository.saveVersion(of: deck.id, label: "Due")

        let other = try await repository.createDeck(name: "Da cancellare", format: .tcg)
        try await repository.saveVersion(of: other.id, label: "Altrui")
        try await repository.delete(other.id, confirmed: true)

        let versions = try await repository.versions(of: deck.id)
        #expect(versions.map(\.label) == ["Uno", "Due"])
        #expect(try await repository.versions(of: other.id).isEmpty,
                "le versioni di un mazzo cancellato se ne vanno con lui")
    }
}
