import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOSync

@Suite("Catalog seed")
struct CatalogSeedTests {
    private static let version = CatalogVersion(
        databaseVersion: "147.04", lastUpdate: "2026-09-16 00:05:12")

    private func makeClient(
        versionFailure: StubError? = nil,
        datasetFailure: StubError? = nil
    ) throws -> StubCatalogClient {
        StubCatalogClient(
            version: Self.version,
            english: try SyncFixture.cards("catalog-en.json"),
            italian: try SyncFixture.cards("catalog-it.json"),
            versionFailure: versionFailure,
            datasetFailure: datasetFailure)
    }

    /// Evidence for R1.AC1: an empty catalog is filled from the full dataset,
    /// and a catalog that is already current does not download it again.
    @Test func retrievesFullDatasetOnlyWhenCatalogIsEmpty() async throws {
        let database = try SyncFixture.migratedDatabase()
        let store = SQLiteCatalogStore(database: database)
        let client = try makeClient()

        let first = try await CatalogSynchronizer(
            client: client, store: store, now: { SyncFixture.observedAt }).synchronize()

        #expect(first == .seeded(cardCount: SyncFixture.englishCardCount))
        let storedCards = try await store.cardCount()
        #expect(storedCards == SyncFixture.englishCardCount)
        let downloadsAfterSeed = await client.datasetRequestCount
        #expect(downloadsAfterSeed > 0)

        // A second run against the now-populated catalog, with upstream
        // reporting the same version, must not fetch the dataset again.
        let second = try await CatalogSynchronizer(
            client: client, store: store, now: { SyncFixture.observedAt }).synchronize()

        #expect(second == .alreadyCurrent)
        let downloadsAfterSecondRun = await client.datasetRequestCount
        #expect(downloadsAfterSecondRun == downloadsAfterSeed)
    }

    /// Evidence for R1.AC3: seeding reports which stage it is in and a share of
    /// the work that grows, rather than an undifferentiated busy state.
    @Test func reportsStageAndIncreasingProportionWhileSeeding() async throws {
        let database = try SyncFixture.migratedDatabase()
        let recorder = ProgressRecorder()

        _ = try await CatalogSynchronizer(
            client: try makeClient(),
            store: SQLiteCatalogStore(database: database),
            now: { SyncFixture.observedAt },
            observe: recorder.observer).synchronize()

        let reports = recorder.recorded
        let stages = reports.map(\.stage)
        #expect(stages.contains(.checkingVersion))
        #expect(stages.contains(.downloading))
        #expect(stages.contains(.storing))
        #expect(stages.last == .finished)

        // The storing stage must actually count its way up, not jump from
        // nothing to everything.
        let storing = reports.filter { $0.stage == .storing }
        #expect(storing.count > 2)
        let proportions = storing.map(\.proportion)
        #expect(proportions == proportions.sorted())
        #expect(proportions.first == 0)
        #expect(proportions.last == 1)
    }

    /// Evidence for R1.AC4: a failed download leaves nothing behind and says
    /// the attempt is worth repeating.
    @Test func leavesCatalogEmptyAndOffersRetryWhenRetrievalFails() async throws {
        let database = try SyncFixture.migratedDatabase()
        let store = SQLiteCatalogStore(database: database)

        var caught: CatalogSyncFailure?
        do {
            _ = try await CatalogSynchronizer(
                client: try makeClient(datasetFailure: .unreachable),
                store: store,
                now: { SyncFixture.observedAt }).synchronize()
        } catch let failure as CatalogSyncFailure {
            caught = failure
        }

        let failure = try #require(caught)
        #expect(failure.stage == .downloading)
        #expect(failure.isRetryable)
        #expect(failure.underlying as? StubError == .unreachable)

        let storedCards = try await store.cardCount()
        #expect(storedCards == 0)
        let storedVersion = try await store.storedVersion()
        #expect(storedVersion == nil)
    }

    /// A storage failure is a different kind of problem: repeating it would hit
    /// the same constraint, so it must not be reported as retryable.
    @Test func reportsStorageFailureAsNotRetryable() async throws {
        let database = try SyncFixture.migratedDatabase()
        let store = RefusingCatalogStore(wrapped: SQLiteCatalogStore(database: database))

        var caught: CatalogSyncFailure?
        do {
            _ = try await CatalogSynchronizer(
                client: try makeClient(), store: store,
                now: { SyncFixture.observedAt }).synchronize()
        } catch let failure as CatalogSyncFailure {
            caught = failure
        }

        let failure = try #require(caught)
        #expect(failure.stage == .storing)
        #expect(!failure.isRetryable)

        let storedCards = try await store.cardCount()
        #expect(storedCards == 0)
    }
}
