import Foundation
import GRDB
import Testing
import YGOCore
@testable import YGOPersistence

@Suite("Banlist provenance")
struct BanlistProvenanceTests {
    private static let fixtures: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "fixtures")
        .appending(path: "banlist")

    /// The catalog's own current TCG list, recorded from YGOPRODeck. A second
    /// upstream, so comparing the two is a real check rather than a query
    /// compared against itself.
    private struct CatalogBanList: Decodable {
        struct Card: Decodable {
            let id: Int
            let name: String
            let konami_id: Int?
            let ban_tcg: String?
        }
        let cards: [Card]
    }

    private func catalogCurrentTCG() throws -> [CatalogBanList.Card] {
        try JSONDecoder().decode(CatalogBanList.self, from: Data(contentsOf:
            Self.fixtures.appending(path: "catalog-current-tcg.json"))).cards
    }

    private func published(_ format: BanlistFormat, _ date: String) throws -> PublishedBanlist {
        try JSONDecoder().decode(PublishedBanlist.self, from: Data(contentsOf: Self.fixtures
            .appending(path: format.rawValue)
            .appending(path: "\(date).vector.json")))
    }

    private func migratedQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)
        return queue
    }

    private func insertCard(
        _ queue: DatabaseQueue, id: Int, konamiID: Int?, name: String,
        catalogStatus: BanStatus = .unlimited, format: CardFormat = .tcg
    ) throws {
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                  human_readable_type, konami_id)
                VALUES (?, ?, '', 'Spell Card', 'spell', 'Spell Card', ?)
                """, arguments: [id, name, konamiID])
            if let stored = catalogStatus.storedValue {
                try db.execute(sql: """
                    INSERT INTO ban_status (card_id, format_code, status, source)
                    VALUES (?, ?, ?, 'upstream')
                    """, arguments: [id, format.rawValue, stored])
            }
        }
    }

    /// Evidence for R4.AC1: a history says who published it, and it is not the
    /// card catalog. A reader weighing a historical claim needs to know that.
    @Test func namesASourceThatIsNotTheCatalogs() throws {
        let queue = try migratedQueue()
        let history = SQLiteBanlistHistory(database: queue)
        try history.store(published(.tcg, "2005-03-01"), format: .tcg,
                          source: "yaml-yugi-limit-regulation",
                          fetchedAt: Date(timeIntervalSince1970: 1_758_441_600))

        let provenance = try history.provenance(for: .tcg)

        #expect(provenance.sources == ["yaml-yugi-limit-regulation"])
        #expect(!provenance.sources.contains("ygoprodeck"))
        #expect(provenance.revisionCount == 1)
        #expect(provenance.newestList == "2005-03-01")
        #expect(!provenance.isEmpty)

        // A format nothing was stored for says so rather than inventing one.
        let empty = try history.provenance(for: .rush)
        #expect(empty.isEmpty)
        #expect(empty.sources.isEmpty)
        #expect(empty.lastSynchronised == nil)
    }

    /// Evidence for R4.AC2: the history carries its own freshness. The catalog
    /// may have been synchronised yesterday and the history last year, and a
    /// panel showing both must not present one date as though it covered both.
    @Test func carriesItsOwnLastSynchronisationIndependentOfTheCatalogs() throws {
        let queue = try migratedQueue()
        let history = SQLiteBanlistHistory(database: queue)

        try history.store(published(.tcg, "2005-03-01"), format: .tcg,
                          source: "yaml-yugi-limit-regulation",
                          fetchedAt: Date(timeIntervalSince1970: 1_600_000_000))
        try history.store(published(.tcg, "2005-09-01"), format: .tcg,
                          source: "yaml-yugi-limit-regulation",
                          fetchedAt: Date(timeIntervalSince1970: 1_758_441_600))

        let provenance = try history.provenance(for: .tcg)
        let last = try #require(provenance.lastSynchronised)

        // The most recent read, not the first one and not the list's own date.
        #expect(last.hasPrefix("2025-09-21"))
        #expect(last != provenance.newestList)
        #expect(provenance.revisionCount == 2)

        // The catalog's own sync state is a different record entirely, and an
        // empty one here does not make the history undated.
        let catalogSyncRows = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_state")
        }
        #expect(catalogSyncRows == 0)
        #expect(provenance.lastSynchronised != nil)
    }

    /// Evidence for R4.AC3: where the two sources differ, both figures are
    /// named. Neither is silently preferred, because the catalog's table is a
    /// certified contract and the history is a second opinion.
    @Test func reportsADisagreementNamingBothStatuses() throws {
        let queue = try migratedQueue()
        let history = SQLiteBanlistHistory(database: queue)

        // Agreeing, disagreeing, catalog-only, history-only, and no konami_id.
        try insertCard(queue, id: 1, konamiID: 100, name: "Agreed Card",
                       catalogStatus: .limited)
        try insertCard(queue, id: 2, konamiID: 200, name: "Disputed Card",
                       catalogStatus: .forbidden)
        try insertCard(queue, id: 3, konamiID: 300, name: "Catalog Only",
                       catalogStatus: .semiLimited)
        try insertCard(queue, id: 4, konamiID: 400, name: "History Only")
        try insertCard(queue, id: 5, konamiID: nil, name: "Untracked Card",
                       catalogStatus: .forbidden)

        try history.store(
            PublishedBanlist(effectiveDate: "2026-05-18",
                             statuses: [100: .limited, 200: .limited, 400: .forbidden]),
            format: .tcg, source: "yaml-yugi-limit-regulation",
            fetchedAt: Date(timeIntervalSince1970: 1_758_441_600))

        let disagreements = try history.disagreements(for: .tcg)

        #expect(disagreements.count == 3)
        #expect(!disagreements.contains { $0.konamiID == 100 })

        let disputed = try #require(disagreements.first { $0.konamiID == 200 })
        #expect(disputed.catalogStatus == .forbidden)
        #expect(disputed.historyStatus == .limited)
        #expect(disputed.name == "Disputed Card")
        #expect(disputed.historyEffectiveDate == "2026-05-18")
        #expect(disputed.historySource == "yaml-yugi-limit-regulation")

        // Named by one source and not the other: still a disagreement, because
        // absence from a list means unrestricted.
        let catalogOnly = try #require(disagreements.first { $0.konamiID == 300 })
        #expect(catalogOnly.catalogStatus == .semiLimited)
        #expect(catalogOnly.historyStatus == .unlimited)

        let historyOnly = try #require(disagreements.first { $0.konamiID == 400 })
        #expect(historyOnly.catalogStatus == .unlimited)
        #expect(historyOnly.historyStatus == .forbidden)

        // A card with no konami_id cannot be compared at all (`C2`).
        #expect(!disagreements.contains { $0.cardID == 5 })

        // Nothing was reconciled: both tables still say what they said.
        let catalogStillSays = try queue.read { db in
            try String.fetchOne(db, sql: """
                SELECT status FROM ban_status WHERE card_id = 2
                """)
        }
        #expect(catalogStillSays == "forbidden")
    }

    /// Evidence for NFR4, against the two real sources rather than a
    /// constructed pair: the catalog's current TCG list and the history's
    /// newest one, 222 cards described by both, recorded on 2026-09-21.
    ///
    /// Agreement is evidence, not a guarantee, which is why the disagreement
    /// path above exists and is proven separately.
    @Test func agreesWithTheCatalogOnTheCurrentTCGList() throws {
        let queue = try migratedQueue()
        let history = SQLiteBanlistHistory(database: queue)
        let catalogCards = try catalogCurrentTCG()

        #expect(catalogCards.count == 222)
        #expect(catalogCards.allSatisfy { $0.konami_id != nil })

        for (index, card) in catalogCards.enumerated() {
            let status: BanStatus = switch card.ban_tcg {
            case "Forbidden": .forbidden
            case "Limited": .limited
            case "Semi-Limited": .semiLimited
            default: .unlimited
            }
            try insertCard(queue, id: index + 1, konamiID: card.konami_id,
                           name: card.name, catalogStatus: status)
        }

        let current = try published(.tcg, "2026-05-18")
        #expect(current.count == 226)
        try history.store(current, format: .tcg,
                          source: "yaml-yugi-limit-regulation", fetchedAt: .now)

        let disagreements = try history.disagreements(for: .tcg)

        // Every card the catalog knows about is described identically by both.
        #expect(disagreements.isEmpty)

        // The four the history names and the catalog has not picked up are
        // stored and waiting, not silently dropped.
        let catalogKonamiIDs = Set(catalogCards.compactMap(\.konami_id))
        let extra = Set(current.statuses.keys).subtracting(catalogKonamiIDs)
        #expect(extra.count == 4)

        let storedEntries = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM banlist_entry")
        }
        #expect(storedEntries == 226)
    }
}
