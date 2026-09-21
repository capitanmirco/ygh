import Foundation
import Observation
import YGOBanlistHistory
import YGOCore
import YGONetworking
import YGOPersistence
import YGOSync

/// Downloads the published Forbidden & Limited Lists on demand.
///
/// `banlist-history` proved the synchroniser and nothing ever called it: the
/// database held zero revisions, so every card's history panel said no list
/// had been downloaded. This is the caller.
///
/// On demand rather than at launch: 177 files at every start would cost every
/// session for data most of them never look at.
@MainActor
@Observable
public final class BanlistSyncCoordinator {
    public enum State: Hashable, Sendable {
        case idle
        case running(stored: Int)
        case finished(stored: Int, alreadyHeld: Int, unmatched: Int)
        case failed(reason: String)
    }

    public private(set) var state: State = .idle

    private let synchronizer: BanlistHistorySynchronizer?
    private let store: SQLiteBanlistHistory

    public init(environment: CatalogEnvironment) {
        self.store = environment.banlistHistory
        // A graph built without a transport substitutes its own upstream, so
        // it has nothing to synchronise through and says so rather than
        // pretending to try.
        self.synchronizer = environment.transport.map { transport in
            BanlistHistorySynchronizer(
                client: YAMLYugiBanlistClient(transport: transport),
                store: environment.banlistHistory,
                source: YAMLYugiBanlistClient.source)
        }
    }

    /// Built directly, which is what a test does to drive it with recorded
    /// lists instead of a host.
    public init(store: SQLiteBanlistHistory, client: any BanlistFetching) {
        self.store = store
        self.synchronizer = BanlistHistorySynchronizer(
            client: client, store: store, source: YAMLYugiBanlistClient.source)
    }

    /// How many lists are already stored, which is what makes the state before
    /// a first synchronisation legible rather than broken.
    public var storedListCount: Int {
        BanlistFormat.allCases.reduce(0) { total, format in
            total + ((try? store.revisions(for: format).count) ?? 0)
        }
    }

    public var hasAnyList: Bool { storedListCount > 0 }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public func synchronize() async {
        guard !isRunning, let synchronizer else {
            if synchronizer == nil { state = .failed(reason: "nessuna connessione configurata") }
            return
        }
        state = .running(stored: storedListCount)

        let report = await synchronizer.synchronize()

        guard report.succeeded else {
            // What was stored stays; only the rest is lost.
            state = .failed(reason: report.failures.values.first ?? "motivo sconosciuto")
            return
        }

        state = .finished(
            stored: report.storedTotal,
            alreadyHeld: report.alreadyHeld.values.reduce(0, +),
            unmatched: report.unmatchedKonamiIDs)
    }

    public var summary: String {
        switch state {
        case .idle:
            hasAnyList
                ? "\(storedListCount) liste memorizzate."
                : "Nessuna lista scaricata."
        case .running(let stored):
            "Scaricamento in corso… \(stored) liste memorizzate."
        case let .finished(stored, alreadyHeld, unmatched):
            stored == 0
                ? "Già aggiornato: \(alreadyHeld) liste."
                : "Scaricate \(stored) liste"
                    + (unmatched > 0 ? ", \(unmatched) carte non abbinate." : ".")
        case .failed(let reason):
            "Scaricamento non riuscito: \(reason)"
        }
    }
}
