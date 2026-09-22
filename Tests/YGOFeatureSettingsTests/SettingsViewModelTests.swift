import Foundation
import Testing
import YGOCore
@testable import YGOFeatureSettings

// MARK: - Stubs

/// A status reader that counts its reads, so a test can tell a value that was
/// re-read from one that was cached.
private final class StatusStub: CatalogStatusReading, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: CatalogStatus?
    private(set) var reads = 0

    init(_ status: CatalogStatus?) { stored = status }

    var current: CatalogStatus? {
        lock.withLock { stored }
    }

    func replace(with status: CatalogStatus?) {
        lock.withLock { stored = status }
    }

    func catalogStatus() async throws -> CatalogStatus? {
        lock.withLock {
            reads += 1
            return stored
        }
    }
}

private final class RefresherStub: CatalogRefreshing, @unchecked Sendable {
    private let lock = NSLock()
    private let outcome: CatalogSyncOutcome
    /// What a real synchronisation would do to the stored state.
    private let onRefresh: (@Sendable () -> Void)?
    private(set) var calls = 0

    init(_ outcome: CatalogSyncOutcome, onRefresh: (@Sendable () -> Void)? = nil) {
        self.outcome = outcome
        self.onRefresh = onRefresh
    }

    var callCount: Int { lock.withLock { calls } }

    func refresh() async -> CatalogSyncOutcome {
        lock.withLock { calls += 1 }
        onRefresh?()
        return outcome
    }
}

/// An inventory over a real temporary directory: asking must not delete, and
/// "must not delete" is only worth asserting against files that exist.
private final class InventoryStub: StorageInventorying, @unchecked Sendable {
    let directory: URL
    private let lock = NSLock()
    private(set) var purges = 0
    private(set) var backupDeletions = 0

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "ygo-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory.appending(path: "Artwork"), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4_000)
            .write(to: directory.appending(path: "Artwork/thumb.jpg"))
        try Data(repeating: 0x42, count: 12_345)
            .write(to: directory.appending(path: "library.pre-migration.sqlite"))
    }

    var artworkExists: Bool {
        FileManager.default.fileExists(
            atPath: directory.appending(path: "Artwork/thumb.jpg").path(percentEncoded: false))
    }

    var backupExists: Bool {
        FileManager.default.fileExists(
            atPath: directory.appending(path: "library.pre-migration.sqlite")
                .path(percentEncoded: false))
    }

    func footprint() async -> StorageFootprint {
        StorageFootprint(
            artworkFiles: artworkExists ? 1 : 0,
            artworkBytes: artworkExists ? 4_000 : 0,
            databaseBytes: 42_000_000,
            backupBytes: backupExists ? 12_345 : nil)
    }

    func purgeArtwork() async throws {
        lock.withLock { purges += 1 }
        try? FileManager.default.removeItem(at: directory.appending(path: "Artwork/thumb.jpg"))
    }

    func deleteBackup() async throws {
        lock.withLock { backupDeletions += 1 }
        try? FileManager.default.removeItem(
            at: directory.appending(path: "library.pre-migration.sqlite"))
    }

    func tearDown() { try? FileManager.default.removeItem(at: directory) }
}

private final class PreferenceStub: PreferenceStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Preferences()
    private(set) var writes = 0

    var current: Preferences { lock.withLock { stored } }
    var writeCount: Int { lock.withLock { writes } }

    func load() -> Preferences { lock.withLock { stored } }

    func save(_ preferences: Preferences) {
        lock.withLock {
            stored = preferences
            writes += 1
        }
    }
}

// MARK: - Tests

@Suite("Settings view model")
@MainActor
struct SettingsViewModelTests {
    private let storedStatus = CatalogStatus(
        version: "147.04",
        upstreamUpdatedAt: Date(timeIntervalSinceReferenceDate: 811_209_912),
        lastSyncAt: Date(timeIntervalSinceReferenceDate: 811_594_159),
        cardCount: 14_566)

