---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-22T08:32:01Z
last_modified: 2026-09-22T08:32:01Z
approved_fingerprint: sha256:3eccb7865ebdfdd9119232e9546fd96682b11fc67798c9fd8372ebdb53770909
---

# Requirements Document

## Introduction

Fourteen features are certified and the application does its job. What it does not yet have is the part of a macOS application that is not a feature: a place to see what it is holding, what it downloaded and when, and to say how it should open next time.

Facts measured against the user's own installation on 2026-09-22:

- **The application stores 499 MB** under `~/Library/Application Support/YGODeckManager`, and nothing in the interface says so.
- **Artwork is 417 MB across 14,730 files**, recorded row by row in `artwork_cache` with a `byte_size` each. `ArtworkStore` already offers `storedByteSize()` and `purge()`; no view calls either.
- **A 37 MB `library.pre-migration.sqlite` is sitting beside the 42 MB live database.** Hard Rule 4 makes a migration take that backup; nothing ever reclaims it, and the user cannot know it exists.
- **`sync_state` already holds everything an update panel needs** — catalog version `147.04`, upstream's own date `2026-09-16`, and `last_sync_at` `2026-09-20T10:49:19Z`. All three are stored and none is shown.
- **The only update check runs at launch.** `CatalogSynchronizer.synchronize()` is reachable from the composition root alone; there is no way to ask for one.
- **No preference is persisted at all**: `UserDefaults` and `@AppStorage` appear nowhere under `App/` or `Packages/`. The window opens on the catalog every time, in whichever language the browser defaults to.
- **The catalog holds 14,566 cards; the user has 2 decks and 0 collection entries.** Deck data is the irreplaceable part, and no maintenance offered here may touch it.

This feature is the settings window: what is stored, what can be reclaimed, and what should be remembered.

## Requirements

### R1 Reaching the settings

**User Story:** As the person using the application, I want its settings where every macOS application keeps them, so that I do not have to look for them.

#### Acceptance Criteria

1. `R1.AC1` The system SHALL offer a settings window reachable from the application menu.
   - Acceptance check: the application menu carries a settings item, and choosing it shows the window.
2. `R1.AC2` WHEN the settings window is already open and the user asks for it again, the system SHALL bring the open window forward.
   - Acceptance check: asking twice leaves one settings window on screen, not two.

### R2 What the stored catalog is, and asking for a newer one

**User Story:** As a duelist, I want to see how current my card data is and to refresh it when I choose, so that I am not waiting for the next launch to find out.

#### Acceptance Criteria

1. `R2.AC1` The system SHALL report the stored catalog version and the date upstream last changed it.
   - Acceptance check: against the stored row the panel reads version `147.04` and 16 September 2026; against a different stored row it reads that row's values.
2. `R2.AC2` The system SHALL report when the application last synchronised the catalog.
   - Acceptance check: against the stored row the panel reads 20 September 2026, 10:49.
3. `R2.AC3` The system SHALL report how many cards the stored catalog holds.
   - Acceptance check: the panel reads 14,566 against the user's database, and the seeded count against a test database.
4. `R2.AC4` WHEN the user asks for an update check, the system SHALL run the same synchronisation the launch runs.
   - Acceptance check: with upstream reporting the stored version, the check stores nothing and `sync_state` is byte-identical afterwards except for the recorded check time.
5. `R2.AC5` WHEN an update check finds a newer upstream version, the system SHALL report that the catalog changed and show the new version.
   - Acceptance check: upstream moved to a later version, the panel afterwards reads that version and states the catalog was updated.
6. `R2.AC6` IF an update check cannot reach upstream, THEN the system SHALL keep the stored catalog and report the failure.
   - Acceptance check: with the network refused, the card count and `sync_state` version are unchanged and the panel states the check failed.
7. `R2.AC7` WHILE an update check is running, the system SHALL report its progress.
   - Acceptance check: the panel shows the same stages the launch reports — checking, downloading, storing — rather than an idle window.
8. `R2.AC8` WHILE an update check is running, the system SHALL refuse to start a second one.
   - Acceptance check: asking again during a check does not start a second synchronisation.

### R3 What the application is storing, and reclaiming it

**User Story:** As the person using the application, I want to see what it has taken on disk and to reclaim what is only a cache, so that half a gigabyte is a choice rather than a surprise.

#### Acceptance Criteria

1. `R3.AC1` The system SHALL report how many artwork files are cached and their total size.
   - Acceptance check: the panel reads 14,730 files and 417 MB against the user's installation, and zero of both against an empty cache.
2. `R3.AC2` The system SHALL report the size of the card database.
   - Acceptance check: the reported size matches `library.sqlite` on disk, 42 MB here.
