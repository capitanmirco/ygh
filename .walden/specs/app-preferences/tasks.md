---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-22T08:39:26Z
last_modified: 2026-09-22T08:55:28Z
approved_fingerprint: sha256:f3432f251cc7993fb759b64ec7adc8c83117c8b8f485acbf5ce33e72fe83d62a
source_design_approved_at: 2026-09-22T08:36:57Z
source_design_fingerprint: sha256:72eacacec6f33002655e59c374ac37be15ba7bdcef2e944b95895f3d233083d5
---

# Implementation Plan

Eight executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

The order is bottom-up on purpose: the four seams are provable against a temporary directory and a stub before any window exists, and the window is the only part this project cannot put under an automatic proof. Task 8 is where that limitation is paid, and it is deliberately the last thing, so that everything provable is already proven when it arrives.

The figures asserted below were measured against the user's own installation on 2026-09-22: 499 MB in the container, artwork 417 MB across 14,730 files, `library.sqlite` 42 MB, `library.pre-migration.sqlite` 37 MB, `sync_state` holding version `147.04`, upstream `2026-09-16` and `last_sync_at` `2026-09-20T10:49:19Z`, 14,566 cards, 2 decks, 0 collection entries. The tests use their own fixtures rather than those numbers; the numbers are what the panels must be able to read.

- [x] 1. Give the application a vocabulary for what it remembers
  - Requirements: `R4.AC3`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: `AppSection` moves out of `RootView` into `YGOCore`, because `R4.AC1` has to store a section and no module outside the app target can see one today. `Preferences` is a `Codable` value holding the starting section, the card language and the last check time. Decoding an unknown section or language yields the default rather than throwing: a string in `UserDefaults` must not be able to stop the application from launching.
  - Verification:
    - command: ["swift", "test", "--filter", "PreferencesTests"]
      expect_output: "Test defaultPreferencesOpenTheCatalogInItalian() passed"
      covers: ["R4.AC3"]
      timeout: 30m
    - command: ["swift", "test", "--filter", "PreferencesTests"]
      expect_output: "Test anUnknownSectionDecodesToTheDefault() passed"
      covers: ["R4.AC3"]
    - command: ["swift", "test", "--filter", "PreferencesTests"]
      expect_output: "Test anUnknownLanguageDecodesToTheDefault() passed"
      covers: ["R4.AC3"]
    - command: ["swift", "test", "--filter", "PreferencesTests"]
      expect_output: "Test everyStoredFieldSurvivesACodableRoundTrip() passed"
      covers: ["R4.AC3"]

- [x] 2. Persist preferences outside the database
  - Requirements: `R4.AC1`, `R4.AC2`, `R4.AC3`
  - Design: Architecture, Options Considered
  - Notes: `UserDefaultsPreferences` in `YGOPersistence`, over an injectable suite so the tests never touch the real domain. It is the first preference storage this project has had. Not a SQLite table: a table is a migration, a migration makes the bootstrapper take the 37 MB backup this feature exists to reclaim, and a user who deletes `library.sqlite` to rebuild the catalog should not also lose which section the window opens on. A relaunch is modelled as a second store instance reading the same suite, which is exactly what `R4.AC1` and `R4.AC2` mean by a fresh launch.
  - Verification:
    - command: ["swift", "test", "--filter", "UserDefaultsPreferencesTests"]
      expect_output: "Test aChosenStartingSectionIsReadBackByALaterInstance() passed"
      covers: ["R4.AC1"]
    - command: ["swift", "test", "--filter", "UserDefaultsPreferencesTests"]
      expect_output: "Test aChosenCardLanguageIsReadBackByALaterInstance() passed"
      covers: ["R4.AC2"]
    - command: ["swift", "test", "--filter", "UserDefaultsPreferencesTests"]
      expect_output: "Test anEmptySuiteYieldsTheDefaults() passed"
      covers: ["R4.AC3"]
    - command: ["swift", "test", "--filter", "UserDefaultsPreferencesTests"]
      expect_output: "Test aSuiteHoldingAnUnknownSectionYieldsTheDefaults() passed"
      covers: ["R4.AC3"]

- [x] 3. Read what the stored catalog is
  - Requirements: `R2.AC1`, `R2.AC2`, `R2.AC3`
  - Design: Architecture
  - Notes: `CatalogStatusReading` is a new protocol rather than three methods added to `CatalogStore`, for the reason `catalog-filters` gave when it added `CardSearchCounting`: every offline stub in the suite conforms to `CatalogStore` and widening it breaks all of them for one read. `SQLiteCatalogStore` conforms to both and answers from `sync_state` plus a count of `card`. All three values are already stored and none has ever been shown.
  - Verification:
    - command: ["swift", "test", "--filter", "CatalogStatusTests"]
      expect_output: "Test theStatusCarriesTheStoredVersionAndUpstreamDate() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "CatalogStatusTests"]
      expect_output: "Test theStatusCarriesWhenTheCatalogWasLastStored() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "CatalogStatusTests"]
      expect_output: "Test theStatusCarriesHowManyCardsAreStored() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "CatalogStatusTests"]
      expect_output: "Test aDatabaseThatHasNeverSynchronisedHasNoStatus() passed"
      covers: ["R2.AC1"]

