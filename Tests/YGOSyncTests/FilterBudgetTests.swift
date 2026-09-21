import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureBrowser
import YGOPersistence
@testable import YGOSync

@MainActor
@Suite("Filter budgets")
struct FilterBudgetTests {
    /// A catalog the size of the real one, with the lists stored. A filter
    /// that is instant on twelve cards is not evidence.
    private static let catalogSize = 14_566

    private func loaded() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)

        let attributes = ["LIGHT", "DARK", "EARTH", "WATER", "FIRE", "WIND", "DIVINE"]
        let frames = ["normal", "effect", "spell", "trap", "fusion", "synchro", "xyz"]
        try queue.write { db in
            for index in 1...Self.catalogSize {
                let frame = frames[index % frames.count]
                let isMonster = frame != "spell" && frame != "trap"
                try db.execute(sql: """
                    INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                      human_readable_type, attribute, level, race,
                                      archetype, atk, def, tcg_date, konami_id)
                    VALUES (?, ?, 'effect text', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        index, String(format: "Card %05d", index), frame, frame, frame,
                        isMonster ? attributes[index % attributes.count] : nil,
                        isMonster ? (index % 12) + 1 : nil,
                        isMonster ? "Type \(index % 87)" : nil,
                        index % 22 == 0 ? "Archetype \(index % 662)" : nil,
                        isMonster ? (index % 5 == 0 ? -1 : (index % 5000)) : nil,
                        isMonster ? (index % 4000) : nil,
                        index % 28 == 0 ? nil : "20\(String(format: "%02d", index % 25))-06-01",
                        index])
                try db.execute(sql: """
                    INSERT INTO card_format (card_id, format_code) VALUES (?, 'TCG')
                    """, arguments: [index])
            }
        }

        // One stored list, the size of a real one.
        let history = SQLiteBanlistHistory(database: queue)
        var statuses: [Int: BanlistStatus] = [:]
        for index in stride(from: 1, through: 220, by: 1) {
            statuses[index] = [.forbidden, .limited, .semiLimited][index % 3]
        }
        try history.store(
            PublishedBanlist(effectiveDate: "2005-03-01", statuses: statuses),
            format: .tcg, source: "yaml-yugi-limit-regulation", fetchedAt: .now)
        return queue
    }

    private func browser(_ queue: DatabaseQueue) -> BrowserViewModel {
        let repository = SQLiteCardRepository(database: queue)
        return BrowserViewModel(
            repository: repository, counter: repository,
            artwork: NoArtwork(), banStatusProvider: repository,
            publishedLists: SQLiteBanlistHistory(database: queue), language: .english)
    }

    /// Evidence for NFR1: a filter that takes a second stops being a filter
    /// and becomes a search. Measured on a full-sized catalog.
    @Test func applyingAFilterUpdatesResultsWithinOneHundredFiftyMilliseconds() async throws {
        let model = browser(try loaded())
        await model.start()
        #expect(model.matchCount == Self.catalogSize)

        var worst: Double = 0
        var filters = CardFilters()

        // Each of these is a different shape of clause: a set, a range, a
        // join, and the list join with its status projection.
        let steps: [(String, CardFilters)] = {
            var byType = CardFilters(); byType.cardTypes = [.monster]
            var byLevel = byType; byLevel.levels = 4...4
            var byYear = byLevel; byYear.releaseYears = 2005...2015
            var byFormat = byYear; byFormat.format = .tcg
            var byList = CardFilters()
            byList.publishedList = PublishedListSelection(
                format: .tcg, effectiveDate: "2005-03-01")
            return [("type", byType), ("level", byLevel), ("year", byYear),
                    ("format", byFormat), ("list", byList)]
        }()

        for (label, next) in steps {
            filters = next
            model.filters = filters
            let started = DispatchTime.now().uptimeNanoseconds
            await model.filtersChanged()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            worst = max(worst, elapsed)
            #expect(model.matchCount > 0, "\(label) matched nothing")
        }

        #expect(worst < 150, "worst filter \(worst) ms")
    }

    /// Evidence for NFR2: every card a filter hides is counted, because a
    /// smaller grid with no explanation reads as a smaller catalog.
    @Test func everyHiddenCardIsCountedAndExplained() async throws {
        let model = browser(try loaded())
        await model.start()

        var filters = CardFilters()
        filters.releaseYears = 2000...2030
        model.filters = filters
        await model.filtersChanged()

        // The undated cards are hidden by the range, and counted.
        #expect(model.excludedUndated > 0)
        #expect(model.excludedUndated == Self.catalogSize / 28)

        // A list naming cards the catalog lacks reports the difference.
        filters = CardFilters()
        filters.publishedList = PublishedListSelection(
            format: .tcg, effectiveDate: "2005-03-01")
        model.filters = filters
        await model.filtersChanged()
        #expect(model.matchCount == 220)
        #expect(model.unmatchedOnList == 0)

        // And every applied filter is named, which is what an empty grid needs.
        #expect(!model.appliedFilters.isEmpty)
    }

    /// Evidence for NFR3: once the lists are stored, nothing goes out again —
    /// including the one filter that came from a second upstream.
    @Test func everyFilterResolvesOfflineOnceTheListsAreStored() async throws {
        let queue = try loaded()
        let model = browser(queue)
        await model.start()

        // Nothing in this graph can reach a network: the repository is SQLite
        // and the artwork provider returns nothing.
        var filters = CardFilters()
        filters.cardTypes = [.monster]
        filters.attributes = [.dark]
        filters.levels = 1...12
        filters.attack = 0...5000
        filters.releaseYears = 2000...2030
        filters.format = .tcg
        model.filters = filters
        await model.filtersChanged()
        #expect(model.matchCount > 0)

        filters = CardFilters()
        filters.publishedList = PublishedListSelection(
            format: .tcg, effectiveDate: "2005-03-01")
        model.filters = filters
        await model.filtersChanged()
        #expect(model.matchCount == 220)
        #expect(model.availableLists(for: .tcg).count == 1)

        // The historical statuses came from storage too.
        #expect(model.items.contains { $0.banStatus == .forbidden })
    }

    /// Evidence for NFR4: a filter that shows as a checkbox and reads as
    /// nothing is unusable without a pointer and a memory.
    @Test func everyFilterReadsAsASentenceNamingWhatItNarrows() async throws {
        var filters = CardFilters()
        filters.cardTypes = [.monster, .spell]
        filters.attributes = [.dark]
        filters.levels = 4...4
        filters.races = ["Dragon"]
        filters.archetypes = ["Blue-Eyes"]
        filters.attack = 2000...3000
        filters.unknownStatsOnly = true
        filters.releaseYears = 2004...2005
        filters.format = .goat
        filters.publishedList = PublishedListSelection(
            format: .tcg, effectiveDate: "2005-03-01")
        filters.ownedOnly = true

        let sentences = filters.descriptions
        #expect(sentences.count == 11)
        #expect(sentences.allSatisfy { $0.count > 4 })
        #expect(sentences.allSatisfy { !$0.hasPrefix("true") && $0 != "1" })

        // Each names what it narrows rather than merely its value.
        #expect(sentences.contains { $0.hasPrefix("tipo:") })
        #expect(sentences.contains { $0.hasPrefix("attributo:") })
        #expect(sentences.contains("livello 4"))
        #expect(sentences.contains { $0.contains("uscita fra 2004 e 2005") })
        #expect(sentences.contains { $0.contains("lista TCG del 2005-03-01") })
        #expect(sentences.contains("solo carte possedute"))

        // And nothing is listed when nothing is applied.
        #expect(CardFilters().descriptions.isEmpty)
    }
}