3. `R3.AC3` WHERE a pre-migration backup of the database exists, the system SHALL report it separately with its size.
   - Acceptance check: with `library.pre-migration.sqlite` present the panel lists it at 37 MB; with no backup file the panel does not list one.
4. `R3.AC4` WHEN the user asks to purge the artwork cache, the system SHALL ask for confirmation before deleting anything.
   - Acceptance check: declining the confirmation leaves the file count and the `artwork_cache` rows unchanged.
5. `R3.AC5` WHEN the user confirms the purge, the system SHALL delete the cached artwork and report nothing cached.
   - Acceptance check: after confirming, the artwork directory holds no files, `artwork_cache` holds no rows, and the panel reads zero files and zero bytes.
6. `R3.AC6` WHEN artwork is needed after a purge, the system SHALL fetch and cache it again.
   - Acceptance check: a card opened after a purge shows its image, and its `artwork_cache` row exists again.
7. `R3.AC7` WHEN the user asks to delete a pre-migration backup, the system SHALL ask for confirmation before deleting it.
   - Acceptance check: declining leaves the backup file on disk at its original size.
8. `R3.AC8` WHEN the user confirms deleting a pre-migration backup, the system SHALL delete that file and nothing else.
   - Acceptance check: after confirming, the backup is gone while `library.sqlite`, its `-wal` and its `-shm` are untouched.
9. `R3.AC9` The system SHALL leave deck and collection data unchanged through every maintenance action it offers.
   - Acceptance check: after a purge and a backup deletion, the deck rows, deck slots and collection entries are identical to before.

### R4 What the application remembers between launches

**User Story:** As the person using the application, I want it to open the way I left it, so that I am not re-choosing the same two things every morning.

#### Acceptance Criteria

1. `R4.AC1` The system SHALL open on the section the user last chose as its starting section.
   - Acceptance check: with the starting section set to decks, a fresh launch shows the deck library rather than the catalog.
2. `R4.AC2` The system SHALL open the catalog in the card language the user chose.
   - Acceptance check: with Italian chosen, a fresh launch reads card names in Italian without touching the language control.
3. `R4.AC3` IF a stored choice is missing or unreadable, THEN the system SHALL use its built-in default.
   - Acceptance check: with no stored preferences, or with a stored value outside the known set, the application launches on the catalog instead of failing.

## Non-Functional Requirements

- `NFR1` Offline-first. Every panel except the update check works with no network, and the check degrades rather than blocking — bridged by `R2.AC6`, `R3.AC1`, `R3.AC2`, `R3.AC3`.
- `NFR2` Accessibility. Every control is reachable and operable from the keyboard, and each reported measurement is announced with what it measures and its unit — bridged by `R1.AC1`, `R2.AC1`–`R2.AC3`, `R3.AC1`–`R3.AC3`.
- `NFR3` No silent data loss. Nothing here deletes without an explicit confirmation, and nothing here can reach user-authored data — bridged by `R3.AC4`, `R3.AC7`, `R3.AC9`.
- `NFR4` The window is usable before it is measured. Reading 14,730 files and 417 MB does not hold up the window's first draw; the figures arrive into a window that is already on screen — bridged by `R3.AC1`.

## Constraints And Dependencies

- `C1` Single local user, no telemetry, no outbound traffic other than the YGOPRODeck API and its image host (Hard Rules 2 and 6).
- `C2` macOS 27 on arm64, Swift 6.4, SwiftUI; the settings window is a SwiftUI `Settings` scene, which is what makes `R1.AC1` and `R1.AC2` the platform's behaviour rather than this feature's.
- `C3` Nothing persists a preference today: no `UserDefaults` or `@AppStorage` under `App/` or `Packages/`. `R4` introduces the first preference store.
- `C4` `sync_state` already holds the three values `R2.AC1` and `R2.AC2` report, so `R2` reads existing state rather than recording new state.
- `C5` Artwork sizes are recorded in `artwork_cache` and also observable on disk. The two can disagree if files are removed outside the application, and `R3.AC1` must state which it reports.
- `C6` `ArtworkStore.purge()` and `ArtworkStore.storedByteSize()` exist and are unused; `R3` binds them to a view rather than introducing deletion logic.

## Out Of Scope

- Menu-bar commands and keyboard shortcuts for moving between sections — the second half of the polish phase, and its own specification.
- Moving where data is stored. The `storage_location` table stays as it is, with no rows.
- Exporting or backing up decks and collection as a whole; decks already leave as `.ydk` and `ydke://`.
- Appearance and theme choices. Colour is `visual-language`'s contract.
- Scheduled or background updates beyond the existing check at launch.
- Interface language. Only the card language of `R4.AC2` is settable; the interface reads Italian by `italian-vocabulary`.
