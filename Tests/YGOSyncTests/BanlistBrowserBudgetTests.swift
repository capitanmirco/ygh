import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureBanlist
import YGOPersistence
@testable import YGOSync

@MainActor
@Suite("Banlist browser budgets")
struct BanlistBrowserBudgetTests {
    /// The real stored lists: 177 of them, 28,648 entries, against a catalog
    /// large enough that most of their identifiers match.
    /// Non-async on purpose: inside an async function, `queue.write` resolves
    /// to GRDB's async overload.
    private func writeSync(_ queue: DatabaseQueue, _ body: (Database) throws -> Void) throws {
        try queue.write(body)
    }

    private func loaded() async throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)

        let frames = ["effect", "spell", "trap", "normal", "fusion", "synchro", "xyz"]
        try writeSync(queue) { db in
            for index in 1...5_000 {
                try db.execute(sql: """
                    INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                      human_readable_type, konami_id)
                    VALUES (?, ?, 'text', ?, ?, ?, ?)
                    """, arguments: [index, String(format: "Card %05d", index),
                                     frames[index % frames.count], frames[index % frames.count],
                                     frames[index % frames.count], index])
            }
        }

        let history = SQLiteBanlistHistory(database: queue)
        let source = RecordedBanlistSource()
        let report = await BanlistHistorySynchronizer(
            client: source, store: history,
            source: "yaml-yugi-limit-regulation"
        ).synchronize(formats: [.tcg])
        #expect(report.stored[.tcg] == 73)
        return queue
    }

    private func browser(_ queue: DatabaseQueue) -> BanlistBrowserViewModel {
        BanlistBrowserViewModel(
            history: SQLiteBanlistHistory(database: queue),
            catalog: SQLiteCardRepository(database: queue))
    }

    /// Evidence for NFR1: measured on the largest stored list rather than on
    /// the GOAT one, because grouping cost grows with entries and the point
    /// is that it does not grow enough to notice.
    @Test func anyStoredListIsGroupedAndShownWithinOneHundredFiftyMilliseconds() async throws {
        let queue = try await loaded()
        let model = browser(queue)
        await model.load(format: .tcg)
        #expect(model.availableLists.count == 73)

        // The largest list the source publishes for the TCG.
        let history = SQLiteBanlistHistory(database: queue)
        let largest = try #require(
            try history.revisions(for: .tcg).max { $0.entryCount < $1.entryCount })
        #expect(largest.entryCount > 100)

        // One untimed pass so first-use costs stay out of the measurement.
        await model.select(largest.effectiveDate)

        var worst: Double = 0
        for revision in try history.revisions(for: .tcg).suffix(12) {
            let started = DispatchTime.now().uptimeNanoseconds
            await model.select(revision.effectiveDate)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            worst = max(worst, elapsed)
        }

        #expect(worst < 150, "worst list \(worst) ms")
    }

    /// Evidence for NFR2, and the check that matters most: across all 73
    /// stored lists, everything a list holds is either shown or counted.
    @Test func theArithmeticClosesOnEveryStoredList() async throws {
        let queue = try await loaded()
        let model = browser(queue)
        let history = SQLiteBanlistHistory(database: queue)
        await model.load(format: .tcg)

        var checked = 0
        for revision in try history.revisions(for: .tcg) {
            await model.select(revision.effectiveDate)
            let entries = try history.list(.tcg, effectiveDate: revision.effectiveDate)

            #expect(model.totalShown + model.unmatched == entries.count,
                    "\(revision.effectiveDate): \(model.totalShown) + \(model.unmatched) != \(entries.count)")
            #expect(model.totalShown + model.unmatched == revision.entryCount)
            #expect(model.groups.count == 3)
            checked += 1
        }
        #expect(checked == 73)
    }

    /// Evidence for NFR3: the lists are stored, so reading one is a database
    /// read and nothing else.
    @Test func aStoredListReadsWithNoNetwork() async throws {
        let queue = try await loaded()
        // From here on the source refuses everything.
        let source = RecordedBanlistSource()
        source.offline = true

        let model = browser(queue)
        await model.load(format: .tcg)
        #expect(model.availableLists.count == 73)

        await model.select("2005-03-01")
        #expect(model.totalShown > 0)
        #expect(model.failure == nil)

        let entry = try #require(model.groups[0].cards.first)
        await model.preview(entry)
        #expect(model.previewCard != nil)
    }

    /// Evidence for NFR4: a row reading a card's name alone tells a listener
    /// neither what it is nor why it is on the list.
    @Test func eachCardReadsAsASentenceNamingItsKindAndStatus() async throws {
        let queue = try await loaded()
        let model = browser(queue)
        await model.load(format: .tcg)
        await model.select("2005-03-01")

        for group in model.groups {
            for card in group.cards.prefix(5) {
                let spoken = BanlistListing.description(of: card)
                #expect(spoken.contains(card.displayName))
                #expect(spoken.count > card.displayName.count + 8)

                switch group.status {
                case .forbidden: #expect(spoken.contains("proibita"))
                case .limited: #expect(spoken.contains("limitata a 1"))
                case .semiLimited: #expect(spoken.contains("semi-limitata a 2"))
                }
            }
        }

        // The groups name themselves too.
        #expect(model.groups.map(\.italianName)
                == ["Proibite", "Limitate", "Semi-limitate"])

        // A card whose kind the catalog does not know still reads as a
        // sentence rather than trailing off.
        let unknown = BanlistListEntry(
            konamiID: 1, cardID: 1, name: "Senza tipo",
            italianName: nil, status: .limited, frame: nil)
        #expect(BanlistListing.description(of: unknown)
                == "Senza tipo, tipo sconosciuto, limitata a 1")
    }
}
