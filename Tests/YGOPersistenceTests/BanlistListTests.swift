import Foundation
import GRDB
import Testing
import YGOCore
@testable import YGOPersistence

@Suite("Banlist lists")
struct BanlistListTests {
    private static let fixtures: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "fixtures")
        .appending(path: "banlist")

    private func published(_ format: BanlistFormat, _ date: String) throws -> PublishedBanlist {
        try JSONDecoder().decode(PublishedBanlist.self, from: Data(contentsOf: Self.fixtures
            .appending(path: format.rawValue)
            .appending(path: "\(date).vector.json")))
    }

    private func publishedDates(_ format: BanlistFormat) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: Self.fixtures.appending(path: format.rawValue),
            includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(".vector.json") }
            .map { String($0.dropLast(".vector.json".count)) }
            .sorted()
    }

    private func store(_ dates: [String], _ format: BanlistFormat = .tcg)
        throws -> (DatabaseQueue, SQLiteBanlistHistory)
    {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)
        let history = SQLiteBanlistHistory(database: queue)
        for date in dates {
            try history.store(published(format, date), format: format,
                              source: "yaml-yugi-limit-regulation",
                              fetchedAt: Date(timeIntervalSince1970: 1_758_441_600))
        }
        return (queue, history)
    }

    private func insertCard(
        _ queue: DatabaseQueue, id: Int, konamiID: Int,
        name: String, italianName: String? = nil
    ) throws {
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO card (id, name_en, name_it, desc_en, type, frame_type,
                                  human_readable_type, konami_id)
                VALUES (?, ?, ?, '', 'Spell Card', 'spell', 'Spell Card', ?)
                """, arguments: [id, name, italianName, konamiID])
        }
    }

    /// Evidence for R3.AC1: the March 2005 TCG list reported as it stood, each
    /// card with a status and a name. An identifier the catalog cannot name is
    /// still reported, because dropping it would make the list wrong.
    @Test func reportsTheMarch2005ListWithNamesAndStatuses() throws {
        let (queue, history) = try store(["2005-03-01"])
        let source = try published(.tcg, "2005-03-01")

        // Name two of the seventy-seven; the rest stay unnamed.
        let forbidden = source.konamiIDs(at: .forbidden).sorted()
        try insertCard(queue, id: 1, konamiID: forbidden[0], name: "Change of Heart",
                       italianName: "Cambio di Cuore")
        try insertCard(queue, id: 2, konamiID: forbidden[1], name: "Delinquent Duo")

        let entries = try history.list(.tcg, effectiveDate: "2005-03-01")

        #expect(entries.count == 77)
        #expect(entries.filter { $0.status == .forbidden }.count == 18)
        #expect(entries.filter { $0.status == .limited }.count == 44)
        #expect(entries.filter { $0.status == .semiLimited }.count == 15)

        let named = entries.filter { $0.name != nil }
        #expect(named.count == 2)
        #expect(named.contains { $0.italianName == "Cambio di Cuore" })
        #expect(named.first { $0.konamiID == forbidden[1] }?.displayName == "Delinquent Duo")

        // The 75 the catalog cannot name are reported anyway, by identifier.
        let unnamed = entries.filter { $0.name == nil }
        #expect(unnamed.count == 75)
        #expect(unnamed.allSatisfy { $0.cardID == nil })
        #expect(unnamed.first?.displayName.hasPrefix("konami_id ") == true)

        // Every identifier on the list, exactly once.
        #expect(Set(entries.map(\.konamiID)) == Set(source.statuses.keys))
    }

    /// Evidence for R3.AC2: the lists held for a format are reported oldest
    /// first, and they are the ones the source published, with no gaps.
    @Test func reportsTCGListsInDateOrderWithNoGaps() throws {
        let dates = try publishedDates(.tcg)
        let (_, history) = try store(dates)

        let revisions = try history.revisions(for: .tcg)

        #expect(revisions.count == 73)
        #expect(revisions.map(\.effectiveDate) == dates)
        #expect(revisions.map(\.effectiveDate) == revisions.map(\.effectiveDate).sorted())
        #expect(revisions.first?.effectiveDate == "1999-08-01")
        #expect(revisions.last?.effectiveDate == "2026-05-18")
        #expect(revisions.allSatisfy { $0.format == .tcg })
        #expect(revisions.allSatisfy { $0.entryCount > 0 })

        // Each revision reports the size of the list it holds.
        let march2005 = revisions.first { $0.effectiveDate == "2005-03-01" }
        #expect(march2005?.entryCount == 77)

        // Another format's lists do not leak into this one.
        #expect(try history.revisions(for: .ocg).isEmpty)
    }

    /// Evidence for R3.AC3, checked against the published bodies rather than
    /// against the same query that produced the answer: two consecutive TCG
    /// lists, differenced twice by different means.
    @Test func reportsTheCardsWhoseStatusDiffersBetweenConsecutiveLists() throws {
        let (_, history) = try store(["2005-03-01", "2005-09-01"])
        let before = try published(.tcg, "2005-03-01")
        let after = try published(.tcg, "2005-09-01")

        let reported = try history.difference(
            .tcg, from: "2005-03-01", to: "2005-09-01")

        // Recomputed straight from the two bodies.
        var expected: [Int: (BanStatus, BanStatus)] = [:]
        for konamiID in Set(before.statuses.keys).union(after.statuses.keys) {
            let from = before.statuses[konamiID]?.banStatus ?? .unlimited
            let to = after.statuses[konamiID]?.banStatus ?? .unlimited
            if from != to { expected[konamiID] = (from, to) }
        }

        #expect(!expected.isEmpty)
        #expect(reported.count == expected.count)
        #expect(Set(reported.map(\.konamiID)) == Set(expected.keys))
        for difference in reported {
            #expect(difference.before == expected[difference.konamiID]?.0)
            #expect(difference.after == expected[difference.konamiID]?.1)
            #expect(difference.before != difference.after)
        }

        // A card whose status held steady is not a change.
        let unchanged = Set(before.statuses.keys)
            .intersection(after.statuses.keys)
            .filter { before.statuses[$0] == after.statuses[$0] }
        #expect(!unchanged.isEmpty)
        #expect(Set(reported.map(\.konamiID)).isDisjoint(with: unchanged))
    }

    /// Evidence for R3.AC3: a card dropped from a list leaves no row, and that
    /// silence is a change — it went free. A difference built only from rows
    /// present on both lists would miss every unbanning ever published.
    @Test func countsADroppedCardAsChanged() throws {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)
        let history = SQLiteBanlistHistory(database: queue)
        try insertCard(queue, id: 1, konamiID: 100, name: "Dropped Card")
        try insertCard(queue, id: 2, konamiID: 200, name: "Added Card")
        try insertCard(queue, id: 3, konamiID: 300, name: "Steady Card")

        let earlier = PublishedBanlist(
            effectiveDate: "2026-01-01",
            statuses: [100: .forbidden, 300: .limited])
        let later = PublishedBanlist(
            effectiveDate: "2026-06-01",
            statuses: [200: .semiLimited, 300: .limited])
        for list in [earlier, later] {
            try history.store(list, format: .tcg, source: "test", fetchedAt: .now)
        }

        let differences = try history.difference(
            .tcg, from: "2026-01-01", to: "2026-06-01")

        #expect(differences.count == 2)

        let dropped = differences.first { $0.konamiID == 100 }
        #expect(dropped?.before == .forbidden)
        #expect(dropped?.after == .unlimited)
        #expect(dropped?.name == "Dropped Card")

        let added = differences.first { $0.konamiID == 200 }
        #expect(added?.before == .unlimited)
        #expect(added?.after == .semiLimited)

        #expect(!differences.contains { $0.konamiID == 300 })
        // Sorted by name, so the reader sees a list rather than identifiers.
        #expect(differences.map(\.name) == ["Added Card", "Dropped Card"])
    }
}
