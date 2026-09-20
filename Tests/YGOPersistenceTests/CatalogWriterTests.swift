import Foundation
import GRDB
import Testing
import YGOCore
import YGONetworking
@testable import YGOPersistence

private enum InjectedFailure: Error { case afterWriting }

@Suite("Catalog writer")
struct CatalogWriterTests {
    private static let observedAt = Date(timeIntervalSince1970: 1_758_000_000)

    private func fixtureCards() throws -> [CatalogCardPayload] {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "fixtures/catalog-en.json")
        return try YGOProDeckCatalogClient.decodeDataset(Data(contentsOf: url))
    }

    private func migratedQueue() throws -> DatabaseQueue {
        var configuration = GRDB.Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: configuration)
        try CatalogSchema.migrator.migrate(queue)
        return queue
    }

    private func seeded() throws -> (DatabaseQueue, [CatalogCardPayload]) {
        let queue = try migratedQueue()
        let cards = try fixtureCards()
        try queue.write { db in
            try CatalogWriter().writeEnglishDataset(cards, observedAt: Self.observedAt, into: db)
        }
        return (queue, cards)
    }

    /// Evidence for R1.AC2: the writer works inside the caller's transaction,
    /// so a failure raised after it has written every card still leaves the
    /// catalog empty. A writer that committed per card would fail here.
    @Test func leavesCatalogEmptyWhenPersistenceFailsPartway() throws {
        let queue = try migratedQueue()
        let cards = try fixtureCards()

        #expect(throws: InjectedFailure.self) {
            try queue.write { db in
                try CatalogWriter().writeEnglishDataset(
                    cards, observedAt: Self.observedAt, into: db)
                throw InjectedFailure.afterWriting
            }
        }

        try queue.read { db in
            for table in ["card", "card_artwork", "card_format", "ban_status",
                          "card_print", "card_price"] {
                let rows = try Int.fetchOne(db, sql: "SELECT count(*) FROM \(table)")
                #expect(rows == 0, "\(table) doveva restare vuota, contiene \(rows ?? -1)")
            }
        }
    }

    /// A malformed dataset must abort the whole write rather than store the
    /// cards that happened to come before the bad one.
    @Test func abortsEntirelyWhenOneCardViolatesAConstraint() throws {
        let queue = try migratedQueue()

        // Two cards claiming the same artwork identifier breaks its primary key.
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
        let cards = try YGOProDeckCatalogClient.decodeDataset(clashing)

        #expect(throws: DatabaseError.self) {
            try queue.write { db in
                try CatalogWriter().writeEnglishDataset(
                    cards, observedAt: Self.observedAt, into: db)
            }
        }

        // The first card was written before the second one failed; the
        // transaction must take it back out again.
        try queue.read { db in
            let storedCards = try Int.fetchOne(db, sql: "SELECT count(*) FROM card")
            #expect(storedCards == 0)
        }
    }

    /// Evidence for R1.AC5: prices are stored with the marketplace they came
    /// from and when they were seen, so a later valuation can say how stale it is.
    @Test func storesPricesWithSourceValueAndObservationTime() throws {
        let (queue, _) = try seeded()

        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT card_id, source, value, observed_at FROM card_price
                """)
            #expect(!rows.isEmpty)

            let expectedText = ISO8601DateFormatter().string(from: Self.observedAt)
            for row in rows {
                #expect((row["value"] as Double) > 0)
                #expect((row["observed_at"] as String) == expectedText)
            }

            let sources = try String.fetchSet(db, sql: "SELECT DISTINCT source FROM card_price")
            #expect(sources.isSubset(of: [
                "cardmarket", "tcgplayer", "ebay", "amazon", "coolstuffinc",
            ]))
            #expect(sources.contains("cardmarket"))
        }
    }

    /// Evidence for R6.AC1: format membership is stored per card, and a format
    /// name the application does not know is skipped rather than stored.
    @Test func storesFormatMembershipPerCard() throws {
        let (queue, cards) = try seeded()

        // Deduplicated on purpose: upstream repeats a format name for a few
        // cards, and the table's primary key forbids the repeat.
        let expected = cards.reduce(into: 0) { total, card in
            total += Set((card.misc?.formats ?? []).compactMap(CardFormat.init(rawValue:))).count
        }

        try queue.read { db in
            let storedFormats = try Int.fetchOne(db, sql: "SELECT count(*) FROM card_format")
            #expect(storedFormats == expected)

            let codes = try String.fetchSet(db, sql: "SELECT DISTINCT format_code FROM card_format")
            #expect(codes.isSubset(of: Set(CardFormat.allCases.map(\.rawValue))))
            #expect(codes.contains(CardFormat.edison.rawValue))
            #expect(codes.contains(CardFormat.masterDuel.rawValue))
        }
    }

    /// Upstream repeats a format name for eight of the fourteen and a half
    /// thousand cards. Storing the repeat would abort the whole seed.
    @Test func storesRepeatedUpstreamFormatNameOnlyOnce() throws {
        let repeated = Data("""
        {"data":[{
          "id": 89631139, "name": "Blue-Eyes White Dragon", "type": "Normal Monster",
          "humanReadableCardType": "Normal Monster", "frameType": "normal",
          "desc": "A legendary dragon.", "race": "Dragon",
          "card_images": [{"id": 89631139}], "card_prices": [{}],
          "misc_info": [{"formats": ["Speed Duel", "TCG", "Speed Duel"], "has_effect": 0}]
        }]}
        """.utf8)
        let cards = try YGOProDeckCatalogClient.decodeDataset(repeated)
        let queue = try migratedQueue()

        try queue.write { db in
            try CatalogWriter().writeEnglishDataset(cards, observedAt: Self.observedAt, into: db)
        }

        try queue.read { db in
            let codes = try String.fetchAll(db, sql:
                "SELECT format_code FROM card_format WHERE card_id = 89631139 ORDER BY format_code")
            #expect(codes == ["Speed Duel", "TCG"])
        }
    }

    /// Evidence for R6.AC2: upstream restrictions are stored, tagged as coming
    /// from upstream, and only for the three formats that publish a list.
    @Test func storesUpstreamBanStatusesWithUpstreamSource() throws {
        let (queue, cards) = try seeded()

        let expected = cards.reduce(into: 0) { total, card in
            for text in [card.banlistInfo?.banTcg, card.banlistInfo?.banOcg,
                         card.banlistInfo?.banGoat] where
                CatalogWriter.banStatus(fromUpstream: text) != nil {
                total += 1
            }
        }
        #expect(expected > 0, "la fixture deve contenere carte con restrizioni")

        try queue.read { db in
            let storedBans = try Int.fetchOne(db, sql: "SELECT count(*) FROM ban_status")
            #expect(storedBans == expected)

            let sources = try String.fetchSet(db, sql: "SELECT DISTINCT source FROM ban_status")
            #expect(sources == ["upstream"])

            let formats = try String.fetchSet(db, sql: "SELECT DISTINCT format_code FROM ban_status")
            #expect(formats.isSubset(of: ["TCG", "OCG", "GOAT"]))

            let statuses = try String.fetchSet(db, sql: "SELECT DISTINCT status FROM ban_status")
            #expect(statuses.isSubset(of: ["forbidden", "limited", "semi_limited"]))
        }
    }

    /// Evidence for R7.AC1: every artwork the upstream source publishes is
    /// stored against the card it depicts, including the ones whose identifier
    /// differs from the card's own.
    @Test func storesEveryArtworkIdentifierAgainstItsCard() throws {
        let (queue, cards) = try seeded()

        let expected = cards.reduce(into: 0) { $0 += $1.cardImages.count }

        try queue.read { db in
            let storedArtworks = try Int.fetchOne(db, sql: "SELECT count(*) FROM card_artwork")
            #expect(storedArtworks == expected)

            // A card with several artworks must map all of them to itself.
            let multi = try #require(cards.first { $0.cardImages.count >= 3 })
            let mapped = try Int.fetchSet(db, sql:
                "SELECT artwork_id FROM card_artwork WHERE card_id = ?", arguments: [multi.id])
            #expect(mapped == Set(multi.cardImages.map(\.id)))
            #expect(mapped.count >= 3)

            // At least one alternate artwork differs from its card's identifier,
            // which is the case that breaks a naive importer.
            let alternates = try Int.fetchOne(db, sql:
                "SELECT count(*) FROM card_artwork WHERE artwork_id <> card_id")
            #expect((alternates ?? 0) > 0)
        }
    }

    /// Re-running the writer must converge rather than accumulate duplicates.
    @Test func rewritingTheSameDatasetIsIdempotent() throws {
        let (queue, cards) = try seeded()

        let counts = { (db: Database) throws -> [Int] in
            try ["card", "card_artwork", "card_format", "ban_status",
                 "card_print", "card_price"].map {
                try Int.fetchOne(db, sql: "SELECT count(*) FROM \($0)") ?? -1
            }
        }
        let before = try queue.read(counts)

        try queue.write { db in
            try CatalogWriter().writeEnglishDataset(cards, observedAt: Self.observedAt, into: db)
        }

        let after = try queue.read(counts)
        #expect(after == before)
    }
}
