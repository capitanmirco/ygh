import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOSync

/// Deck files produced by other tools reference artwork identifiers, not card
/// identifiers, and most alternate artworks carry a number that appears nowhere
/// else. Resolving them is what makes an import land complete.
@Suite("Artwork resolution")
struct ArtworkResolutionTests {
    private func seededRepository() async throws -> (SQLiteCardRepository, [CatalogCardPayload]) {
        let database = try SyncFixture.migratedDatabase()
        let english = try SyncFixture.cards("catalog-en.json")

        _ = try await CatalogSynchronizer(
            client: StubCatalogClient(
                version: CatalogVersion(databaseVersion: "147.04", lastUpdate: ""),
                english: english,
                italian: try SyncFixture.cards("catalog-it.json")),
            store: SQLiteCatalogStore(database: database),
            now: { SyncFixture.observedAt }).synchronize()

        return (SQLiteCardRepository(database: database), english)
    }

    /// Evidence for R7.AC2: every artwork a card publishes resolves to that one
    /// card, including the identifiers that differ from the card's own.
    @Test func resolvesEveryAlternateArtworkIdentifierToOneCard() async throws {
        let (repository, english) = try await seededRepository()
        let multiArtwork = try #require(english.first { $0.cardImages.count >= 3 })

        for image in multiArtwork.cardImages {
            let resolved = try await repository.card(withArtwork: ArtworkIdentifier(image.id))
            let card = try #require(resolved, "artwork \(image.id) non risolto")
            #expect(card.id == CardIdentifier(multiArtwork.id))
        }

        // At least one of them is not the card's own identifier: that is the
        // case a naive importer gets wrong.
        let alternates = multiArtwork.cardImages.filter { $0.id != multiArtwork.id }
        #expect(!alternates.isEmpty)

        // Resolution agrees with a direct lookup by card identifier.
        let direct = try #require(try await repository.card(with: CardIdentifier(multiArtwork.id)))
        let alternateID = try #require(alternates.first).id
        let viaArtwork = try #require(
            try await repository.card(withArtwork: ArtworkIdentifier(alternateID)))
        #expect(direct == viaArtwork)
    }

    /// Every artwork in the whole dataset resolves, not just the interesting one.
    @Test func resolvesEveryArtworkInTheDataset() async throws {
        let (repository, english) = try await seededRepository()

        for card in english {
            for image in card.cardImages {
                let resolved = try await repository.card(withArtwork: ArtworkIdentifier(image.id))
                #expect(resolved?.id == CardIdentifier(card.id))
            }
        }
    }

    /// Evidence for R7.AC3: an identifier the catalog does not hold is reported
    /// as unresolved. Returning a nearest match would silently put the wrong
    /// card into an imported deck.
    @Test func reportsUnknownIdentifierAsUnresolved() async throws {
        let (repository, english) = try await seededRepository()
        let known = Set(english.flatMap { $0.cardImages.map(\.id) })

        for absent in [0, 1, 999_999_999] where !known.contains(absent) {
            let resolved = try await repository.card(withArtwork: ArtworkIdentifier(absent))
            #expect(resolved == nil, "identificatore \(absent) non doveva risolvere")
        }

        // An identifier one away from a real artwork must not resolve either.
        let realArtwork = try #require(known.first)
        if !known.contains(realArtwork + 1) {
            let neighbour = try await repository.card(
                withArtwork: ArtworkIdentifier(realArtwork + 1))
            #expect(neighbour == nil)
        }
    }
}
