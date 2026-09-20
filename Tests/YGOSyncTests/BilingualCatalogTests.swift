import Foundation
import GRDB
import Testing
import YGOCore
import YGONetworking
import YGOPersistence
@testable import YGOSync

@Suite("Bilingual catalog")
struct BilingualCatalogTests {
    private static let version = CatalogVersion(
        databaseVersion: "147.04", lastUpdate: "2026-09-16 00:05:12")

    private func seeded() async throws -> (DatabaseQueue, SQLiteCatalogStore, StubCatalogClient) {
        let database = try SyncFixture.migratedDatabase()
        let store = SQLiteCatalogStore(database: database)
        let client = StubCatalogClient(
            version: Self.version,
            english: try SyncFixture.cards("catalog-en.json"),
            italian: try SyncFixture.cards("catalog-it.json"))
        _ = try await CatalogSynchronizer(
            client: client, store: store, now: { SyncFixture.observedAt }).synchronize()
        return (database, store, client)
    }

    /// Evidence for R3.AC1: both languages are stored, matched on the card
    /// identifier the localised response carries, and the cards the localised
    /// dataset does not cover keep English text with no Italian alongside it.
    @Test func storesItalianAndEnglishTextJoinedByCardIdentifier() async throws {
        let (database, _, _) = try await seeded()
        let english = try SyncFixture.cards("catalog-en.json")
        let italian = try SyncFixture.cards("catalog-it.json")
        let translatedIDs = Set(italian.map(\.id))

        #expect(english.count > 30)
        #expect(italian.count < english.count)
        #expect(translatedIDs.count < english.count, "la fixture deve avere carte non tradotte")

        try await database.read { db in
            let withItalian = try Int.fetchSet(db, sql:
                "SELECT id FROM card WHERE name_it IS NOT NULL")
            #expect(withItalian == translatedIDs)

            // Every card, translated or not, keeps complete English text.
            let missingEnglish = try Int.fetchOne(db, sql: """
                SELECT count(*) FROM card WHERE name_en IS NULL OR name_en = ''
                   OR desc_en IS NULL
                """)
            #expect(missingEnglish == 0)

            // The stored translation is the localised name, not the English one.
            let sample = try #require(italian.first)
            let storedName = try String.fetchOne(db, sql:
                "SELECT name_it FROM card WHERE id = ?", arguments: [sample.id])
            #expect(storedName == sample.name)
            #expect(sample.nameEn != nil)
        }
    }

    /// A localised row for a card the English dataset does not contain updates
    /// nothing: English decides what exists.
    @Test func discardsLocalisedRowsForUnknownCards() async throws {
        let database = try SyncFixture.migratedDatabase()
        let ghost = try YGOProDeckCatalogClient.decodeDataset(Data("""
        {"data":[{
          "id": 999999999, "name": "Carta Fantasma", "type": "Spell Card",
          "humanReadableCardType": "Normal Spell", "frameType": "spell",
          "desc": "Non esiste.", "race": "Normal", "name_en": "Ghost Card",
          "card_images": [{"id": 999999999}], "card_prices": [{}]
        }]}
        """.utf8))

        let client = StubCatalogClient(
            version: Self.version,
            english: try SyncFixture.cards("catalog-en.json"),
            italian: ghost)

        _ = try await CatalogSynchronizer(
            client: client, store: SQLiteCatalogStore(database: database),
            now: { SyncFixture.observedAt }).synchronize()

        try await database.read { db in
            let ghostRows = try Int.fetchOne(db, sql:
                "SELECT count(*) FROM card WHERE id = 999999999")
            #expect(ghostRows == 0)
            let translated = try Int.fetchOne(db, sql:
                "SELECT count(*) FROM card WHERE name_it IS NOT NULL")
            #expect(translated == 0)
        }
    }

    /// A translation withdrawn upstream must disappear rather than linger as
    /// stale text next to a rewritten English entry.
    @Test func clearsTranslationWhenUpstreamWithdrawsIt() async throws {
        let (database, store, client) = try await seeded()
        let translatedID = try #require(try SyncFixture.cards("catalog-it.json").first?.id)

        try await database.read { db in
            let before = try String.fetchOne(db, sql:
                "SELECT name_it FROM card WHERE id = ?", arguments: [translatedID])
            #expect(before != nil)
        }

        // Upstream publishes a new version whose localised dataset is empty.
        await client.advanceVersion(to: "148.00")
        let emptyItalianClient = StubCatalogClient(
            version: CatalogVersion(databaseVersion: "148.00", lastUpdate: "2026-09-18 00:00:00"),
            english: try SyncFixture.cards("catalog-en.json"),
            italian: [])

        _ = try await CatalogSynchronizer(
            client: emptyItalianClient, store: store,
            now: { SyncFixture.observedAt }).synchronize()

        try await database.read { db in
            let after = try String.fetchOne(db, sql:
                "SELECT name_it FROM card WHERE id = ?", arguments: [translatedID])
            #expect(after == nil)
        }
    }
}
