import Foundation
import GRDB
import Testing
import YGOCore
import YGONetworking
import YGOPersistence
@testable import YGOSync

@Suite("Catalog update")
struct CatalogUpdateTests {
    private static let firstVersion = CatalogVersion(
        databaseVersion: "147.04", lastUpdate: "2026-09-16 00:05:12")

    /// A catalog already seeded at `firstVersion`, plus the client that seeded it.
    private func seededCatalog() async throws -> (DatabaseQueue, SQLiteCatalogStore, StubCatalogClient) {
        let database = try SyncFixture.migratedDatabase()
        let store = SQLiteCatalogStore(database: database)
        let client = StubCatalogClient(
            version: Self.firstVersion,
            english: try SyncFixture.cards("catalog-en.json"),
            italian: try SyncFixture.cards("catalog-it.json"))

        let outcome = try await CatalogSynchronizer(
            client: client, store: store, now: { SyncFixture.observedAt }).synchronize()
        #expect(outcome == .seeded(cardCount: SyncFixture.englishCardCount))

        return (database, store, client)
    }

    private func synchronizer(
        _ client: StubCatalogClient,
        _ store: any CatalogStore
    ) -> CatalogSynchronizer {
        CatalogSynchronizer(client: client, store: store, now: { SyncFixture.observedAt })
    }

    /// Evidence for R2.AC2: a new upstream version brings changed fields in,
    /// while cards it did not touch keep what they had.
    @Test func upsertsChangedCardsWhenUpstreamVersionDiffers() async throws {
        let (database, store, client) = try await seededCatalog()

        var cards = try SyncFixture.cards("catalog-en.json")
        let target = cards[0]
        let untouched = cards[1]
        let renamed = Data("""
        {"data":[{
          "id": \(target.id), "name": "Renamed By Upstream", "type": "\(target.type)",
          "humanReadableCardType": "\(target.humanReadableCardType)",
          "frameType": "\(target.frameType)", "desc": "Rewritten text.",
          "race": "\(target.race)",
          "card_images": [{"id": \(target.id)}], "card_prices": [{}]
        }]}
        """.utf8)
        cards[0] = try #require(try YGOProDeckCatalogClient.decodeDataset(renamed).first)

        await client.replaceEnglish(with: cards)
        await client.advanceVersion(to: "148.00")

        let expectedTotal = cards.count
        let outcome = try await synchronizer(client, store).synchronize()
        #expect(outcome == .updated(cardCount: expectedTotal))

        try await database.read { db in
            let changed = try Row.fetchOne(db, sql:
                "SELECT name_en, desc_en FROM card WHERE id = ?", arguments: [target.id])
            #expect(changed?["name_en"] == "Renamed By Upstream")
            #expect(changed?["desc_en"] == "Rewritten text.")

            let kept = try Row.fetchOne(db, sql:
                "SELECT name_en FROM card WHERE id = ?", arguments: [untouched.id])
            #expect(kept?["name_en"] == untouched.name)

            let total = try Int.fetchOne(db, sql: "SELECT count(*) FROM card")
            #expect(total == expectedTotal)
        }
    }

    /// Evidence for R2.AC3: matching versions cost one small request and
    /// nothing else.
    @Test func skipsDatasetRequestWhenVersionsMatch() async throws {
        let (_, store, client) = try await seededCatalog()
        let downloadsAfterSeed = await client.datasetRequestCount

        let outcome = try await synchronizer(client, store).synchronize()

        #expect(outcome == .alreadyCurrent)
        let downloadsAfterCheck = await client.datasetRequestCount
        #expect(downloadsAfterCheck == downloadsAfterSeed)
        let calls = await client.calls
        #expect(calls.last == .version)
    }

    /// Evidence for R2.AC4: a completed update records what it synchronised to
    /// and when, inside the same transaction as the cards.
    @Test func storesVersionAndCompletionTimeAfterUpdate() async throws {
        let (database, store, client) = try await seededCatalog()
        await client.advanceVersion(to: "149.12")

        _ = try await synchronizer(client, store).synchronize()

        let stored = try await store.storedVersion()
        #expect(stored?.databaseVersion == "149.12")
        #expect(stored?.lastUpdate == "2026-09-18 00:00:00")

        try await database.read { db in
            let syncedAt = try String.fetchOne(db, sql:
                "SELECT last_sync_at FROM sync_state WHERE id = 1")
            #expect(syncedAt == ISO8601DateFormatter().string(from: SyncFixture.observedAt))
        }
    }

