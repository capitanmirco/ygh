---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-22T10:34:40Z
last_modified: 2026-09-22T10:34:40Z
approved_fingerprint: sha256:b166c06692c45636804d4576b0314a0394f0d4c36d3e55cc6004a3676cae577e
---

# Requirements Document

## Introduction

`deck-builder` `R8` says what a version history is for: *as a duelist who tunes a list over weeks, I want to see and recover what it looked like before, so that an experiment is never a one-way door.* Its four acceptance criteria are certified and its storage works.

The door does not open. Nothing in the application lets anyone save a version or go back to one.

Facts measured on 2026-09-22:

- **`saveVersion`, `versions(of:)` and `restore(versionID:)` exist** in `SQLiteDeckOrganisation.swift`, as an extension on `SQLiteDeckRepository`. So `environment.deckRepository` — the object the editor already holds — carries all three.
- **Their only callers are tests.** `DeckVersionTests` and `DeckEditorTests` exercise them; no view, no view model and no composition code mentions them.
- **`deck_version` holds 0 rows** in the user's database, which is what that adds up to.
- **`DeckVersion` is declared in `YGOPersistence`**, not `YGOCore`, so no feature module can name the type. There is no port for any of this.
- **`restore` already stores the replaced state as a version first**, which is the third of `R8`'s criteria and is what makes a restore reversible.
- **The deck editor already owns the shape this needs**: a header with actions, an undo stack, and a confirmation held as model state after a dismissal cleared one too early.
- **`R8`'s durability criterion is already satisfied by the schema**: `deck_version.deck_id` cascades, so versions live and die with their deck.

This feature is the way in. It adds no storage and changes no stored shape: it is the screen and the affordances that let `R8`'s four criteria be exercised by the person they were written for.

What it must not do is turn a recovery into a loss. A restore replaces every card in a deck, and a deck is the one thing in this application that cannot be downloaded again.

## Requirements

### R1 Saving a version

**User Story:** As a duelist about to try something, I want to mark where I am, so that I can come back to it.

#### Acceptance Criteria

1. `R1.AC1` WHEN the user saves a version of the open deck, the system SHALL store it and report that it was stored.
   - Acceptance check: after saving, the deck's version list holds one more entry than before and the editor says so.
2. `R1.AC2` WHEN the user saves a version without naming it, the system SHALL store it under the moment it was taken.
   - Acceptance check: an unnamed version is listed with its date and time rather than with an empty label.
3. `R1.AC3` WHILE no deck is open, the system SHALL NOT offer to save a version.
   - Acceptance check: the save action is unavailable until a deck is loaded.
4. `R1.AC4` IF saving a version fails, THEN the system SHALL report the failure and leave the deck unchanged.
   - Acceptance check: with storage refusing, the editor reports it and the deck's cards are identical afterwards.

### R2 Reading what was

**User Story:** As a duelist who tunes a list over weeks, I want to see the states I marked, so that I can tell them apart before choosing one.

#### Acceptance Criteria

1. `R2.AC1` WHEN the user opens the history of the open deck, the system SHALL list that deck's versions, most recent first.
   - Acceptance check: three versions saved in order are listed newest to oldest.
2. `R2.AC2` The system SHALL report each version's name, when it was taken, and how many cards it holds.
   - Acceptance check: a version of a 43-card deck reads its label, its moment and 43.
3. `R2.AC3` The system SHALL list only the open deck's versions.
   - Acceptance check: with two decks each holding versions, the history shows one deck's and not the other's.
4. `R2.AC4` WHERE a deck has no versions, the system SHALL say so rather than showing an empty list.
   - Acceptance check: a deck never versioned reads a sentence explaining what a version is, not a blank panel.
5. `R2.AC5` IF a stored version cannot be read, THEN the system SHALL list it as unreadable rather than as empty.
   - Acceptance check: a version whose snapshot is corrupt is shown as unreadable and cannot be chosen for restoring, instead of reading zero cards.

### R3 Going back

**User Story:** As a duelist whose experiment failed, I want the list I had, so that weeks of tuning are not lost to an afternoon.

