import Foundation
import YGOCore

/// Decides whether the catalog needs seeding, updating, or leaving alone, and
/// carries out whichever it is.
///
/// Seeding and updating deliberately share one code path. The only difference
/// is the starting condition, so there is one rollback story rather than two,
/// and `R1.AC2` and `R2.AC7` are satisfied by the same transaction boundary.
public actor CatalogSynchronizer: CatalogSyncing {
    private let client: any CatalogFetching
    private let store: any CatalogStore
    private let observe: @Sendable (CatalogSyncProgress) -> Void
    private let now: @Sendable () -> Date

    public init(
        client: any CatalogFetching,
        store: any CatalogStore,
        now: @escaping @Sendable () -> Date = Date.init,
        observe: @escaping @Sendable (CatalogSyncProgress) -> Void = { _ in }
    ) {
        self.client = client
        self.store = store
        self.now = now
        self.observe = observe
    }

    public func synchronize() async throws -> CatalogSyncOutcome {
        let storedCards = try await store.cardCount()
        return storedCards == 0 ? try await seed() : try await update()
    }

    // MARK: - Seeding

    /// An empty catalog has nothing to protect and nothing to compare against,
    /// so it goes straight for the dataset.
    private func seed() async throws -> CatalogSyncOutcome {
        let version: CatalogVersion
        let dataset: CatalogDataset
        do {
            observe(.init(stage: .checkingVersion))
            version = try await client.fetchVersion()
            dataset = try await download(version: version)
        } catch {
            // Nothing was written, so the catalog is still empty and the user
            // can simply try again.
            throw CatalogSyncFailure(stage: .downloading, underlying: error, isRetryable: true)
        }

        try await storeDataset(dataset)
        observe(.init(stage: .finished, completed: dataset.english.count,
                      total: dataset.english.count))
        return .seeded(cardCount: dataset.english.count)
    }

    // MARK: - Updating

    /// A populated catalog asks for the version stamp first: eighty bytes to
    /// decide whether forty megabytes are needed at all.
    private func update() async throws -> CatalogSyncOutcome {
        observe(.init(stage: .checkingVersion))

        let upstreamVersion: CatalogVersion
        do {
            upstreamVersion = try await client.fetchVersion()
        } catch {
            // Freshness is optional; usability is not. The stored catalog
            // answers every query without upstream.
            observe(.init(stage: .finished))
            return .keptStoredCatalog(reason: String(describing: error))
        }

        let stored = try await store.storedVersion()
        guard stored?.databaseVersion != upstreamVersion.databaseVersion else {
            observe(.init(stage: .finished))
            return .alreadyCurrent
        }

        let dataset: CatalogDataset
        do {
            dataset = try await download(version: upstreamVersion)
        } catch {
            observe(.init(stage: .finished))
            return .keptStoredCatalog(reason: String(describing: error))
        }

        // From here a failure must leave the previous catalog untouched, which
        // is the store's transaction to honour.
        try await storeDataset(dataset)
        observe(.init(stage: .finished, completed: dataset.english.count,
                      total: dataset.english.count))
        return .updated(cardCount: dataset.english.count)
    }

    // MARK: - Shared steps

    private func download(version: CatalogVersion) async throws -> CatalogDataset {
        observe(.init(stage: .downloading))
        let english = try await client.fetchDataset(language: .english)
        let italian = try await client.fetchDataset(language: .italian)
        return CatalogDataset(
            english: english, italian: italian, version: version, observedAt: now())
    }

    private func storeDataset(_ dataset: CatalogDataset) async throws {
        let observe = self.observe
        do {
            try await store.apply(dataset) { progress in observe(progress) }
        } catch {
            // A storage failure is not a network hiccup; retrying the same
            // payload will hit the same constraint.
            throw CatalogSyncFailure(stage: .storing, underlying: error, isRetryable: false)
        }
    }
}
