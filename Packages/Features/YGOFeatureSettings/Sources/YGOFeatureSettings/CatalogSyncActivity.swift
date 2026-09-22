import Foundation
import Observation
import YGOCore

/// One synchronisation, as the interface sees it.
///
/// The launch and the settings panel both report a synchronisation, and before
/// this existed each kept its own progress line and its own idea of whether a
/// run was in flight. Two objects holding one truth means the second one is
/// always the stale one, so there is one object and both read it.
@MainActor
@Observable
public final class CatalogSyncActivity {
    /// What to show while a run is happening, or nil when nothing is.
    public private(set) var line: String?
    public private(set) var isRunning = false

    public init() {}

    /// The stage-to-sentence mapping, as a function of a value.
    ///
    /// Static and pure on purpose: it is the whole of what the progress line
    /// says, and this project has no way to prove a window.
    public nonisolated static func line(for progress: CatalogSyncProgress) -> String? {
        switch progress.stage {
        case .checkingVersion: "Controllo aggiornamenti…"
        case .downloading: "Scarico il catalogo…"
        case .storing: "Salvo le carte: \(progress.completed) di \(progress.total)"
        case .finished: nil
        }
    }

    /// Handed to `CatalogEnvironment.live(observeSync:)` at startup, so every
    /// synchronisation reports here whoever asked for it.
    public nonisolated func observe(_ progress: CatalogSyncProgress) {
        Task { @MainActor in self.line = Self.line(for: progress) }
    }

    /// Runs one synchronisation, or returns nil because one is already running.
    ///
    /// The guard is here rather than in a view: a second caller must not reach
    /// the refresher at all, which is what stops two downloads of 41 MB from
    /// racing into the same transaction.
    public func run(_ refresher: any CatalogRefreshing) async -> CatalogSyncOutcome? {
        guard !isRunning else { return nil }
        isRunning = true
        defer {
            isRunning = false
            line = nil
        }
        return await refresher.refresh()
    }
}