#### Acceptance Criteria

1. `R3.AC1` WHEN the user asks to restore a version, the system SHALL ask for confirmation before changing the deck.
   - Acceptance check: declining leaves every section's counts as they were.
2. `R3.AC2` WHEN the user confirms a restore, the system SHALL set the deck to that version's cards.
   - Acceptance check: after confirming, each section holds exactly the counts the version held.
3. `R3.AC3` WHEN a restore completes, the system SHALL show the restored deck without the user reopening it.
   - Acceptance check: the editor's card list and legality report read the restored deck immediately.
4. `R3.AC4` WHEN a restore completes, the system SHALL list the replaced state as a version of its own.
   - Acceptance check: after restoring, the history holds an entry for what was replaced, and restoring that returns the deck to it.
5. `R3.AC5` IF a restore fails, THEN the system SHALL report the failure and leave the deck as it was.
   - Acceptance check: with storage refusing part way, the deck's cards are identical to before the attempt.
6. `R3.AC6` The system SHALL NOT restore a version belonging to another deck.
   - Acceptance check: a version identifier from another deck is refused rather than applied.

### R4 Reaching it from the keyboard

**User Story:** As someone who builds decks without a mouse, I want the history reachable like everything else in the editor.

#### Acceptance Criteria

1. `R4.AC1` The system SHALL let the user open and close the history without a pointer.
   - Acceptance check: the history opens and closes from the keyboard alone.
2. `R4.AC2` WHILE the history is open, the system SHALL let the user move through its versions and choose one from the keyboard.
   - Acceptance check: the selection moves between versions and a restore can be asked for without a pointer.

## Non-Functional Requirements

- `NFR1` No silent loss. A restore replaces every card in a deck; it happens only after an explicit confirmation, and the replaced state is recoverable afterwards — bridged by `R3.AC1`, `R3.AC4`, `R3.AC5`.
- `NFR2` Offline. Saving, listing and restoring read and write the local database only, and work with no network — bridged by `R1.AC1`, `R2.AC1`, `R3.AC2`.
- `NFR3` Accessibility. Every version reads as a sentence naming what it is, when it was taken and how large it is, and every action is keyboard reachable — bridged by `R2.AC2`, `R4.AC1`, `R4.AC2`.
- `NFR4` A deck holds at most ninety distinct cards and a version is one JSON snapshot, so opening the history is a single read. Listing must not re-read the deck once per version — bridged by `R2.AC1`.

## Constraints And Dependencies

- `C1` The storage contract is `deck-builder` `R8`, already approved and certified. This feature adds no table, no column and no migration; it makes `R8`'s criteria reachable.
- `C2` `saveVersion`, `versions(of:)` and `restore(versionID:)` live in an extension on `SQLiteDeckRepository`, so the object the editor already holds carries them. What is missing is a port: `DeckVersion` is declared in `YGOPersistence` and no feature module can name it.
- `C3` `restore` already writes the replaced state as a version before replacing, which is why `R3.AC4` is a report about existing behaviour rather than new behaviour.
- `C4` Versions cascade with their deck (`deck_version.deck_id ON DELETE CASCADE`), which is `R8`'s durability criterion and is not re-specified here.
- `C5` macOS 27 on arm64, Swift 6.4, SwiftUI; the editor is an existing certified screen and this extends it rather than replacing it.
- `C6` A snapshot is JSON written once and read rarely. `versions(of:)` currently degrades an unreadable snapshot to zero cards, which `R2.AC5` changes: a version nobody can read must not be presented as an empty deck.

## Out Of Scope

- Folders, tags and searching decks by name — `deck-builder` `R7`, whose four criteria are storage-only for exactly the same reason. A separate decision, and a separate specification.
- Naming or renaming a version after it was taken.
- Deleting a version. Versions cost one JSON snapshot each and cascade with their deck; pruning them is a storage question nobody has yet.
- Comparing two versions, or showing what changed between them.
- Versions of anything other than a deck.
- Automatic versioning on a schedule or on every edit. The undo stack already covers the last edits; a version is something the user decides to mark.
