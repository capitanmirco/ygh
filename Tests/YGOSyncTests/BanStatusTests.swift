import Foundation
import GRDB
import Testing
import YGOCore
import YGONetworking
import YGOPersistence
@testable import YGOSync

@Suite("Ban status")
struct BanStatusTests {
    private struct Catalog {
        let database: DatabaseQueue
        let repository: SQLiteCardRepository
        let editor: SQLiteBanListEditor
        let store: SQLiteCatalogStore
        let client: StubCatalogClient
        let english: [CatalogCardPayload]
    }

    private func seeded() async throws -> Catalog {
        let database = try SyncFixture.migratedDatabase()
        let store = SQLiteCatalogStore(database: database)
        let english = try SyncFixture.cards("catalog-en.json")
        let client = StubCatalogClient(
            version: CatalogVersion(databaseVersion: "147.04", lastUpdate: ""),
            english: english,
            italian: try SyncFixture.cards("catalog-it.json"))

        _ = try await CatalogSynchronizer(
            client: client, store: store, now: { SyncFixture.observedAt }).synchronize()

        return Catalog(
            database: database,
            repository: SQLiteCardRepository(database: database),
            editor: SQLiteBanListEditor(database: database),
            store: store, client: client, english: english)
    }

    /// A card the upstream ban list does not mention at all.
    private func unrestrictedCard(_ catalog: Catalog) throws -> CatalogCardPayload {
        try #require(catalog.english.first { $0.banlistInfo == nil })
    }

    /// Evidence for R6.AC3: the upstream source publishes only the three
    /// restricting statuses, so a card with no entry is unrestricted rather
    /// than unknown.
    @Test func reportsUnlimitedWhenNoBanRowExists() async throws {
        let catalog = try await seeded()
        let card = try unrestrictedCard(catalog)

        for format in CardFormat.allCases {
            let status = try await catalog.repository.banStatus(
                for: CardIdentifier(card.id), in: format)
            #expect(status == .unlimited)
            #expect(status.copyAllowance.maximumCopies == 3)
        }

        // A card the upstream list does restrict reports that restriction.
        let restricted = try #require(catalog.english.first { $0.banlistInfo?.banTcg != nil })
        let tcgStatus = try await catalog.repository.banStatus(
            for: CardIdentifier(restricted.id), in: .tcg)
        #expect(tcgStatus != .unlimited)
    }

    /// Evidence for R6.AC4: the formats upstream leaves empty accept entries
    /// from the user, and those survive a restart of the store.
    @Test func persistsUserRecordedStatusForFormatWithoutUpstreamData() async throws {
        let catalog = try await seeded()
        let card = try unrestrictedCard(catalog)
        let identifier = CardIdentifier(card.id)

        try await catalog.editor.setUserBanStatus(.limited, for: identifier, in: .edison)
        try await catalog.editor.setUserBanStatus(.semiLimited, for: identifier, in: .masterDuel)

        var edison = try await catalog.repository.banStatus(for: identifier, in: .edison)
        var masterDuel = try await catalog.repository.banStatus(for: identifier, in: .masterDuel)
        #expect(edison == .limited)
        #expect(masterDuel == .semiLimited)

        // Amending an entry replaces it rather than adding a second one.
        try await catalog.editor.setUserBanStatus(.forbidden, for: identifier, in: .edison)
        edison = try await catalog.repository.banStatus(for: identifier, in: .edison)
        #expect(edison == .forbidden)

        // Setting a card back to unrestricted removes the row, because the
        // schema stores only the three restricting statuses.
        try await catalog.editor.setUserBanStatus(.unlimited, for: identifier, in: .masterDuel)
        masterDuel = try await catalog.repository.banStatus(for: identifier, in: .masterDuel)
        #expect(masterDuel == .unlimited)

        try await catalog.database.read { db in
            let rows = try Int.fetchOne(db, sql: """
                SELECT count(*) FROM ban_status WHERE card_id = ? AND source = 'user'
                """, arguments: [card.id])
            #expect(rows == 1)
        }
    }

    /// One card may hold one row per format. A hand-written TCG entry would
    /// therefore block the update that is meant to overwrite it, so the formats
    /// upstream maintains refuse user entries outright.
    @Test func refusesUserEntryForFormatMaintainedUpstream() async throws {
        let catalog = try await seeded()
        let identifier = CardIdentifier(try unrestrictedCard(catalog).id)

        for format in CardFormat.allCases where format.hasUpstreamBanList {
            await #expect(throws: BanListEditingError.formatIsMaintainedUpstream(format)) {
                try await catalog.editor.setUserBanStatus(.limited, for: identifier, in: format)
            }
        }
    }

    /// Evidence for R6.AC5: an update replaces every upstream restriction while
    /// the user's own entries come through untouched.
    @Test func retainsUserStatusesWhileReplacingUpstreamOnes() async throws {
        let catalog = try await seeded()
        let card = try unrestrictedCard(catalog)
        let identifier = CardIdentifier(card.id)

        try await catalog.editor.setUserBanStatus(.forbidden, for: identifier, in: .edison)
        try await catalog.editor.setUserBanStatus(.limited, for: identifier, in: .masterDuel)

        // Upstream publishes a new version in which this card is now Limited in
        // TCG, and some previously restricted card is no longer listed.
        var revised = catalog.english
        let index = try #require(revised.firstIndex { $0.id == card.id })
        let payload = revised[index]
        revised[index] = try #require(try YGOProDeckCatalogClient.decodeDataset(Data("""
        {"data":[{
          "id": \(payload.id), "name": "\(payload.name)", "type": "\(payload.type)",
          "humanReadableCardType": "\(payload.humanReadableCardType)",
          "frameType": "\(payload.frameType)", "desc": "unchanged",
          "race": "\(payload.race)",
          "card_images": [{"id": \(payload.id)}], "card_prices": [{}],
          "banlist_info": {"ban_tcg": "Limited"}
        }]}
        """.utf8)).first)

        await catalog.client.replaceEnglish(with: revised)
        await catalog.client.advanceVersion(to: "148.00")
        let outcome = try await CatalogSynchronizer(
            client: catalog.client, store: catalog.store,
            now: { SyncFixture.observedAt }).synchronize()
        #expect(outcome == .updated(cardCount: revised.count))

        // Upstream data moved.
        let tcg = try await catalog.repository.banStatus(for: identifier, in: .tcg)
        #expect(tcg == .limited)

        // User data did not.
        let edison = try await catalog.repository.banStatus(for: identifier, in: .edison)
        let masterDuel = try await catalog.repository.banStatus(for: identifier, in: .masterDuel)
        #expect(edison == .forbidden)
        #expect(masterDuel == .limited)

        try await catalog.database.read { db in
            let userRows = try Int.fetchOne(db, sql:
                "SELECT count(*) FROM ban_status WHERE source = 'user'")
            #expect(userRows == 2)
        }
    }

    /// Evidence for R6.AC6 against stored data rather than the enum alone.
    @Test func reportsCopyAllowanceMatchingTheStoredStatus() async throws {
        let catalog = try await seeded()
        let identifier = CardIdentifier(try unrestrictedCard(catalog).id)

        let expected: [(BanStatus, Int)] = [
            (.forbidden, 0), (.limited, 1), (.semiLimited, 2), (.unlimited, 3),
        ]

        for (status, copies) in expected {
            try await catalog.editor.setUserBanStatus(status, for: identifier, in: .edison)
            let read = try await catalog.repository.banStatus(for: identifier, in: .edison)
            #expect(read == status)
            #expect(read.copyAllowance.maximumCopies == copies)
        }
    }
}
