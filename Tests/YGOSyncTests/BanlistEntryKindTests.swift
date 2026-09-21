import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOSync

@Suite("Banlist entry kind")
struct BanlistEntryKindTests {
    /// A catalog holding one card of each kind, plus a list naming them and
    /// one identifier the catalog does not hold.
    private func seeded() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)

        let cards: [(Int, String, String, Int)] = [
            (1, "Un Mostro Effetto", "effect", 4001),
            (2, "Una Magia", "spell", 4002),
            (3, "Una Trappola", "trap", 4003),
            (4, "Un Fusione", "fusion", 4004),
        ]
        try queue.write { db in
            for (id, name, frame, konami) in cards {
                try db.execute(sql: """
                    INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                      human_readable_type, konami_id)
                    VALUES (?, ?, 'text', ?, ?, ?, ?)
                    """, arguments: [id, name, frame, frame, frame, konami])
            }
        }

        let history = SQLiteBanlistHistory(database: queue)
        try history.store(
            PublishedBanlist(effectiveDate: "2005-03-01", statuses: [
                4001: .forbidden, 4002: .limited, 4003: .semiLimited,
                4004: .limited, 99_999: .forbidden,
            ]),
            format: .tcg, source: "yaml-yugi-limit-regulation",
            fetchedAt: Date(timeIntervalSince1970: 1_758_441_600))
        return queue
    }

    private func readSync<T>(_ queue: DatabaseQueue, _ body: (Database) throws -> T) throws -> T {
        try queue.read(body)
    }

    /// Evidence for R1.AC3: grouping by kind needs the kind, and the stored
    /// entry did not carry it. The query already joins `card` for the names,
    /// so this is one more column rather than a second read.
    @Test func aStoredEntryCarriesItsCardsKind() throws {
        let history = SQLiteBanlistHistory(database: try seeded())
        let entries = try history.list(.tcg, effectiveDate: "2005-03-01")

        let byKonami = Dictionary(uniqueKeysWithValues: entries.map { ($0.konamiID, $0) })
        #expect(byKonami[4001]?.frame == .effect)
        #expect(byKonami[4002]?.frame == .spell)
        #expect(byKonami[4003]?.frame == .trap)
        #expect(byKonami[4004]?.frame == .fusion)

        // And the kind groups the way the listing expects it to.
        #expect(byKonami[4001]?.frame?.cardType == .monster)
        #expect(byKonami[4004]?.frame?.cardType == .monster)
        #expect(byKonami[4002]?.frame?.cardType == .spell)
    }

    /// Evidence for R1.AC3: an entry the catalog cannot match has no name and
    /// no card, and now has no kind either — one condition, three nils.
    @Test func anUnmatchedEntryCarriesNoKindJustAsItCarriesNoName() throws {
        let history = SQLiteBanlistHistory(database: try seeded())
        let entries = try history.list(.tcg, effectiveDate: "2005-03-01")

        let unknown = try #require(entries.first { $0.konamiID == 99_999 })
        #expect(unknown.cardID == nil)
        #expect(unknown.name == nil)
        #expect(unknown.frame == nil)
        #expect(unknown.status == .forbidden)

        // Every matched entry has all three.
        let matched = entries.filter { $0.cardID != nil }
        #expect(matched.count == 4)
        #expect(matched.allSatisfy { $0.frame != nil && $0.name != nil })
    }

    /// Evidence for R1.AC3, against the real stored list rather than a
    /// constructed one: the kinds the GOAT list's cards carry are the kinds
    /// the catalog records for them.
    @Test func theGoatListsKindsMatchWhatTheCatalogSays() throws {
        let queue = try FilterFixture.database()
        let history = SQLiteBanlistHistory(database: queue)
        try history.store(
            PublishedBanlist(effectiveDate: "2005-03-01", statuses: [
                4007: .forbidden,   // Blue-Eyes White Dragon, a normal monster
                4012: .limited,     // Pot of Greed, a spell
                4014: .semiLimited, // Mirror Force, a trap
            ]),
            format: .tcg, source: "yaml-yugi-limit-regulation", fetchedAt: .now)

        let entries = try history.list(.tcg, effectiveDate: "2005-03-01")
        #expect(entries.count == 3)

        let stored = try readSync(queue) { db in
            try Row.fetchAll(db, sql: """
                SELECT konami_id, frame_type FROM card WHERE konami_id IN (4007, 4012, 4014)
                """).reduce(into: [Int: String]()) {
                    $0[$1["konami_id"] as Int] = $1["frame_type"] as String
                }
        }

        for entry in entries {
            #expect(entry.frame?.rawValue == stored[entry.konamiID],
                    "\(entry.konamiID) disagrees with the catalog")
        }
        #expect(entries.first { $0.konamiID == 4012 }?.frame == .spell)
        #expect(entries.first { $0.konamiID == 4014 }?.frame == .trap)
    }
}
