---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-22T08:36:57Z
last_modified: 2026-09-22T08:36:57Z
approved_fingerprint: sha256:72eacacec6f33002655e59c374ac37be15ba7bdcef2e944b95895f3d233083d5
source_requirements_approved_at: 2026-09-22T08:32:01Z
source_requirements_fingerprint: sha256:3eccb7865ebdfdd9119232e9546fd96682b11fc67798c9fd8372ebdb53770909
---

# Feature Design

## Architecture

A settings window, one view model, three read-only seams over things that already exist, and the first preference store the application has ever had.

```
App (Settings scene) ──▶ YGOFeatureSettings ──▶ YGOCore
   │                        SettingsViewModel       CatalogStatusReading
   │                        CatalogSyncActivity     CatalogRefreshing
   │                                                StorageInventorying
   │                                                PreferenceStoring
   └── binds the four protocols to:
         SQLiteCatalogStore  (sync_state + card count)
         CatalogEnvironment  (its existing start())
         FileStorageInventory (container directory)
         UserDefaultsPreferences
```

Nothing is fetched that was not already fetched, and nothing new is written to the database. Three of the four seams read state the application already keeps and never showed.

### What each seam is, and why it is a seam

```swift
/// What the stored catalog is. `R2.AC1`–`R2.AC3`.
public struct CatalogStatus: Hashable, Sendable {
    public let version: String
    public let upstreamUpdatedAt: Date?
    public let lastSyncAt: Date?
    public let cardCount: Int
}

public protocol CatalogStatusReading: Sendable {
    func catalogStatus() async throws -> CatalogStatus?
}

/// One synchronisation, whoever asks for it. `R2.AC4`.
public protocol CatalogRefreshing: Sendable {
    func refresh() async -> CatalogSyncOutcome
}

/// What the application occupies on disk. `R3.AC1`–`R3.AC3`.
public struct StorageFootprint: Hashable, Sendable {
    public let artworkFiles: Int
    public let artworkBytes: Int
    public let databaseBytes: Int
    /// Nil when no pre-migration backup is present, which is the ordinary case
    /// on a machine that has never migrated.
    public let backupBytes: Int?
}

public protocol StorageInventorying: Sendable {
    func footprint() async -> StorageFootprint
    func purgeArtwork() async throws
    func deleteBackup() async throws
}

/// What the application remembers. `R4`.
public struct Preferences: Hashable, Sendable, Codable {
    public var startingSection: AppSection
    public var cardLanguage: CardLanguage
    public var lastCheckedAt: Date?
}

public protocol PreferenceStoring: Sendable {
    func load() -> Preferences
    func save(_ preferences: Preferences)
}
```

`CatalogStatusReading` is a new protocol rather than a widening of `CatalogStore`, for the reason `catalog-filters` gave when it added `CardSearchCounting`: every offline stub in the suite conforms to `CatalogStore`, and adding a method to it breaks all of them for the sake of one read. `SQLiteCatalogStore` conforms to both.

`CatalogRefreshing` is what stops this feature from growing a second synchronisation. `CatalogEnvironment.start()` is the launch flow — synchronise, then fill artwork behind the interface — and the live binding is that method under a new name. The manual check in `R2.AC4` is not *a* synchronisation like the launch's; it is the same one. `card-catalog` learned this once already when the refresh and the startup path threatened to diverge.

### `sync_state` is read, never written

`SQLiteCatalogStore.apply` is the only writer of `sync_state`, and it writes `last_sync_at` only when a dataset is actually stored. A check that finds nothing new therefore leaves the row untouched — which is correct, and also means the row cannot answer *when did you last look*.

So the panel shows two different facts from two different places:

| Shown | Source | Changes when |
| --- | --- | --- |
| Catalogo aggiornato al | `sync_state.last_sync_at` | a dataset is stored |
| Ultimo controllo | `Preferences.lastCheckedAt` | any check finishes, including one that found nothing |

That is why `R2.AC4` can assert `sync_state` is byte-identical after an `alreadyCurrent` check: the check time is recorded beside the preferences, not in the catalog.

