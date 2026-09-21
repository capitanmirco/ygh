import Foundation
import Testing
import YGOBanlistHistory
import YGOCore
@testable import YGOFeatureCardDetail

@Suite("Card detail history")
struct CardDetailHistoryTests {
    /// Real TCG dates, so a timeline is checked against the shape the source
    /// publishes rather than an invented one.
    private static let dates = [
        "1999-08-01", "2004-03-01", "2005-03-01", "2005-09-01",
        "2010-03-01", "2015-01-01", "2020-01-01", "2026-05-18",
    ]

    private func loader(
        konamiID: Int? = 4007,
        release: CardRelease = .known(tcg: "2002-03-08", ocg: "1999-01-21"),
        statuses: [String: BanlistStatus] = [:],
        catalogStatus: BanStatus = .unlimited,
        revisionDates: [String]? = nil,
        failRevisions: Bool = false
    ) -> CardDetailLoader {
        var details = StubDetailReader()
        details.releases = [DetailCards.blueEyes.id: release]
        if let konamiID { details.konamiIDs = [DetailCards.blueEyes.id: konamiID] }

        var history = StubBanlistHistory()
        history.revisionDates = [.tcg: revisionDates ?? Self.dates]
        history.statuses = konamiID.map { [$0: statuses] } ?? [:]
        history.failRevisions = failRevisions

        return CardDetailLoader(
            catalog: StubCardRepository(
                statuses: [DetailCards.blueEyes.id: catalogStatus],
                cards: [DetailCards.blueEyes]),
            details: details,
            usage: StubUsageReader(),
            priceLookup: StubPriceLookup(),
            history: history,
            provenance: history)
    }

    /// Evidence for R5.AC1: what the card is right now, in the format being
    /// read. The panel opens on this before it opens on the history.
    @Test func reportsTheCurrentStatusInTheChosenFormat() async throws {
        let limited = await loader(
            statuses: ["2026-05-18": .limited], catalogStatus: .limited)
            .load(DetailCards.blueEyes, language: .italian, format: .tcg)
        #expect(limited.currentStatus == .limited)

        let free = await loader(catalogStatus: .unlimited)
            .load(DetailCards.blueEyes, language: .italian, format: .tcg)
        #expect(free.currentStatus == .unlimited)
    }

    /// Evidence for R5.AC2: what a duelist means by history is the moments it
    /// moved, with what it moved from and to.
    @Test func reportsEachChangeWithItsDateAndBothStatuses() async throws {
        let detail = await loader(
            statuses: [
                "2005-03-01": .forbidden, "2005-09-01": .forbidden,
                "2010-03-01": .forbidden,
            ],
            catalogStatus: .unlimited)
            .load(DetailCards.blueEyes, language: .italian, format: .tcg)

        let timeline = try #require(detail.history.timelineValue)
        // The card existed from 2002, so the 1999 list says nothing about it.
        #expect(timeline.entries.count == 7)
        #expect(timeline.entries.first?.effectiveDate == "2004-03-01")

        let changes = detail.history.changes
        #expect(changes.count == 2)
        #expect(changes[0].effectiveDate == "2005-03-01")
        #expect(changes[0].from == .unlimited)
        #expect(changes[0].to == .forbidden)
        #expect(changes[1].effectiveDate == "2015-01-01")
        #expect(changes[1].from == .forbidden)
        #expect(changes[1].to == .unlimited)
    }

    /// Evidence for R5.AC3: most cards have never been on a list. Saying so is
    /// an answer; showing an empty table is not.
    @Test func aCardOnNoListSaysNeverRestricted() async throws {
        let detail = await loader(statuses: [:])
            .load(DetailCards.blueEyes, language: .italian, format: .tcg)

        guard case let .neverRestricted(format) = detail.history else {
            Issue.record("expected neverRestricted, got \(detail.history)")
            return
        }
        #expect(format == .tcg)
        #expect(detail.history.changes.isEmpty)
        #expect(detail.history.timelineValue == nil)
    }

