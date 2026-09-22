import Foundation
import Testing
import YGOCore
@testable import YGOFeatureSettings

/// A refresher that can be held mid-run, so a second caller arrives while the
/// first is still in flight.
private actor HeldRefresher: CatalogRefreshing {
    private(set) var calls = 0
    private var release: CheckedContinuation<Void, Never>?

    func refresh() async -> CatalogSyncOutcome {
        calls += 1
        await withCheckedContinuation { continuation in
            release = continuation
        }
        return .alreadyCurrent
    }

    func waitUntilStarted() async {
        while calls == 0 { await Task.yield() }
    }

    func letItFinish() {
        release?.resume()
        release = nil
    }
}

private struct ImmediateRefresher: CatalogRefreshing {
    let outcome: CatalogSyncOutcome
    func refresh() async -> CatalogSyncOutcome { outcome }
}

@Suite("Catalog sync activity")
@MainActor
struct CatalogSyncActivityTests {
    /// Evidence for R2.AC7: the panel says what the launch already says,
    /// because it is the same mapping rather than a second wording of it.
    @Test func everyStageYieldsTheLineTheLaunchAlreadyShows() {
        #expect(CatalogSyncActivity.line(for: .init(stage: .checkingVersion))
            == "Controllo aggiornamenti…")
        #expect(CatalogSyncActivity.line(for: .init(stage: .downloading))
            == "Scarico il catalogo…")

        let activity = CatalogSyncActivity()
        #expect(activity.line == nil, "niente in corso, niente da dire")
        #expect(activity.isRunning == false)
    }

    /// Evidence for R2.AC7: the stage that can count its work says how much.
    @Test func theStoringStageCountsWhatItHasStored() {
        let line = CatalogSyncActivity.line(
            for: .init(stage: .storing, completed: 4_200, total: 14_566))
        #expect(line == "Salvo le carte: 4200 di 14566")

        let start = CatalogSyncActivity.line(
            for: .init(stage: .storing, completed: 0, total: 14_566))
        #expect(start == "Salvo le carte: 0 di 14566")
    }

    /// Evidence for R2.AC7: a finished run clears the line rather than leaving
    /// the last count on screen.
    @Test func theFinishedStageClearsTheLine() async {
        #expect(CatalogSyncActivity.line(for: .init(stage: .finished)) == nil)

        let activity = CatalogSyncActivity()
        activity.observe(.init(stage: .storing, completed: 1, total: 2))
        while activity.line == nil { await Task.yield() }
        #expect(activity.line == "Salvo le carte: 1 di 2")

        activity.observe(.init(stage: .finished))
        while activity.line != nil { await Task.yield() }
        #expect(activity.line == nil)
    }

    /// Evidence for R2.AC8: the second caller does not reach the refresher at
    /// all, which is asserted by counting its calls rather than by reading a flag.
    @Test func aSecondRunDuringARunReachesNoRefresher() async {
        let refresher = HeldRefresher()
        let activity = CatalogSyncActivity()

        let first = Task { await activity.run(refresher) }
        await refresher.waitUntilStarted()
        #expect(activity.isRunning)

        let second = await activity.run(refresher)
        #expect(second == nil, "il secondo non parte")
        #expect(await refresher.calls == 1, "e non raggiunge il refresher")

        await refresher.letItFinish()
        let outcome = await first.value
        #expect(outcome == .alreadyCurrent)
        #expect(activity.isRunning == false)
        #expect(activity.line == nil)

        // Once the first has finished, a later run is allowed again.
        let later = await activity.run(ImmediateRefresher(outcome: .updated(cardCount: 14_566)))
        #expect(later == .updated(cardCount: 14_566))
        #expect(await refresher.calls == 1)
    }
}