    private func makeModel(
        status: StatusStub,
        refresher: RefresherStub,
        inventory: InventoryStub,
        preferences: PreferenceStub,
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSinceReferenceDate: 811_766_400) }
    ) -> SettingsViewModel {
        SettingsViewModel(
            status: status, refresher: refresher, inventory: inventory,
            preferences: preferences, now: now)
    }

    /// Evidence for R2.AC4: a check that finds nothing new leaves the stored
    /// catalog exactly as it was — only the check time moves, and it lives in
    /// the preferences rather than in `sync_state`.
    @Test func aCheckThatFindsNothingNewStoresNothing() async throws {
        let status = StatusStub(storedStatus)
        let inventory = try InventoryStub()
        defer { inventory.tearDown() }
        let preferences = PreferenceStub()
        let model = makeModel(
            status: status, refresher: RefresherStub(.alreadyCurrent),
            inventory: inventory, preferences: preferences)

        await model.load()
        await model.checkForUpdates()

        #expect(model.report == .upToDate)
        #expect(model.status == storedStatus, "niente è cambiato nel catalogo")
        #expect(status.current == storedStatus)
        #expect(preferences.current.lastCheckedAt
            == Date(timeIntervalSinceReferenceDate: 811_766_400))
        #expect(preferences.current.startingSection == .catalog, "e nient'altro si muove")
    }

    /// Evidence for R2.AC4: the manual check is the launch's synchronisation,
    /// reached through the one seam, rather than a second implementation.
    @Test func theCheckGoesThroughTheSameRefresherTheLaunchUses() async throws {
        let status = StatusStub(storedStatus)
        let inventory = try InventoryStub()
        defer { inventory.tearDown() }
        let refresher = RefresherStub(.alreadyCurrent)
        let model = makeModel(
            status: status, refresher: refresher,
            inventory: inventory, preferences: PreferenceStub())

        #expect(refresher.callCount == 0)
        await model.checkForUpdates()
        #expect(refresher.callCount == 1)

        await model.checkForUpdates()
        #expect(refresher.callCount == 2, "una richiesta, una sincronizzazione")
    }

    /// Evidence for R2.AC5: a newer upstream version is reported as a change,
    /// and the panel re-reads rather than keeping the version it opened with.
    @Test func aNewerUpstreamVersionIsReportedAsAnUpdate() async throws {
        let status = StatusStub(storedStatus)
        let inventory = try InventoryStub()
        defer { inventory.tearDown() }
        let newer = CatalogStatus(
            version: "147.10", upstreamUpdatedAt: storedStatus.upstreamUpdatedAt,
            lastSyncAt: Date(timeIntervalSinceReferenceDate: 811_766_400), cardCount: 14_600)
        let refresher = RefresherStub(.updated(cardCount: 14_600)) { status.replace(with: newer) }

        let model = makeModel(
            status: status, refresher: refresher,
            inventory: inventory, preferences: PreferenceStub())
        await model.load()
        #expect(model.status?.version == "147.04")

        await model.checkForUpdates()
        #expect(model.report == .updated(cardCount: 14_600))
        #expect(model.status?.version == "147.10")
        #expect(model.status?.cardCount == 14_600)
    }

    /// Evidence for R2.AC6 and NFR1: an unreachable upstream costs freshness,
    /// never the catalog, and the panel says which of the two happened.
    @Test func anUnreachableUpstreamKeepsTheStoredCatalogAndSaysSo() async throws {
        let status = StatusStub(storedStatus)
        let inventory = try InventoryStub()
        defer { inventory.tearDown() }
        let model = makeModel(
            status: status,
            refresher: RefresherStub(.keptStoredCatalog(reason: "offline")),
            inventory: inventory, preferences: PreferenceStub())

        await model.load()
        await model.checkForUpdates()

        #expect(model.report == .failed(reason: "offline"))
        #expect(model.report?.sentence.contains("catalogo invariato") == true)
        #expect(model.status == storedStatus)
        #expect(model.status?.cardCount == 14_566)

        // The storage panel is unaffected: nothing there needs a network.
        #expect(model.footprint?.artworkFiles == 1)
        #expect(model.footprint?.databaseBytes == 42_000_000)
    }

    /// Evidence for R3.AC4 and NFR3: asking arms a confirmation and touches
    /// nothing. The files are real, so "touches nothing" is observable.
    @Test func askingToPurgeDeletesNothingUntilItIsConfirmed() async throws {
        let inventory = try InventoryStub()
        defer { inventory.tearDown() }
        let model = makeModel(
            status: StatusStub(storedStatus), refresher: RefresherStub(.alreadyCurrent),
            inventory: inventory, preferences: PreferenceStub())
        await model.load()

        model.ask(.purgeArtwork)
        #expect(model.pending == .purgeArtwork)
        #expect(inventory.artworkExists)
        #expect(inventory.purges == 0)

        await model.confirm()
        #expect(model.pending == nil)
        #expect(inventory.purges == 1)
        #expect(!inventory.artworkExists)
        #expect(model.footprint?.artworkFiles == 0, "e il pannello si rimisura")
        #expect(inventory.backupExists, "il backup non era quello armato")
    }

    /// Evidence for R3.AC7 and NFR3: the same for the backup, which is the
    /// deletion that gives up a hand rollback to the previous schema.
    @Test func askingToDeleteTheBackupDeletesNothingUntilItIsConfirmed() async throws {
        let inventory = try InventoryStub()
        defer { inventory.tearDown() }
        let model = makeModel(
            status: StatusStub(storedStatus), refresher: RefresherStub(.alreadyCurrent),
            inventory: inventory, preferences: PreferenceStub())
        await model.load()
        #expect(model.footprint?.backupBytes == 12_345)

        model.ask(.deleteBackup)
        #expect(inventory.backupExists)
        #expect(inventory.backupDeletions == 0)

        await model.confirm()
        #expect(inventory.backupDeletions == 1)
        #expect(!inventory.backupExists)
        #expect(model.footprint?.backupBytes == nil)
        #expect(inventory.artworkExists, "le immagini non erano quelle armate")
    }

    /// Evidence for R3.AC4 and R3.AC7: declining is a real outcome, not an
    /// absence of one.
    @Test func cancellingAnArmedRequestLeavesEverythingOnDisk() async throws {
        let inventory = try InventoryStub()
        defer { inventory.tearDown() }
        let model = makeModel(
            status: StatusStub(storedStatus), refresher: RefresherStub(.alreadyCurrent),
            inventory: inventory, preferences: PreferenceStub())

        model.ask(.purgeArtwork)
        model.cancel()
        #expect(model.pending == nil)

        // Confirming with nothing armed must also do nothing.
        await model.confirm()
        #expect(inventory.purges == 0)
        #expect(inventory.backupDeletions == 0)
        #expect(inventory.artworkExists)
        #expect(inventory.backupExists)
    }

    /// Evidence for NFR3: one armed request at a time, so the window can bind
    /// one alert and two confirmations cannot race for one sequence.
    @Test func onlyOneRequestCanBeArmedAtATime() async throws {
        let inventory = try InventoryStub()
        defer { inventory.tearDown() }
        let model = makeModel(
            status: StatusStub(storedStatus), refresher: RefresherStub(.alreadyCurrent),
            inventory: inventory, preferences: PreferenceStub())

        model.ask(.purgeArtwork)
        model.ask(.deleteBackup)
        #expect(model.pending == .deleteBackup, "l'ultima richiesta sostituisce, non si accoda")

        await model.confirm()
        #expect(inventory.backupDeletions == 1)
        #expect(inventory.purges == 0, "la richiesta sostituita non viene eseguita dopo")
        #expect(inventory.artworkExists)
    }

    /// Evidence for NFR4: the window is drawn before it is measured. Walking
    /// 14,730 files is long enough to be seen, and zeroes that later become
    /// real figures are a panel that lied for a moment.
    @Test func thePanelHasNoFootprintUntilItHasBeenMeasured() async throws {
        let inventory = try InventoryStub()
        defer { inventory.tearDown() }
        let model = makeModel(
            status: StatusStub(storedStatus), refresher: RefresherStub(.alreadyCurrent),
            inventory: inventory, preferences: PreferenceStub())

        #expect(model.footprint == nil)
        #expect(model.status == nil)
        #expect(model.storageValues.isEmpty)
        #expect(model.catalogValues.isEmpty)

        await model.load()
        #expect(model.footprint != nil)
        #expect(model.status != nil)
        #expect(!model.reportedValues.isEmpty)
    }

    /// Evidence for NFR2: no figure reaches the screen as a bare number.
    @Test func everyReportedMeasurementNamesWhatItMeasuresAndItsUnit() async throws {
        let inventory = try InventoryStub()
        defer { inventory.tearDown() }
        let preferences = PreferenceStub()
        let model = makeModel(
            status: StatusStub(storedStatus), refresher: RefresherStub(.alreadyCurrent),
            inventory: inventory, preferences: preferences)
        await model.load()
        await model.checkForUpdates()

        #expect(model.reportedValues.count >= 7)
        for value in model.reportedValues {
            #expect(!value.label.isEmpty)
            #expect(!value.value.isEmpty)
            #expect(value.accessibilityLabel == "\(value.label): \(value.value)")
            #expect(value.accessibilityLabel.contains(":"))
        }

        let byIdentifier = Dictionary(
            uniqueKeysWithValues: model.reportedValues.map { ($0.id, $0) })
        #expect(byIdentifier["cards"]?.value == "14566 carte")
        #expect(byIdentifier["artwork"]?.value.contains("file") == true)
        #expect(byIdentifier["database"]?.value.contains("MB") == true)
        #expect(byIdentifier["backup"]?.value.contains("KB") == true)
        #expect(byIdentifier["checked"] != nil, "anche l'ultimo controllo è una misura")
    }

    /// Evidence for R2.AC1, R2.AC2, R2.AC3 and R3.AC1: what the panel says
    /// about a stored catalog, read from one snapshot.
    @Test func theStoredCatalogIsReportedAsFourReadableFacts() async throws {
        let inventory = try InventoryStub()
        defer { inventory.tearDown() }
        let model = makeModel(
            status: StatusStub(storedStatus), refresher: RefresherStub(.alreadyCurrent),
            inventory: inventory, preferences: PreferenceStub())
        await model.load()

        let values = Dictionary(uniqueKeysWithValues: model.catalogValues.map { ($0.id, $0.value) })
        #expect(values["version"] == "147.04")
        #expect(values["cards"] == "14566 carte")
        #expect(values["upstream"]?.contains("2026") == true)
        #expect(values["synced"]?.contains("2026") == true)
        #expect(values["checked"] == nil, "prima di un controllo non c'è un ultimo controllo")

        let storage = Dictionary(uniqueKeysWithValues: model.storageValues.map { ($0.id, $0.value) })
        #expect(storage["artwork"]?.contains("1 file") == true)
        #expect(storage["total"] != nil)
    }
}