    /// Evidence for R2.AC5: upstream being unreachable costs freshness, never
    /// the ability to use the application.
    @Test func startsOnStoredCatalogWhenVersionRequestFails() async throws {
        let (_, store, _) = try await seededCatalog()

        let offlineClient = StubCatalogClient(
            version: Self.firstVersion, english: [], versionFailure: .unreachable)

        let outcome = try await synchronizer(offlineClient, store).synchronize()

        guard case .keptStoredCatalog = outcome else {
            Issue.record("atteso keptStoredCatalog, ricevuto \(outcome)")
            return
        }

        // The catalog is still fully usable.
        let storedCards = try await store.cardCount()
        #expect(storedCards == SyncFixture.englishCardCount)
        let storedVersion = try await store.storedVersion()
        #expect(storedVersion?.databaseVersion == "147.04")

        // No dataset was attempted: there was no version to compare against.
        let downloads = await offlineClient.datasetRequestCount
        #expect(downloads == 0)
    }

    /// Evidence for R2.AC6: refreshing on demand is the same path as starting,
    /// not a second implementation that could drift from it.
    @Test func userRefreshPerformsSameVersionCheckAsStartup() async throws {
        let (_, store, client) = try await seededCatalog()

        let onStartup = try await synchronizer(client, store).synchronize()
        let callsAfterStartup = await client.calls

        await client.advanceVersion(to: "150.00")
        let onRefresh = try await synchronizer(client, store).synchronize()
        let callsAfterRefresh = await client.calls

        #expect(onStartup == .alreadyCurrent)
        #expect(onRefresh == .updated(cardCount: SyncFixture.englishCardCount))

        // Both began with a version request; only the one that found a
        // difference went on to the dataset.
        #expect(callsAfterStartup.last == .version)
        let newCalls = Array(callsAfterRefresh.dropFirst(callsAfterStartup.count))
        #expect(newCalls.first == .version)
        #expect(newCalls.contains(.dataset(.english)))
    }

    /// Evidence for R2.AC7: an update that cannot be stored leaves the catalog
    /// exactly as it was, down to the version it claims.
    @Test func retainsPriorCatalogWhenUpsertFails() async throws {
        let (database, store, client) = try await seededCatalog()

        // Rows cannot cross an async boundary, so the snapshot is reduced to
        // plain values inside the read.
        let before = try await database.read { db in
            try String.fetchAll(db, sql:
                "SELECT id || '|' || name_en FROM card ORDER BY id")
        }
        let versionBefore = try await store.storedVersion()

        // Two cards claiming one artwork identifier: the write aborts part way.
        let clashing = Data("""
        {"data":[
          {"id": 1, "name": "First", "type": "Spell Card",
           "humanReadableCardType": "Normal Spell", "frameType": "spell",
           "desc": "A", "race": "Normal",
           "card_images": [{"id": 900}], "card_prices": [{}]},
          {"id": 2, "name": "Second", "type": "Spell Card",
           "humanReadableCardType": "Normal Spell", "frameType": "spell",
           "desc": "B", "race": "Normal",
           "card_images": [{"id": 900}], "card_prices": [{}]}
        ]}
        """.utf8)
        await client.replaceEnglish(with: try YGOProDeckCatalogClient.decodeDataset(clashing))
        await client.advanceVersion(to: "151.00")

        var caught: CatalogSyncFailure?
        do {
            _ = try await synchronizer(client, store).synchronize()
        } catch let failure as CatalogSyncFailure {
            caught = failure
        }

        #expect(caught?.stage == .storing)

        let after = try await database.read { db in
            try String.fetchAll(db, sql:
                "SELECT id || '|' || name_en FROM card ORDER BY id")
        }
        #expect(after == before)
        let versionAfter = try await store.storedVersion()
        #expect(versionAfter == versionBefore)
    }
}
