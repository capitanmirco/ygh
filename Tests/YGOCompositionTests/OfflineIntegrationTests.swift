import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureBrowser
import YGONetworking
import YGOPersistence
@testable import YGOComposition

private enum Offline: Error { case noNetwork }

/// Upstream is simply gone: every call throws.
private struct DeadCatalogClient: CatalogFetching {
    func fetchVersion() async throws -> CatalogVersion { throw Offline.noNetwork }
    func fetchDataset(language: CardLanguage) async throws -> [CatalogCardPayload] {
        throw Offline.noNetwork
    }
}

private struct DeadArtworkFetcher: ArtworkFetching {
    func imageData(
        for identifier: ArtworkIdentifier,
        variant: ArtworkVariant
    ) async throws -> Data { throw Offline.noNetwork }
}

/// Serves the recorded fixtures, used only to get a catalog on disk first.
private struct FixtureCatalogClient: CatalogFetching {
    let english: [CatalogCardPayload]
    let italian: [CatalogCardPayload]

    func fetchVersion() async throws -> CatalogVersion {
        CatalogVersion(databaseVersion: "147.04", lastUpdate: "2026-09-16 00:05:12")
    }

    func fetchDataset(language: CardLanguage) async throws -> [CatalogCardPayload] {
        language == .english ? english : italian
    }
}

private struct FixtureArtworkFetcher: ArtworkFetching {
    func imageData(
        for identifier: ArtworkIdentifier,
        variant: ArtworkVariant
    ) async throws -> Data { Data("artwork-\(identifier.rawValue)".utf8) }
}

@Suite("Offline integration")
struct OfflineIntegrationTests {
    private static let observedAt = Date(timeIntervalSince1970: 1_758_000_000)

    private static func fixtures() throws -> ([CatalogCardPayload], [CatalogCardPayload]) {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return (
            try YGOProDeckCatalogClient.decodeDataset(
                Data(contentsOf: root.appending(path: "fixtures/catalog-en.json"))),
            try YGOProDeckCatalogClient.decodeDataset(
                Data(contentsOf: root.appending(path: "fixtures/catalog-it.json"))))
    }

    /// Evidence for NFR4: with every outbound call throwing, the whole graph
    /// still answers. The application degrades in freshness, never in
    /// usability, which is the point of storing the catalog at all.
    @Test func everyFeatureWorksWithAllOutboundCallsThrowing() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "ygo-offline-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: container) }

        let (english, italian) = try Self.fixtures()

        // One online start to put a catalog and some artwork on disk.
        let online = try CatalogEnvironment.make(
            containerURL: container,
            client: FixtureCatalogClient(english: english, italian: italian),
            artworkFetcher: FixtureArtworkFetcher(),
            now: { Self.observedAt })
        let seeded = await online.start()
        #expect(seeded == .seeded(cardCount: english.count))
        _ = try await online.prefetcher.prefetchThumbnails()
        try await online.database.close()

        // Now the network disappears entirely and the application opens again.
        let offline = try CatalogEnvironment.make(
            containerURL: container,
            client: DeadCatalogClient(),
            artworkFetcher: DeadArtworkFetcher(),
            now: { Self.observedAt })

        let outcome = await offline.start()
        guard case .keptStoredCatalog = outcome else {
            Issue.record("atteso keptStoredCatalog, ricevuto \(outcome)")
            return
        }

        // 1. The catalog is intact.
        let count = try await offline.repository.cardCount()
        #expect(count == english.count)

        // 2. Text search works, in both stored languages.
        let translated = try #require(italian.first)
        let italianWord = try #require(translated.name.split(separator: " ")
            .map(String.init).max(by: { $0.count < $1.count }))
        let byItalian = try await offline.repository.search(
            CardQuery(text: italianWord, limit: 200)).cards
        #expect(byItalian.contains { $0.id == CardIdentifier(translated.id) })

        // 3. Filters work, alone and combined with a join.
        let spells = try await offline.repository.search(CardQuery(
            filters: { var f = CardFilters(); f.frames = [.spell]; return f }(),
            limit: 200)).cards
        #expect(!spells.isEmpty)

        let tcgMonsters = try await offline.repository.search(CardQuery(
            filters: {
                var f = CardFilters(); f.frames = [.normal, .effect]; f.format = .tcg; return f
            }(), limit: 200)).cards
        #expect(!tcgMonsters.isEmpty)

        // 4. Restriction questions answer, including a user-recorded one.
        let card = try #require(tcgMonsters.first)
        _ = try await offline.repository.banStatus(for: card.id, in: .tcg)
        try await offline.banListEditor.setUserBanStatus(.limited, for: card.id, in: .edison)
        let edison = try await offline.repository.banStatus(for: card.id, in: .edison)
        #expect(edison == .limited)

        // 5. Alternate artwork identifiers still resolve.
        let multi = try #require(english.first { $0.cardImages.count >= 3 })
        let alternate = try #require(multi.cardImages.first { $0.id != multi.id })
        let resolved = try await offline.repository.card(
            withArtwork: ArtworkIdentifier(alternate.id))
        #expect(resolved?.id == CardIdentifier(multi.id))

        // 6. Artwork already on disk is served; what is missing degrades to a
        //    named placeholder rather than a blank tile.
        let storedPath = await offline.artworkStore.storedArtworkPath(
            for: ArtworkIdentifier(multi.id), variant: .thumbnail)
        #expect(storedPath != nil)
        let missingFull = await offline.prefetcher.ensureFullImage(
            for: ArtworkIdentifier(multi.id), cardName: multi.name)
        #expect(missingFull == .placeholder(cardName: multi.name))

        // 7. The browser itself, driven through the same protocols the app uses.
        let model = await BrowserViewModel(
            repository: offline.repository,
            counter: offline.repository,
            artwork: offline.artworkStore,
            banStatusProvider: offline.repository,
            language: .italian)
        await model.search()
        let items = await model.items
        #expect(items.count == english.count)

        // 8. Language switching, with no network to fall back on.
        await model.setLanguage(.english)
        let englishTitles = await model.items.map(\.title)
        #expect(englishTitles.contains(try #require(english.first).name))

        try await offline.database.close()
    }

    /// A first start with no network leaves an empty catalog and says so,
    /// rather than crashing or presenting a half-built one.
    @Test func firstStartWithoutNetworkLeavesAnEmptyCatalogAndReportsIt() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "ygo-cold-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: container) }

        let environment = try CatalogEnvironment.make(
            containerURL: container,
            client: DeadCatalogClient(),
            artworkFetcher: DeadArtworkFetcher(),
            now: { Self.observedAt })

        let outcome = await environment.start()
        guard case .keptStoredCatalog = outcome else {
            Issue.record("atteso keptStoredCatalog, ricevuto \(outcome)")
            return
        }

        let count = try await environment.repository.cardCount()
        #expect(count == 0)

        // Searching an empty catalog is a settled answer, not a crash.
        let search = try await environment.repository.search(CardQuery(text: "dragon"))
        #expect(search == .noMatches)

        try await environment.database.close()
    }
}