- [x] 4. Measure and reclaim the artwork on disk
  - Requirements: `R3.AC1`, `R3.AC6`
  - Design: Architecture, Options Considered
  - Notes: `ArtworkStore` gains `storedFootprint()`, one walk of the tree yielding both the file count and the byte total, and `storedByteSize()` becomes `storedFootprint().bytes` so there is one definition of what counts. The disk is read rather than `artwork_cache`, because the table is the application's belief and the panel is being asked about the disk — and `R3.AC5` asserts the files are gone, which a row count cannot see. `purge()` already exists and already forgets the rows; what is new here is that something asks it.
  - Verification:
    - command: ["swift", "test", "--filter", "ArtworkFootprintTests"]
      expect_output: "Test theFootprintCountsEveryStoredFileAndItsBytes() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "ArtworkFootprintTests"]
      expect_output: "Test anEmptyStoreReportsNoFilesAndNoBytes() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "ArtworkFootprintTests"]
      expect_output: "Test theByteTotalAgreesWithTheOlderByteSizeReading() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "ArtworkFootprintTests"]
      expect_output: "Test artworkStoredAfterAPurgeIsOnDiskAndRecordedAgain() passed"
      covers: ["R3.AC6"]

- [x] 5. Inventory the container, and reclaim from it without touching user data
  - Requirements: `R3.AC2`, `R3.AC3`, `R3.AC5`, `R3.AC8`, `R3.AC9`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: `FileStorageInventory` takes the same `DatabaseBootstrapper.Configuration(containerURL:)` the bootstrapper uses, so the panel cannot drift from the two file names it already owns. The database figure is `library.sqlite` alone: the write-ahead log is not a second copy of the data and moves for reasons the user cannot act on. Deleting the backup removes one file and nothing else — the sidecars belong to the live database and removing one of them is how SQLite gets told to replay a log that belongs to a discarded file. `R3.AC9` is the invariant that matters most here: the deck rows, the deck slots and the collection entries are counted before and after both maintenance actions and compared, because that is the one thing in this application that cannot be fetched again.
  - Verification:
    - command: ["swift", "test", "--filter", "StorageInventoryTests"]
      expect_output: "Test theInventoryReportsTheDatabaseFilesSize() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "StorageInventoryTests"]
      expect_output: "Test aPresentBackupIsReportedSeparatelyWithItsSize() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "StorageInventoryTests"]
      expect_output: "Test aContainerWithNoBackupReportsNone() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "StorageInventoryTests"]
      expect_output: "Test purgingLeavesNoArtworkFileAndNoArtworkRow() passed"
      covers: ["R3.AC5"]
    - command: ["swift", "test", "--filter", "StorageInventoryTests"]
      expect_output: "Test deletingTheBackupLeavesTheDatabaseAndItsSidecarsIntact() passed"
      covers: ["R3.AC8"]
    - command: ["swift", "test", "--filter", "StorageInventoryTests"]
      expect_output: "Test decksSlotsAndCollectionAreIdenticalAfterBothMaintenanceActions() passed"
      covers: ["R3.AC9"]

- [x] 6. One synchronisation activity for the launch and the panel
  - Requirements: `R2.AC7`, `R2.AC8`
  - Design: Architecture, Simplicity And Elegance Review
  - Notes: Creates the `YGOFeatureSettings` module and its test target in `Package.swift`. `CatalogSyncActivity` holds the progress line and whether a run is in flight; `LaunchState` hands its `observe` to `CatalogEnvironment.live(observeSync:)` and hands the object to the settings window, so the two places report one run rather than each keeping its own idea of one. The stage-to-sentence mapping is a static function over a value, which is how `R2.AC7` is proven without a window. `run` returning nil while a run is in flight is `R2.AC8`; the second caller must not reach the refresher at all, which the stub asserts by counting its calls.
  - Verification:
    - command: ["swift", "test", "--filter", "CatalogSyncActivityTests"]
      expect_output: "Test everyStageYieldsTheLineTheLaunchAlreadyShows() passed"
      covers: ["R2.AC7"]
    - command: ["swift", "test", "--filter", "CatalogSyncActivityTests"]
      expect_output: "Test theStoringStageCountsWhatItHasStored() passed"
      covers: ["R2.AC7"]
    - command: ["swift", "test", "--filter", "CatalogSyncActivityTests"]
      expect_output: "Test theFinishedStageClearsTheLine() passed"
      covers: ["R2.AC7"]
    - command: ["swift", "test", "--filter", "CatalogSyncActivityTests"]
      expect_output: "Test aSecondRunDuringARunReachesNoRefresher() passed"
      covers: ["R2.AC8"]

