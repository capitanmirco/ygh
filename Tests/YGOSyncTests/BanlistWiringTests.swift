import Foundation
import GRDB
import Testing
import YGOComposition
import YGOCore
import YGOFeatureBrowser
import YGOPersistence
@testable import YGOSync

@MainActor
@Suite("Banlist wiring")
struct BanlistWiringTests {
    private func coordinator(
        _ queue: DatabaseQueue, source: RecordedBanlistSource = RecordedBanlistSource()
    ) -> BanlistSyncCoordinator {
        BanlistSyncCoordinator(
            store: SQLiteBanlistHistory(database: queue), client: source)
    }

    private func migrated() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)
        return queue
    }

    /// Evidence for R3.AC4: this is the state the user's own database is in.
    /// Zero revisions, and every card's history panel saying so. An empty
    /// chooser would look like a broken one.
    @Test func beforeAnySynchronisationTheChooserSaysSoRatherThanBeingEmpty() async throws {
        let queue = try migrated()
        let sync = coordinator(queue)

        #expect(!sync.hasAnyList)
        #expect(sync.storedListCount == 0)
        #expect(sync.state == .idle)
        #expect(sync.summary == "Nessuna lista scaricata.")

        // And the browser's chooser is empty rather than offering a phantom.
        let repository = SQLiteCardRepository(database: queue)
        let model = BrowserViewModel(
            repository: repository, counter: repository,
            artwork: NoArtwork(), banStatusProvider: repository,
            publishedLists: SQLiteBanlistHistory(database: queue))
        #expect(model.availableLists(for: .tcg).isEmpty)
    }

    /// Evidence for R4.AC1: the synchroniser existed and nothing called it.
    /// This is the caller, driven by the recorded lists rather than a host.
    @Test func aSynchronisationStoresWhatTheSourcePublished() async throws {
        let queue = try migrated()
        let sync = coordinator(queue)

        await sync.synchronize()

        #expect(sync.hasAnyList)
        #expect(sync.storedListCount == 177)
        if case let .finished(stored, _, _) = sync.state {
            #expect(stored == 177)
        } else {
            Issue.record("expected finished, got \(sync.state)")
        }

        // The history the card panel reads is no longer empty.
        let history = SQLiteBanlistHistory(database: queue)
        #expect(try history.revisions(for: .tcg).count == 73)
        #expect(try history.list(.tcg, effectiveDate: "2005-03-01").count == 77)
    }

    /// Evidence for R4.AC2: 177 files is fast, and saying so is still better
    /// than a frozen window. Search keeps answering throughout.
    @Test func progressIsReportedAndSearchKeepsAnswering() async throws {
        let queue = try FilterFixture.database()
        let sync = coordinator(queue)
        #expect(sync.summary.contains("Nessuna lista"))

        let repository = SQLiteCardRepository(database: queue)
        let model = BrowserViewModel(
            repository: repository, counter: repository,
            artwork: NoArtwork(), banStatusProvider: repository)
        await model.start()
        let before = model.matchCount

        await sync.synchronize()

        // The summary now names what was stored rather than staying silent.
        #expect(sync.summary.contains("177"))
        #expect(!sync.isRunning)

        // A second run finds nothing new and says that instead.
        await sync.synchronize()
        #expect(sync.summary.contains("Già aggiornato"))

        // The catalog answered the whole time and is unchanged.
        await model.start()
        #expect(model.matchCount == before)
    }

    /// Evidence for R4.AC3: the lists already stored are worth more than the
    /// ones that failed to arrive.
    @Test func aFailedSynchronisationKeepsWhatWasStoredAndSaysSo() async throws {
        let queue = try migrated()
        let source = RecordedBanlistSource()
        let sync = coordinator(queue, source: source)

        await sync.synchronize()
        let stored = sync.storedListCount
        #expect(stored == 177)

        source.offline = true
        await sync.synchronize()

        if case let .failed(reason) = sync.state {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("expected failed, got \(sync.state)")
        }
        #expect(sync.summary.contains("non riuscito"))
        #expect(sync.storedListCount == stored)
    }

    /// Evidence for R4.AC4: once downloaded, the lists are local. Nothing in
    /// the chooser or the filter goes out again.
    @Test func afterwardsEveryListQuestionAnswersOffline() async throws {
        let queue = try FilterFixture.database()
        let source = RecordedBanlistSource()
        let sync = coordinator(queue, source: source)
        await sync.synchronize()

        // From here on the source refuses everything.
        source.offline = true

        let history = SQLiteBanlistHistory(database: queue)
        let repository = SQLiteCardRepository(database: queue)
        let model = BrowserViewModel(
            repository: repository, counter: repository,
            artwork: NoArtwork(), banStatusProvider: repository,
            publishedLists: history, language: .english)
        await model.start()

        // The chooser still offers every stored list.
        #expect(model.availableLists(for: .tcg).count == 73)

        // And the filter still narrows by one of them.
        var filters = CardFilters()
        filters.publishedList = PublishedListSelection(
            format: .tcg, effectiveDate: "2005-03-01")
        model.filters = filters
        await model.filtersChanged()
        #expect(model.unmatchedOnList > 0)   // the fixture holds few of its cards
        #expect(sync.hasAnyList)
    }
}