<!-- assumed: the check time lives in the preference store rather than a new sync_state column (source: a column means a migration, and a migration takes the 37 MB backup this very feature exists to reclaim) -->

### The footprint is read from the disk, not from the table

`artwork_cache` holds 14,730 rows with a `byte_size` each, and the disk holds 14,730 files. Either could answer `R3.AC1`, and they can disagree: `ArtworkStore.storedArtworkPath` already repairs a row whose file was removed from outside the application.

The panel reports the disk, because the disk is the thing the user is being asked about and the table is only the application's belief about it. `ArtworkStore` gains one method that walks the tree once:

```swift
public struct ArtworkFootprint: Hashable, Sendable {
    public let files: Int
    public let bytes: Int
}

public func storedFootprint() -> ArtworkFootprint
```

`storedByteSize()` stays — three certified tests call it — and becomes `storedFootprint().bytes`, so there is one walk and one definition of what counts.

`FileStorageInventory` lives in `YGOPersistence`, which already owns the container layout: `DatabaseBootstrapper.Configuration(containerURL:)` is what names `library.sqlite` and `library.pre-migration.sqlite`. The inventory takes that same configuration rather than re-deriving the names, so the panel cannot drift from the bootstrapper.

The reported database size is `library.sqlite` alone. The 3 MB write-ahead log is not folded into it: it is not a second copy of the data and it is reclaimed by SQLite, and a number that moves for reasons the user cannot act on is worse than a number that is slightly low.

### Confirmation is model state, not a view detail

`R3.AC4` and `R3.AC7` require a confirmation before anything is deleted, and this project has learned twice that the interface layer is where its real bugs live — the deck deletion bug was two SwiftUI alerts racing for one sequence.

So the confirmation is a value on the view model, and the view is a single alert bound to it:

```swift
public enum MaintenanceRequest: Hashable, Sendable {
    case purgeArtwork
    case deleteBackup
}

@MainActor @Observable public final class SettingsViewModel {
    public private(set) var pending: MaintenanceRequest?
    public func ask(_ request: MaintenanceRequest)   // arms it, deletes nothing
    public func confirm() async                      // performs exactly `pending`
    public func cancel()                             // clears it
}
```

One request can be armed at a time and the view draws one alert, so the racing sequence cannot be built. It also makes `R3.AC4` and `R3.AC7` provable without a window: `ask` followed by an inspection of the disk is the whole test.

### One synchronisation activity, shared by launch and settings

`LaunchState` already turns `CatalogSyncProgress` into an Italian line — *Controllo aggiornamenti…*, *Scarico il catalogo…*, *Salvo le carte: n di m*. `R2.AC7` needs that same line in the settings window and `R2.AC8` needs to know a run is in flight.

`CatalogSyncActivity` owns both:

```swift
@MainActor @Observable public final class CatalogSyncActivity {
    public private(set) var line: String?
    public private(set) var isRunning: Bool
    public nonisolated func observe(_ progress: CatalogSyncProgress)
    public func run(_ refresher: any CatalogRefreshing) async -> CatalogSyncOutcome?
    public static func line(for progress: CatalogSyncProgress) -> String?
}
```

`run` returns nil when a run is already in flight, which is `R2.AC8`. The stage-to-sentence mapping is a static function over a value, which is `R2.AC7` provable without a window. `LaunchState` creates the object, hands `observe` to `CatalogEnvironment.live(observeSync:)` and passes the object to the settings window, so both places report the same run rather than each keeping its own idea of one.

