import Foundation
import GRDB
import Testing
import YGOCore
@testable import YGOPersistence

@Suite("Card printing reads")
struct CardPrintingReadTests {
    /// Three cards standing for three real populations: one printed many times
    /// over, one among the 552 the catalog holds no printing for, and one among
    /// the 85 carrying neither release date.
    private func seeded() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)

        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                  human_readable_type, tcg_date, ocg_date, konami_id)
                VALUES (89631139, 'Blue-Eyes White Dragon', 'legendary',
                        'Normal Monster', 'normal', 'Normal Monster',
                        '2002-03-08', '1999-01-21', 4007)
                """)
            try db.execute(sql: """
                INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                  human_readable_type, tcg_date, ocg_date)
                VALUES (2, 'Unprinted Card', 'text', 'Spell Card', 'spell',
                        'Spell Card', '2015-06-01', NULL)
                """)
            try db.execute(sql: """
                INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                  human_readable_type, tcg_date, ocg_date)
                VALUES (3, 'Undated Card', 'text', 'Spell Card', 'spell',
                        'Spell Card', NULL, NULL)
                """)

            // 78 printings, as the live catalog holds for Blue-Eyes.
            for index in 1...78 {
                try db.execute(sql: """
                    INSERT INTO card_print
                        (card_id, set_code, set_name, rarity, rarity_code, set_price)
                    VALUES (89631139, ?, ?, ?, ?, ?)
                    """, arguments: [
                        String(format: "SET-%03d", index),
                        String(format: "Set %03d", index),
                        index % 3 == 0 ? "Ultra Rare" : "Common",
                        "(UR)",
                        index % 5 == 0 ? nil : Double(index) / 100.0,
                    ])
            }
        }
        return queue
    }

    /// Evidence for R3.AC1: every printing, each carrying all three things a
    /// collector needs to identify it.
    @Test func readsSeventyEightPrintingsWithSetCodeAndRarity() async throws {
        let reader = SQLiteCardDetailReader(database: try seeded())

        let printings = try await reader.printings(forCard: CardIdentifier(89_631_139))

        #expect(printings.count == 78)
        #expect(printings.allSatisfy { !$0.setName.isEmpty })
        #expect(printings.allSatisfy { !$0.setCode.isEmpty })
        #expect(printings.allSatisfy { !$0.rarity.isEmpty })

        // Ordered so the panel reads as a list rather than as a dump.
        #expect(printings.map(\.setName) == printings.map(\.setName).sorted())
        #expect(Set(printings.map(\.setCode)).count == 78)
        #expect(Set(printings.map(\.rarity)) == ["Common", "Ultra Rare"])

        // A printing the upstream listed no price for is unpriced, not free.
        let unpriced = printings.filter { $0.listedPrice == nil }
        #expect(unpriced.count == 15)
        #expect(printings.compactMap(\.listedPrice).allSatisfy { $0 > 0 })
    }

    /// Evidence for R3.AC2: 552 cards have no printing at all, thirty of them
    /// legal in the TCG. An empty list is the answer, and the panel has to be
    /// able to tell it apart from a list it failed to read.
    @Test func aCardWithNoPrintingReportsNoneRecorded() async throws {
        let reader = SQLiteCardDetailReader(database: try seeded())

        let printings = try await reader.printings(forCard: CardIdentifier(2))
        #expect(printings.isEmpty)

        // A card the catalog does not hold at all reads the same way here; the
        // panel never asks for one, because it opens from a card it has.
        #expect(try await reader.printings(forCard: CardIdentifier(999)).isEmpty)
    }

    /// Evidence for R2.AC4: a date means little without its region. The same
    /// card reached the OCG three years before the TCG.
    @Test func reportsBothReleaseDatesEachNamedByItsRegion() async throws {
        let reader = SQLiteCardDetailReader(database: try seeded())

        let release = try await reader.release(forCard: CardIdentifier(89_631_139))
        guard case let .known(tcg, ocg) = release else {
            Issue.record("expected known dates, got \(release)")
            return
        }
        #expect(tcg == "2002-03-08")
        #expect(ocg == "1999-01-21")
        #expect(release.isKnown)

        // The history needs the date that applies in the format it is drawing.
        #expect(release.date(for: .tcg) == "2002-03-08")
        #expect(release.date(for: .ocg) == "1999-01-21")

        // One region only is still an answer, and it says which region.
        let single = try await reader.release(forCard: CardIdentifier(2))
        guard case let .known(tcgOnly, ocgOnly) = single else {
            Issue.record("expected a known date, got \(single)")
            return
        }
        #expect(tcgOnly == "2015-06-01")
        #expect(ocgOnly == nil)
        // A format with no date of its own falls back to the one that exists
        // rather than claiming the card predates every list.
        #expect(single.date(for: .ocg) == "2015-06-01")
    }

    /// Evidence for R2.AC5: 85 cards carry neither date. "Unknown" and "not
    /// yet printed" are different claims, and only one of them is true here.
    @Test func aCardWithNeitherDateReportsAnUnknownRelease() async throws {
        let reader = SQLiteCardDetailReader(database: try seeded())

        let release = try await reader.release(forCard: CardIdentifier(3))
        #expect(release == .unknown)
        #expect(!release.isKnown)
        #expect(release.date(for: .tcg) == nil)

        // The constructor refuses to dress two absent dates as a known pair.
        #expect(CardRelease(tcg: nil, ocg: nil) == .unknown)
        #expect(CardRelease(tcg: nil, ocg: "2000-01-01") != .unknown)

        // A card the catalog does not hold is unknown too, not a crash.
        #expect(try await reader.release(forCard: CardIdentifier(999)) == .unknown)
        #expect(try await reader.konamiID(forCard: CardIdentifier(3)) == nil)
        #expect(try await reader.konamiID(forCard: CardIdentifier(89_631_139)) == 4007)
    }
}