- [x] 7. The panel itself
  - Requirements: `R2.AC4`, `R2.AC5`, `R2.AC6`, `R3.AC4`, `R3.AC7`, `NFR1`, `NFR2`, `NFR3`, `NFR4`
  - Design: Architecture, Failure Modes And Tradeoffs, Verification Plan
  - Notes: `SettingsViewModel` over the four protocols and `CatalogSyncActivity`. The manual check is `CatalogRefreshing`, bound in the app to `CatalogEnvironment.start()`, so it is the launch's synchronisation rather than a second one that can diverge — `card-catalog` paid for that lesson once. The confirmation is state, not a view detail: `ask` arms exactly one request and deletes nothing, `confirm` performs the armed one, `cancel` clears it. One alert, one armed request, so the two-alert sequence that produced the deck deletion bug cannot be built here. The footprint is optional until measured, which is how the window draws before 14,730 files have been walked.
  - Verification:
    - command: ["swift", "test", "--filter", "SettingsViewModelTests"]
      expect_output: "Test aCheckThatFindsNothingNewStoresNothing() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "SettingsViewModelTests"]
      expect_output: "Test theCheckGoesThroughTheSameRefresherTheLaunchUses() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "SettingsViewModelTests"]
      expect_output: "Test aNewerUpstreamVersionIsReportedAsAnUpdate() passed"
      covers: ["R2.AC5"]
    - command: ["swift", "test", "--filter", "SettingsViewModelTests"]
      expect_output: "Test anUnreachableUpstreamKeepsTheStoredCatalogAndSaysSo() passed"
      covers: ["R2.AC6", "NFR1"]
    - command: ["swift", "test", "--filter", "SettingsViewModelTests"]
      expect_output: "Test askingToPurgeDeletesNothingUntilItIsConfirmed() passed"
      covers: ["R3.AC4", "NFR3"]
    - command: ["swift", "test", "--filter", "SettingsViewModelTests"]
      expect_output: "Test askingToDeleteTheBackupDeletesNothingUntilItIsConfirmed() passed"
      covers: ["R3.AC7", "NFR3"]
    - command: ["swift", "test", "--filter", "SettingsViewModelTests"]
      expect_output: "Test cancellingAnArmedRequestLeavesEverythingOnDisk() passed"
      covers: ["R3.AC4", "R3.AC7"]
    - command: ["swift", "test", "--filter", "SettingsViewModelTests"]
      expect_output: "Test onlyOneRequestCanBeArmedAtATime() passed"
      covers: ["NFR3"]
    - command: ["swift", "test", "--filter", "SettingsViewModelTests"]
      expect_output: "Test thePanelHasNoFootprintUntilItHasBeenMeasured() passed"
      covers: ["NFR4"]
    - command: ["swift", "test", "--filter", "SettingsViewModelTests"]
      expect_output: "Test everyReportedMeasurementNamesWhatItMeasuresAndItsUnit() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "SettingsViewModelTests"]
      expect_output: "Test theStoredCatalogIsReportedAsFourReadableFacts() passed"
      covers: ["R2.AC1", "R2.AC2", "R2.AC3", "R3.AC1"]

- [x] 8. Put the window in the application
  - Requirements: `R1.AC1`, `R1.AC2`, `R4.AC1`, `R4.AC2`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: A SwiftUI `Settings` scene beside the existing `WindowGroup`, the four protocols bound to `SQLiteCatalogStore`, `CatalogEnvironment`, `FileStorageInventory` and `UserDefaultsPreferences`, and `RootView` taking its first section and the browser its language from the loaded preferences. This is the task the project cannot prove automatically: there is no view-level harness here, and `R1.AC1` and `R1.AC2` are the platform's behaviour rather than this feature's. The proof is therefore what it honestly is — the scene is declared, the bindings are present, the app target builds — and the single-window behaviour is observed by hand. Recorded as a limitation in the design rather than dressed up as a test.
  - Verification:
    - command: ["sh", "-c", "grep -q 'Settings {' App/YGODeckManagerApp.swift && echo SETTINGS_SCENE_DECLARED"]
      expect_output: "SETTINGS_SCENE_DECLARED"
      covers: ["R1.AC1"]
    - command: ["sh", "-c", "grep -q 'UserDefaultsPreferences' App/YGODeckManagerApp.swift && echo PREFERENCES_BOUND"]
      expect_output: "PREFERENCES_BOUND"
      covers: ["R4.AC1", "R4.AC2"]
    - command: ["sh", "-c", "grep -q 'FileStorageInventory' App/YGODeckManagerApp.swift && echo INVENTORY_BOUND"]
      expect_output: "INVENTORY_BOUND"
      covers: ["R1.AC1"]
    - command: ["swift", "build"]
      expect_exit: 0
      covers: ["R1.AC1", "R1.AC2"]
      timeout: 30m