<!-- assumed: CatalogSyncActivity lives in YGOFeatureSettings and the app target uses it (source: the alternative homes are YGOComposition, which would drag GRDB into a feature module against the constitution's dependency direction, or YGOCore, which holds no observable UI state) -->

### `AppSection` moves into `YGOCore`

`R4.AC1` stores which section the window opens on, and the section is `RootView.Section` inside the app target, where no other module can see it. It moves to `YGOCore` as `AppSection`, and `RootView` keeps its display names and icons over that type.

It is a domain fact — the application has six sections — rather than a view detail, and moving it changes no certified module's contract.

### Loading order

`R4` is read synchronously before the window is built: `Preferences` decides the starting section and the browser's language, and both are needed at the first draw.

`R2` and `R3` are not. The settings window draws its panels with their figures absent and fills them in, because walking 14,730 files takes long enough to be seen. That is `NFR4`, and it is why `StorageInventorying.footprint()` is `async` and the view model exposes an optional footprint rather than a zeroed one.

## Options Considered

**Preferences in SQLite instead of `UserDefaults`.** Everything else this application stores is in `library.sqlite`, so a `preference` table would be the consistent choice. It was rejected twice over: a new table is a migration, and a migration makes the bootstrapper take the 37 MB pre-migration backup that this feature exists to let the user reclaim; and preferences must outlive the database, since a user who deletes `library.sqlite` to start the catalog again should not also lose which section the window opens on. `UserDefaults` is also what the platform's own settings windows read.

**Reporting the artwork footprint from `artwork_cache`.** One query instead of a walk over 14,730 files, and it would answer instantly. Rejected because the table is the application's belief and the panel is being asked about the disk; `R3.AC5` asserts that files are gone, and a row count cannot see that. The walk is done off the main actor instead, which is `NFR4`.

**Calling `synchronizer.synchronize()` directly from the settings panel.** One fewer protocol. Rejected: the launch calls `environment.start()`, which also fills artwork behind the interface. Two entry points that differ by a background task are exactly the divergence `card-catalog` already paid for once.

## Simplicity And Elegance Review

The feature adds one module, one view model and four small protocols, and writes no new persistence code except a `UserDefaults` read and write. Three of its four seams are bindings over methods that already existed and had no caller: `ArtworkStore.purge()`, `ArtworkStore.storedByteSize()` and `CatalogEnvironment.start()`.

The first draft had the settings view model own its own sync progress string and its own running flag, and `LaunchState` keep a second pair. That is two objects with one truth between them, and the second one is always the stale one. `CatalogSyncActivity` replaced both.

Coupling stays where the constitution puts it: `YGOFeatureSettings` imports `YGOCore` and nothing else, the implementations sit in the modules that already own the state they read, and the app target is the only place that knows which concrete type satisfies which protocol.

## Failure Modes And Tradeoffs

**A purge while the artwork prefetcher is running.** Both go through the `ArtworkStore` actor, so no file is half-written, but a prefetch in flight will immediately start re-caching what was just purged. This is not prevented. `R3.AC6` says artwork returns on demand, and the panel re-measures after the purge rather than trusting the number it reported a moment ago.

**Deleting the pre-migration backup removes a manual rollback.** The backup is the containment for a migration that throws; once the application is open, that migration committed and the file is dead weight. What it still offers is a hand rollback to the previous schema, which the user gives up. The confirmation says so rather than describing the file as junk.

**The database can be larger than its file.** The 3 MB write-ahead log is excluded by decision, so the reported figure is low by up to the log's size. Stated in the panel's wording rather than silently folded in.

**A preference for a section that no longer exists.** Decoding an unknown `AppSection` or `CardLanguage` yields the default instead of throwing, which is `R4.AC3`; the alternative is an application that will not launch because of a string in `UserDefaults`.

**Deck and collection data.** No maintenance action touches the database contents at all: purging removes files under `Artwork/`, deleting the backup removes one file beside the database. `R3.AC9` asserts this rather than assuming it, because it is the one thing here that cannot be fetched again.

**`R1` has no model.** The settings window's existence and its single-instance behaviour are the SwiftUI `Settings` scene's, not this feature's, and there is no view-level harness in this project. Its proof is a source-level assertion that the scene is declared and the app target builds; the single-window behaviour is the platform's guarantee, stated in `C2` and checked by hand. This limitation is recorded rather than dressed up as a test.

## Verification Plan

New test target `YGOFeatureSettingsTests`, plus additions to three existing targets. Every check runs against stubs or a temporary directory; none touches the user's installation.

| What | Where | How it is observed |
| --- | --- | --- |
| Catalog status is read and reported | `YGOFeatureSettingsTests` | a stub returning version `147.04`, upstream 16 Sep 2026, last sync 20 Sep 2026, 14,566 cards produces exactly those four values on the view model |
| A check that finds nothing stores nothing | `YGOPersistenceTests` | an `alreadyCurrent` refresh against a seeded temporary database leaves the `sync_state` row identical, `last_sync_at` included |
| A check that finds a newer version reports it | `YGOFeatureSettingsTests` | a refresher returning `.updated(cardCount:)` moves the panel's version to the new one and states the catalog changed |
| An unreachable upstream keeps the catalog | `YGOFeatureSettingsTests` | a refresher returning `.keptStoredCatalog(reason:)` leaves the reported version and card count untouched and reports the failure |
| Progress lines | `YGOFeatureSettingsTests` | `CatalogSyncActivity.line(for:)` over the four stages yields the four sentences, and `.finished` yields nil |
| No second concurrent check | `YGOFeatureSettingsTests` | a second `run` during a suspended refresher returns nil and the refresher records one call |
| Artwork footprint | `YGOImageStoreTests` | a store seeded with known files reports their exact count and byte total; an empty store reports zero and zero |
| Database and backup sizes | `YGOPersistenceTests` | against a temporary container the inventory reports the database file's size, the backup's size when present, and nil when absent |
| Asking does not delete | `YGOFeatureSettingsTests` | after `ask(.purgeArtwork)` and after `ask(.deleteBackup)`, the files are still there and `cancel()` leaves them there |
| Confirming purges | `YGOPersistenceTests` | after `confirm()` the artwork tree holds no files, `artwork_cache` holds no rows, and a fresh footprint reads zero |
| Confirming deletes only the backup | `YGOPersistenceTests` | the backup is gone; `library.sqlite`, `-wal` and `-shm` are present and unchanged |
| Artwork returns after a purge | `YGOImageStoreTests` | a store request after a purge fetches, writes the file and records the row again |
| User data survives maintenance | `YGOPersistenceTests` | deck rows, deck slots and collection entries are counted before and after both maintenance actions and compared |
| Preferences round-trip | `YGOPersistenceTests` | values written through `UserDefaultsPreferences` into an isolated suite read back identically |
| Unknown or absent preferences | `YGOPersistenceTests` | an empty suite and a suite holding an unknown section string both yield the defaults |
| The settings scene exists | `YGOFeatureSettingsTests` | the app source declares a `Settings` scene, asserted over the file, alongside the app target building |
| Keyboard and VoiceOver | `YGOFeatureSettingsTests` | every reported measurement carries an accessibility label naming what it measures and its unit |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `Settings` scene in the app target; source assertion plus the platform's single-window behaviour, with the limitation recorded above |
| `R2` | `CatalogStatusReading` bound to `SQLiteCatalogStore`, `CatalogRefreshing` bound to `CatalogEnvironment.start()`, `CatalogSyncActivity` for progress and the single-run guard |
| `R3` | `StorageInventorying` bound to `FileStorageInventory`, `ArtworkStore.storedFootprint()`/`purge()`, `MaintenanceRequest` confirmation state |
| `R4` | `Preferences`, `PreferenceStoring` bound to `UserDefaultsPreferences`, `AppSection` in `YGOCore`, defaults on unknown values |
| `NFR1` | Every panel but the update check reads local state only; `R2.AC6`'s `keptStoredCatalog` path is the check's degraded outcome |
| `NFR2` | Accessibility labels on each reported measurement, asserted in the feature's tests; controls are standard SwiftUI controls in a `Form` |
| `NFR3` | `MaintenanceRequest` arming, and the before/after count of decks, slots and collection entries |
| `NFR4` | `footprint()` is `async` and off the main actor; the view model exposes an optional footprint so the window draws before it is measured |