@Suite("Settings confirmation sequencing")
@MainActor
struct SettingsConfirmationSequencingTests {
    private func makeModel(_ inventory: InventoryStub) -> SettingsViewModel {
        SettingsViewModel(
            status: StatusStub(nil), refresher: RefresherStub(.alreadyCurrent),
            inventory: inventory, preferences: PreferenceStub())
    }

    /// The alert's dismissal clears the armed request before the button's
    /// action runs, so a confirmed purge quietly did nothing.
    ///
    /// The window's remedy is to capture the request while the alert is built
    /// and hand it to `confirm(_:)`. This is that sequence: cleared first, as
    /// a dismissal clears it, and the deletion still has to happen.
    @Test func confirmingACapturedRequestClearedByTheDismissalStillPerformsIt() async throws {
        let inventory = try InventoryStub()
        defer { inventory.tearDown() }
        let model = makeModel(inventory)
        await model.load()

        model.ask(.purgeArtwork)
        let captured = try #require(model.pending)

        // What the dismissal does before the action runs.
        model.cancel()
        #expect(model.pending == nil)

        // Reading the model here is what deleted nothing.
        await model.confirm()
        #expect(inventory.purges == 0)
        #expect(inventory.artworkExists)

        // Handing over what the user confirmed performs it.
        await model.confirm(captured)
        #expect(inventory.purges == 1)
        #expect(!inventory.artworkExists)
        #expect(model.footprint?.artworkFiles == 0)
    }

    /// The same for the backup, and it must be the captured request that runs
    /// rather than whatever happens to be armed at the time.
    @Test func confirmingACapturedRequestPerformsThatRequestAndNoOther() async throws {
        let inventory = try InventoryStub()
        defer { inventory.tearDown() }
        let model = makeModel(inventory)
        await model.load()

        model.ask(.deleteBackup)
        let captured = try #require(model.pending)
        model.cancel()

        // Something else gets armed in the meantime.
        model.ask(.purgeArtwork)

        await model.confirm(captured)
        #expect(inventory.backupDeletions == 1)
        #expect(!inventory.backupExists)
        #expect(inventory.purges == 0, "esegue ciò che è stato confermato, non ciò che è armato")
        #expect(inventory.artworkExists)
        #expect(model.pending == nil, "e disarma comunque")
    }
}
