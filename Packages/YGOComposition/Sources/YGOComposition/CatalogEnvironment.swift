import Foundation
import GRDB
import YGOCore
import YGOImageStore
import YGONetworking
import YGOPersistence
import YGODeckIO
import YGOSync
import YGOValidation

/// The composition root: the one place that binds protocols to concrete
/// implementations.
///
/// Everything above it depends on protocols only, which is why the feature
/// modules can be tested without SQLite or a network, and why this whole graph
/// can be rebuilt against failing stubs to prove the application works offline.
public struct CatalogEnvironment: Sendable {
    public let database: DatabasePool
    public let repository: SQLiteCardRepository
    public let catalogStore: SQLiteCatalogStore
    public let banListEditor: SQLiteBanListEditor
    public let artworkStore: ArtworkStore
    public let artworkPresence: SQLiteArtworkPresence
    public let synchronizer: CatalogSynchronizer
    public let prefetcher: ArtworkPrefetcher
    public let deckRepository: SQLiteDeckRepository
    public let deckValidator: DeckValidator
    public let deckImporter: DeckImporter
    public let collection: SQLiteCollectionRepository

    /// Where the application keeps its data on a real machine.
    public static func defaultContainerURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
            .appending(path: "YGODeckManager")
    }

    /// The real graph: SQLite on disk, artwork on disk, upstream over HTTP.
    ///
    /// Both clients share one rate limiter, because the upstream ceiling counts
    /// every request together rather than one budget per kind of resource.
    public static func live(
        containerURL: URL? = nil,
        observeSync: @escaping @Sendable (CatalogSyncProgress) -> Void = { _ in },
        observePrefetch: @escaping @Sendable (ArtworkPrefetcher.Progress) -> Void = { _ in }
    ) throws -> CatalogEnvironment {
        let container = try containerURL ?? defaultContainerURL()
        let limiter = RateLimiter()
        let transport = URLSessionCatalogTransport(limiter: limiter)

        return try make(
            containerURL: container,
            client: YGOProDeckCatalogClient(transport: transport),
            artworkFetcher: URLSessionArtworkFetcher(transport: transport),
            observeSync: observeSync,
            observePrefetch: observePrefetch)
    }

    /// The same graph with the two upstream seams substituted, which is what
    /// lets an integration test cut the network entirely.
    public static func make(
        containerURL: URL,
        client: any CatalogFetching,
        artworkFetcher: any ArtworkFetching,
        now: @escaping @Sendable () -> Date = Date.init,
        observeSync: @escaping @Sendable (CatalogSyncProgress) -> Void = { _ in },
        observePrefetch: @escaping @Sendable (ArtworkPrefetcher.Progress) -> Void = { _ in }
    ) throws -> CatalogEnvironment {
        let database = try DatabaseBootstrapper(
            configuration: .init(containerURL: containerURL)).open()

        let repository = SQLiteCardRepository(database: database)
        let catalogStore = SQLiteCatalogStore(database: database)
        let presence = SQLiteArtworkPresence(database: database)
        let artworkStore = ArtworkStore(
            rootURL: containerURL.appending(path: "Artwork"), presence: presence, now: now)

        let deckRepository = SQLiteDeckRepository(database: database, now: now)
        let deckValidator = DeckValidator()

        return CatalogEnvironment(
            database: database,
            repository: repository,
            catalogStore: catalogStore,
            banListEditor: SQLiteBanListEditor(database: database),
            artworkStore: artworkStore,
            artworkPresence: presence,
            synchronizer: CatalogSynchronizer(
                client: client, store: catalogStore, now: now, observe: observeSync),
            prefetcher: ArtworkPrefetcher(
                store: artworkStore, presence: presence,
                fetcher: artworkFetcher, observe: observePrefetch),
            deckRepository: deckRepository,
            deckValidator: deckValidator,
            deckImporter: DeckImporter(repository: deckRepository, validator: deckValidator),
            collection: SQLiteCollectionRepository(database: database))
    }

    /// Runs the startup flow: bring the catalog up to date if upstream allows,
    /// then fill in missing artwork in the background.
    ///
    /// Neither step is allowed to stop the application from opening. An
    /// unreachable upstream costs freshness, never usability.
    @discardableResult
    public func start() async -> CatalogSyncOutcome {
        let outcome: CatalogSyncOutcome
        do {
            outcome = try await synchronizer.synchronize()
        } catch let failure as CatalogSyncFailure {
            return .keptStoredCatalog(reason: String(describing: failure.underlying))
        } catch {
            return .keptStoredCatalog(reason: String(describing: error))
        }

        // Artwork fills in behind the interface rather than in front of it.
        Task.detached(priority: .background) { [prefetcher] in
            _ = try? await prefetcher.prefetchThumbnails()
        }

        return outcome
    }
}
