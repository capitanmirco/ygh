import Foundation
import Testing
import YGOCore
@testable import YGOBanlistHistory

@Suite("Banlist changes")
struct BanlistChangeTests {
    /// Evidence for R2.AC4: a card forbidden in 2005 and unrestricted in 2015
    /// moved twice. The baseline before the first list is unrestricted, so
    /// being forbidden on the first list it appears on is itself a change.
    @Test func reportsExactlyTwoChangesWithTheirDates() {
        let timeline = BanlistTimelineBuilder.timeline(
            format: .tcg,
            revisionDates: TCGDates.all,
            statuses: [
                "2005-03-01": .forbidden, "2005-09-01": .forbidden,
                "2006-03-01": .forbidden, "2010-03-01": .forbidden,
            ],
            releaseDate: "1999-01-01")

        let changes = timeline.changes
        #expect(changes.count == 2)

        #expect(changes[0].effectiveDate == "2005-03-01")
        #expect(changes[0].from == .unlimited)
        #expect(changes[0].to == .forbidden)

        // Unnamed on the 2015 list, which is how a card comes back.
        #expect(changes[1].effectiveDate == "2015-01-01")
        #expect(changes[1].from == .forbidden)
        #expect(changes[1].to == .unlimited)

        // The lists in between held it forbidden and are not changes.
        #expect(!changes.contains { $0.effectiveDate == "2006-03-01" })
        #expect(changes.map(\.effectiveDate) == changes.map(\.effectiveDate).sorted())
    }

    /// Evidence for R2.AC4: a card that never moved reports no changes, which
    /// is what most of the catalog looks like. A card that steps through every
    /// status reports one change per step, so the count is not a coincidence
    /// of the previous case.
    @Test func aCardThatNeverMovedReportsNoChanges() {
        let still = BanlistTimelineBuilder.timeline(
            format: .tcg, revisionDates: TCGDates.all,
            statuses: [:], releaseDate: "1999-01-01")
        #expect(still.changes.isEmpty)

        // Limited on every single list: restricted throughout, moved once.
        let alwaysLimited = BanlistTimelineBuilder.timeline(
            format: .tcg, revisionDates: TCGDates.all,
            statuses: Dictionary(uniqueKeysWithValues:
                TCGDates.all.map { ($0, BanlistStatus.limited) }),
            releaseDate: "1999-01-01")
        #expect(alwaysLimited.changes.count == 1)
        #expect(alwaysLimited.changes[0].effectiveDate == "1999-08-01")
        #expect(!alwaysLimited.wasNeverRestricted)

        // Every step reported. Note 2005-09-01: the card is named on neither
        // that list nor the one before 2006, so it goes free and comes back,
        // and both of those are changes. A history that skipped them would be
        // claiming the card sat still while the game moved it twice.
        let wandering = BanlistTimelineBuilder.timeline(
            format: .tcg, revisionDates: TCGDates.all,
            statuses: [
                "2004-03-01": .forbidden,
                "2005-03-01": .limited,
                "2006-03-01": .semiLimited,
            ],
            releaseDate: "1999-01-01")
        #expect(wandering.changes.count == 5)
        #expect(wandering.changes.map(\.to)
                == [.forbidden, .limited, .unlimited, .semiLimited, .unlimited])
        #expect(wandering.changes.map(\.effectiveDate)
                == ["2004-03-01", "2005-03-01", "2005-09-01",
                    "2006-03-01", "2010-03-01"])

        // A card that only ever existed after its last change still reports it.
        let recent = BanlistTimelineBuilder.timeline(
            format: .tcg, revisionDates: TCGDates.all,
            statuses: ["2026-05-18": .forbidden], releaseDate: "2020-06-01")
        #expect(recent.changes.count == 1)
        #expect(recent.changes[0].effectiveDate == "2026-05-18")
        #expect(recent.currentStatus == .forbidden)
    }
}
