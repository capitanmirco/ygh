import Foundation
import Testing
import YGOCore
@testable import YGOBanlistHistory

/// The real TCG dates these tests use, so a timeline is checked against the
/// shape the source actually publishes rather than an invented one.
enum TCGDates {
    static let all = [
        "1999-08-01", "2004-03-01", "2005-03-01", "2005-09-01", "2006-03-01",
        "2010-03-01", "2015-01-01", "2015-04-01", "2020-01-01", "2026-05-18",
    ]
}

@Suite("Banlist timeline")
struct BanlistTimelineTests {
    /// Evidence for R2.AC1: a card restricted since 2005 reports one entry per
    /// list from that date onwards, oldest first.
    @Test func reportsOneEntryPerListOldestFirst() {
        let timeline = BanlistTimelineBuilder.timeline(
            format: .tcg,
            // Deliberately unsorted: the builder orders, the caller need not.
            revisionDates: TCGDates.all.shuffled(),
            statuses: [
                "2005-03-01": .forbidden, "2005-09-01": .forbidden,
                "2006-03-01": .limited, "2010-03-01": .limited,
                "2015-01-01": .semiLimited,
            ],
            releaseDate: "2004-01-01")

        #expect(timeline.format == .tcg)
        #expect(timeline.entries.count == 9)   // every list from 2004-03-01 on
        #expect(timeline.entries.map(\.effectiveDate)
                == timeline.entries.map(\.effectiveDate).sorted())
        #expect(timeline.entries.first?.effectiveDate == "2004-03-01")
        #expect(timeline.entries.last?.effectiveDate == "2026-05-18")

        let byDate = Dictionary(uniqueKeysWithValues:
            timeline.entries.map { ($0.effectiveDate, $0.status) })
        #expect(byDate["2005-03-01"] == .forbidden)
        #expect(byDate["2006-03-01"] == .limited)
        #expect(byDate["2015-01-01"] == .semiLimited)
        #expect(timeline.currentStatus == .unlimited)
    }

    /// Evidence for R2.AC2: the source names only restricted cards, so a card
    /// a list does not name was unrestricted on it. It stays in the history
    /// rather than disappearing from it, which is what makes the shape of the
    /// history readable.
    @Test func aCardAbsentFromAListIsUnrestrictedOnIt() {
        let timeline = BanlistTimelineBuilder.timeline(
            format: .tcg,
            revisionDates: TCGDates.all,
            statuses: ["2005-03-01": .forbidden],
            releaseDate: "1999-01-01")

        #expect(timeline.entries.count == TCGDates.all.count)

        let unnamed = timeline.entries.filter { $0.effectiveDate != "2005-03-01" }
        #expect(unnamed.count == 9)
        #expect(unnamed.allSatisfy { $0.status == .unlimited })
        #expect(!timeline.wasNeverRestricted)
    }

    /// Evidence for R2.AC3: absence means two different things, and the release
    /// date separates them. A card printed in 2015 was not unrestricted on the
    /// 2005 list; it did not exist.
    @Test func reportsNothingForListsPublishedBeforeTheCardExisted() {
        let timeline = BanlistTimelineBuilder.timeline(
            format: .tcg,
            revisionDates: TCGDates.all,
            statuses: ["2020-01-01": .limited],
            releaseDate: "2015-02-10")

        #expect(timeline.entries.count == 3)   // 2015-04-01, 2020-01-01, 2026-05-18
        #expect(timeline.entries.first?.effectiveDate == "2015-04-01")
        #expect(!timeline.entries.contains { $0.effectiveDate < "2015-02-10" })

        // A list published on the release date itself does describe the card.
        let sameDay = BanlistTimelineBuilder.timeline(
            format: .tcg, revisionDates: TCGDates.all,
            statuses: [:], releaseDate: "2015-01-01")
        #expect(sameDay.entries.first?.effectiveDate == "2015-01-01")

        // An unknown release date is unknown, not ancient: nothing is dropped.
        let unknown = BanlistTimelineBuilder.timeline(
            format: .tcg, revisionDates: TCGDates.all,
            statuses: [:], releaseDate: nil)
        #expect(unknown.entries.count == TCGDates.all.count)
    }

    /// Evidence for R2.AC5: most cards have never been on a list, and saying
    /// so explicitly is different from returning an empty history that a
    /// caller could read as "unknown".
    @Test func aCardOnNoListIsReportedNeverRestricted() {
        let timeline = BanlistTimelineBuilder.timeline(
            format: .tcg, revisionDates: TCGDates.all,
            statuses: [:], releaseDate: "1999-01-01")

        #expect(timeline.wasNeverRestricted)
        #expect(timeline.changes.isEmpty)
        #expect(timeline.entries.count == TCGDates.all.count)
        #expect(timeline.entries.allSatisfy { $0.status == .unlimited })

        // One restriction anywhere is enough to make that false.
        let once = BanlistTimelineBuilder.timeline(
            format: .tcg, revisionDates: TCGDates.all,
            statuses: ["2010-03-01": .semiLimited], releaseDate: "1999-01-01")
        #expect(!once.wasNeverRestricted)
    }
}
