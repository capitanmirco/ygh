import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureBanlist
import YGOPersistence
@testable import YGOSync

@MainActor
@Suite("Banlist browser")
struct BanlistBrowserTests {
    /// The catalog's fixture, plus three stored TCG lists including the one
    /// that defines GOAT.
    private func seeded() throws -> DatabaseQueue {
        let queue = try FilterFixture.database()
        let history = SQLiteBanlistHistory(database: queue)

        try history.store(
            PublishedBanlist(effectiveDate: "2005-03-01", statuses: [
                4007: .forbidden, 4012: .limited, 4014: .semiLimited, 99_999: .forbidden,
            ]),
            format: .tcg, source: "yaml-yugi-limit-regulation", fetchedAt: .now)
        try history.store(
            PublishedBanlist(effectiveDate: "2010-03-01", statuses: [4008: .limited]),
            format: .tcg, source: "yaml-yugi-limit-regulation", fetchedAt: .now)
        try history.store(
            PublishedBanlist(effectiveDate: "2026-05-18", statuses: [4009: .forbidden]),
            format: .tcg, source: "yaml-yugi-limit-regulation", fetchedAt: .now)
        return queue
    }

    private func browser(_ queue: DatabaseQueue) -> BanlistBrowserViewModel {
        BanlistBrowserViewModel(
            history: SQLiteBanlistHistory(database: queue),
            catalog: SQLiteCardRepository(database: queue))
    }

    /// Evidence for R2.AC1: newest first, unlike the catalog's chooser. That
    /// one is a history to look back through; this screen opens on the rules
    /// as they stand.
    @Test func theTcgListsAreOfferedNewestFirst() async throws {
        let model = browser(try seeded())
        await model.load(format: .tcg)

        #expect(model.availableLists.map(\.effectiveDate)
                == ["2026-05-18", "2010-03-01", "2005-03-01"])
        #expect(!model.hasNoStoredLists)
        // It opens on the newest without being asked.
        #expect(model.selectedDate == "2026-05-18")
    }

    /// Evidence for R2.AC2: choosing a date replaces what is on screen.
    @Test func choosingAnotherDateReplacesTheGroups() async throws {
        let model = browser(try seeded())
        await model.load(format: .tcg)
        #expect(model.totalShown == 1)

        await model.select("2005-03-01")

        #expect(model.selectedDate == "2005-03-01")
        #expect(model.groups.map(\.count) == [1, 1, 1])
        #expect(model.totalShown == 3)
        #expect(model.unmatched == 1)

        // And back again.
        await model.select("2010-03-01")
        #expect(model.totalShown == 1)
        #expect(model.unmatched == 0)
    }

    /// Evidence for R2.AC3: the source dates the GOAT list 2005-03-01 and
    /// players call it April 2005. Naming it is what closes that gap.
    @Test func theGoatDefiningListIsLabelledAsSuch() async throws {
        let model = browser(try seeded())
        await model.load(format: .tcg)

        #expect(model.label(for: "2005-03-01") == "2005-03-01 — lista GOAT")
        #expect(model.label(for: "2010-03-01") == "2010-03-01 — lista Edison")
        // An ordinary list is just its date.
        #expect(model.label(for: "2026-05-18") == "2026-05-18")
    }

    /// Evidence for R2.AC4: three empty groups look like a bug. Saying that
    /// nothing has been downloaded does not.
    @Test func withNothingStoredTheScreenSaysSo() async throws {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)
        let model = browser(queue)

        await model.load(format: .tcg)

        #expect(model.hasNoStoredLists)
        #expect(model.availableLists.isEmpty)
        #expect(model.selectedDate == nil)
        #expect(model.totalShown == 0)
        // The three groups still exist, so the screen has one shape.
        #expect(model.groups.count == 3)
        #expect(model.failure == nil, "nothing stored is not a failure")
    }

    /// Evidence for R2.AC5: a list without its format and date is an
    /// assertion about nothing in particular.
    @Test func theScreenNamesTheFormatAndDateItIsShowing() async throws {
        let model = browser(try seeded())
        await model.load(format: .tcg)
        #expect(model.heading == "TCG · 2026-05-18")

        await model.select("2005-03-01")
        #expect(model.heading == "TCG · 2005-03-01")
        #expect(model.format == .tcg)

        // With nothing chosen it says that rather than naming a phantom.
        let empty = BanlistBrowserViewModel(
            history: SQLiteBanlistHistory(database: try DatabaseQueue()))
        #expect(empty.heading == "Nessuna lista scelta")
    }

    /// Evidence for R3.AC1: a name you do not recognise should not send you
    /// to another screen.
    @Test func selectingACardShowsItsDetailBesideTheList() async throws {
        let model = browser(try seeded())
        await model.load(format: .tcg)
        await model.select("2005-03-01")

        let entry = try #require(model.groups[0].cards.first)
        await model.preview(entry)

        let card = try #require(model.previewCard)
        #expect(card.id.rawValue == entry.cardID)
        #expect(!card.englishEffect.isEmpty)
        #expect(model.previewFailure == nil)
    }

    /// Evidence for R3.AC2: the same card, described the same way, wherever
    /// it is opened from.
    @Test func theDetailIsTheOneTheCatalogGives() async throws {
        let queue = try seeded()
        let model = browser(queue)
        await model.load(format: .tcg)
        await model.select("2005-03-01")

        let entry = try #require(model.groups[1].cards.first)
        await model.preview(entry)
        let fromList = try #require(model.previewCard)

        // `#require` cannot nest, so the identifier is unwrapped first.
        let cardID = try #require(entry.cardID)
        let fromCatalog = try #require(
            try await SQLiteCardRepository(database: queue)
                .card(with: CardIdentifier(cardID)))
        #expect(fromList == fromCatalog)
    }

    /// Evidence for R3.AC3: an entry the catalog cannot match has nothing to
    /// open, and saying so is different from opening nothing.
    @Test func anUnopenableCardIsStatedRatherThanBlank() async throws {
        let model = browser(try seeded())
        await model.load(format: .tcg)
        await model.select("2005-03-01")

        let unmatched = BanlistListEntry(
            konamiID: 99_999, cardID: nil, name: nil,
            italianName: nil, status: .forbidden, frame: nil)
        await model.preview(unmatched)

        #expect(model.previewCard == nil)
        let failure = try #require(model.previewFailure)
        #expect(failure.contains("non corrisponde"))

        // A screen built without a catalog says something different and
        // equally specific.
        let bare = BanlistBrowserViewModel(
            history: SQLiteBanlistHistory(database: try seeded()))
        await bare.load(format: .tcg)
        await bare.select("2005-03-01")
        let first = try #require(bare.groups[0].cards.first)
        await bare.preview(first)
        #expect(bare.previewFailure?.contains("non può aprire") == true)
    }
}
