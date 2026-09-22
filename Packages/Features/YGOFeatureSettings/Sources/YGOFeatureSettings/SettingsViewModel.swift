import Foundation
import Observation
import YGOCore

/// A deletion the user has been asked to confirm.
///
/// Exactly one can be armed. The window draws one alert bound to this, which
/// is what keeps two confirmations from racing for one sequence — the shape
/// that produced this project's deck deletion bug.
public enum MaintenanceRequest: Hashable, Sendable {
    case purgeArtwork
    case deleteBackup
}

/// One figure as the panel reports it: what it measures, and the value with
/// its unit. Accessibility reads the pair, so a measurement cannot reach the
/// screen as a bare number.
public struct ReportedValue: Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let value: String

    public init(id: String, label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }

    public var accessibilityLabel: String { "\(label): \(value)" }
}

/// What happened the last time an update was asked for.
public enum CheckReport: Hashable, Sendable {
    case upToDate
    case updated(cardCount: Int)
    case failed(reason: String)

    public var sentence: String {
        switch self {
        case .upToDate: "Il catalogo è già aggiornato."
        case .updated(let cardCount): "Catalogo aggiornato: \(cardCount) carte."
        case .failed(let reason): "Controllo non riuscito, catalogo invariato. \(reason)"
        }
    }
}

/// The settings window's state.
@MainActor
@Observable
public final class SettingsViewModel {
    private let statusReader: any CatalogStatusReading
    private let refresher: any CatalogRefreshing
    private let inventory: any StorageInventorying
    private let preferenceStore: any PreferenceStoring
    private let now: @Sendable () -> Date

    public let activity: CatalogSyncActivity

    /// Nil until read. The window draws before either is known: walking 14,730
    /// files takes long enough to be seen, and a panel of zeroes that later
    /// turn into real figures is a panel that lied for a moment.
    public private(set) var status: CatalogStatus?
    public private(set) var footprint: StorageFootprint?
    public private(set) var pending: MaintenanceRequest?
    public private(set) var report: CheckReport?
    public private(set) var preferences: Preferences

    public init(
        status: any CatalogStatusReading,
        refresher: any CatalogRefreshing,
        inventory: any StorageInventorying,
        preferences: any PreferenceStoring,
        activity: CatalogSyncActivity = CatalogSyncActivity(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.statusReader = status
        self.refresher = refresher
        self.inventory = inventory
        self.preferenceStore = preferences
        self.activity = activity
        self.now = now
        self.preferences = preferences.load()
    }

    // MARK: - Reading

    public func load() async {
        status = try? await statusReader.catalogStatus()
        footprint = await inventory.footprint()
    }

    /// Runs the launch's own synchronisation.
    ///
    /// Not `synchronize()` directly: the launch calls a flow that also fills
    /// artwork behind the interface, and two entry points differing by a
    /// background task is the divergence this project has already paid for.
    public func checkForUpdates() async {
        guard let outcome = await activity.run(refresher) else { return }

        switch outcome {
        case .alreadyCurrent:
            report = .upToDate
        case .seeded(let cardCount), .updated(let cardCount):
            report = .updated(cardCount: cardCount)
        case .keptStoredCatalog(let reason):
            report = .failed(reason: reason)
        }

        // Recorded here rather than in `sync_state`: that row moves only when a
        // dataset is stored, so it cannot answer when the application last looked.
        preferences.lastCheckedAt = now()
        preferenceStore.save(preferences)

        status = try? await statusReader.catalogStatus()
    }

    // MARK: - Maintenance

    /// Arms a confirmation. Deletes nothing.
    public func ask(_ request: MaintenanceRequest) {
        pending = request
    }

    public func cancel() {
        pending = nil
    }

    /// Performs exactly the request the user confirmed, then re-measures
    /// rather than trusting the figures reported a moment ago.
    ///
    /// It takes the request rather than reading `pending`, because the alert's
    /// dismissal clears `pending` before the button's action runs. Reading it
    /// here is how a confirmed deletion quietly did nothing.
    public func confirm(_ request: MaintenanceRequest) async {
        pending = nil

        switch request {
        case .purgeArtwork: try? await inventory.purgeArtwork()
        case .deleteBackup: try? await inventory.deleteBackup()
        }

        footprint = await inventory.footprint()
    }

    /// Performs whatever is armed. For callers that are not an alert.
    public func confirm() async {
        guard let request = pending else { return }
        await confirm(request)
    }

    // MARK: - Preferences

    public func setStartingSection(_ section: AppSection) {
        preferences.startingSection = section
        preferenceStore.save(preferences)
    }

    public func setCardLanguage(_ language: CardLanguage) {
        preferences.cardLanguage = language
        preferenceStore.save(preferences)
    }

    // MARK: - What the panel reports

    public var catalogValues: [ReportedValue] {
        guard let status else { return [] }
        var values = [
            ReportedValue(id: "version", label: "Versione del catalogo", value: status.version),
            ReportedValue(
                id: "cards", label: "Carte memorizzate",
                value: "\(status.cardCount) carte"),
        ]
        if let upstream = status.upstreamUpdatedAt {
            values.append(ReportedValue(
                id: "upstream", label: "Aggiornato all'origine il",
                value: Self.day(upstream)))
        }
        if let synced = status.lastSyncAt {
            values.append(ReportedValue(
                id: "synced", label: "Scaricato il", value: Self.moment(synced)))
        }
        if let checked = preferences.lastCheckedAt {
            values.append(ReportedValue(
                id: "checked", label: "Ultimo controllo", value: Self.moment(checked)))
        }
        return values
    }

    public var storageValues: [ReportedValue] {
        guard let footprint else { return [] }
        var values = [
            ReportedValue(
                id: "artwork", label: "Immagini delle carte",
                value: "\(Self.bytes(footprint.artworkBytes)) in \(footprint.artworkFiles) file"),
            ReportedValue(
                id: "database", label: "Database delle carte",
                value: Self.bytes(footprint.databaseBytes)),
        ]
        if let backup = footprint.backupBytes {
            values.append(ReportedValue(
                id: "backup", label: "Backup precedente alla migrazione",
                value: Self.bytes(backup)))
        }
        values.append(ReportedValue(
            id: "total", label: "Totale su disco", value: Self.bytes(footprint.totalBytes)))
        return values
    }

    /// Every figure the panel shows, which is what `NFR2` is asserted over.
    public var reportedValues: [ReportedValue] { catalogValues + storageValues }

    static func bytes(_ count: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(count))
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "it_IT")))
    }

    static func moment(_ date: Date) -> String {
        date.formatted(
            .dateTime.day().month(.wide).year().hour().minute()
                .locale(Locale(identifier: "it_IT")))
    }
}