    /// Evidence for R5.AC4: 203 of 14,566 cards carry no Konami identifier, so
    /// they cannot be joined to any published list. That is not a fact about
    /// the card's history; it is the absence of one.
    @Test func aCardWithoutAKonamiIdSaysHistoryUnavailable() async throws {
        let detail = await loader(konamiID: nil)
            .load(DetailCards.blueEyes, language: .italian, format: .tcg)

        guard case let .unavailable(reason) = detail.history else {
            Issue.record("expected unavailable, got \(detail.history)")
            return
        }
        #expect(reason.contains("identificativo Konami"))
        #expect(detail.history.changes.isEmpty)

        // A history that could not be read at all reads the same way: unknown,
        // never "clean".
        let broken = await loader(failRevisions: true)
            .load(DetailCards.blueEyes, language: .italian, format: .tcg)
        #expect(broken.history.timelineValue == nil)
        if case .unavailable = broken.history {} else {
            Issue.record("expected unavailable, got \(broken.history)")
        }

        // So does a format whose lists have not been downloaded yet.
        let nothingStored = await loader(revisionDates: [])
            .load(DetailCards.blueEyes, language: .italian, format: .tcg)
        if case let .unavailable(reason) = nothingStored.history {
            #expect(reason.contains("TCG"))
        } else {
            Issue.record("expected unavailable, got \(nothingStored.history)")
        }
    }

    /// Evidence for R5.AC3 and R5.AC4 together, which is the point: these two
    /// read alike in a panel and mean opposite things. "Never restricted" is
    /// knowledge; "unavailable" is its absence. A single empty case would
    /// quietly tell 203 cards' readers the first when only the second is true.
    @Test func neverRestrictedAndUnavailableAreDifferentAnswers() async throws {
        let clean = await loader(statuses: [:])
            .load(DetailCards.blueEyes, language: .italian, format: .tcg)
        let unknown = await loader(konamiID: nil)
            .load(DetailCards.blueEyes, language: .italian, format: .tcg)

        #expect(clean.history != unknown.history)
        #expect(clean.history.changes.isEmpty)
        #expect(unknown.history.changes.isEmpty)

        // Both are empty of changes, and only one of them is a claim.
        if case .neverRestricted = clean.history {} else {
            Issue.record("expected neverRestricted, got \(clean.history)")
        }
        if case .unavailable = unknown.history {} else {
            Issue.record("expected unavailable, got \(unknown.history)")
        }
    }

    /// Evidence for R5.AC5: the catalog and the history are two sources. On
    /// the 222 cards both described they agreed, which is evidence and not a
    /// guarantee — so when they differ, both figures are shown and neither is
    /// quietly preferred.
    @Test func aDisagreementShowsBothFiguresNamed() async throws {
        let detail = await loader(
            statuses: ["2026-05-18": .limited],
            catalogStatus: .forbidden)
            .load(DetailCards.blueEyes, language: .italian, format: .tcg)

        let disagreement = try #require(detail.disagreement)
        #expect(disagreement.catalogStatus == .forbidden)
        #expect(disagreement.historyStatus == .limited)
        #expect(disagreement.historyEffectiveDate == "2026-05-18")
        #expect(disagreement.historySource == "yaml-yugi-limit-regulation")
        #expect(disagreement.konamiID == 4007)
        #expect(disagreement.name == "Drago Bianco Occhi Blu")

        // Neither table was changed to match the other.
        #expect(detail.currentStatus == .forbidden)
        #expect(detail.history.timelineValue?.currentStatus == .limited)

        // Agreement reports nothing, which is the ordinary case.
        let agreeing = await loader(
            statuses: ["2026-05-18": .limited], catalogStatus: .limited)
            .load(DetailCards.blueEyes, language: .italian, format: .tcg)
        #expect(agreeing.disagreement == nil)
    }
}
