---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-22T11:40:19Z
last_modified: 2026-09-22T11:40:19Z
approved_fingerprint: sha256:764731cf04567981caa22950c40ba2145894aeecd15e2564fd968336aff9af6f
source_design_approved_at: 2026-09-22T10:38:14Z
source_design_fingerprint: sha256:429b63cb3ffdbe0f18f90b9f3e07e943e4abd8c8b9b2092ec647430260a14f4a
---

# Implementation Plan

Seven executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

The suite is `DeckVersionHistoryTests`. `DeckHistoryTests` was taken: it holds `deck-editing`'s undo and redo proofs, which are a different history — the one that lasts as long as the editor is open.

The two guards come first, before anything can call them. They are the only places where this feature can destroy something: one restores into the wrong deck, the other presents an unreadable version as an empty one. Everything after them is a screen over storage that was already certified.

Measured on 2026-09-22: `deck_version` holds 0 rows, `saveVersion`/`versions(of:)`/`restore(versionID:)` are called by tests alone, and `DeckVersion` is declared in `YGOPersistence` where no feature module can name it.

- [x] 1. Give the history a name a feature module can call
  - Requirements: `R2.AC3`
  - Design: Architecture
  - Notes: `DeckVersion` moves to `YGOCore` and gains `isReadable`, defaulting to true so `deck-builder`'s certified tests keep compiling and passing unchanged. `DeckHistorying` is one protocol rather than a reading and a writing half: the collection is split because a read-only collection screen exists, and no read-only history screen does. `SQLiteDeckRepository` conforms with the methods it already has.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckVersionTests"]
      expect_output: "Test savedVersionKeepsPreEditCounts() passed"
      covers: ["R2.AC3"]
      timeout: 30m
    - command: ["swift", "test", "--filter", "DeckVersionStorageTests"]
      expect_output: "Test theRepositoryAnswersTheHistoryPortForOneDeckOnly() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "DeckVersionTests"]
      expect_output: "Test versionsSurviveUnrelatedDeletionsAndAReopen() passed"
      covers: ["R2.AC3"]

- [x] 2. Tell an unreadable version apart from an empty one
  - Requirements: `R2.AC5`
  - Design: Architecture, Options Considered, Failure Modes And Tradeoffs
  - Notes: `versions(of:)` turns a snapshot it cannot decode into `slots: []`, which reads as a version of an empty deck — and `restore` throws on the same row, so the two disagree. It now reports `isReadable: false` with empty slots. Letting the read throw instead would hide every version of that deck behind one corrupt row, which is the opposite of what a history is for.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckVersionStorageTests"]
      expect_output: "Test anUndecodableSnapshotIsMarkedUnreadableRatherThanEmpty() passed"
      covers: ["R2.AC5"]
    - command: ["swift", "test", "--filter", "DeckVersionStorageTests"]
      expect_output: "Test oneCorruptVersionDoesNotHideTheOthers() passed"
      covers: ["R2.AC5"]

- [x] 3. Refuse a version that belongs to another deck
  - Requirements: `R3.AC6`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: `restore(versionID:)` reads the version's own `deck_id` and restores into it, so a foreign identifier rewrites *that* deck. Harmless while nothing calls it; one wrong identifier away once a panel lists versions. `restoreVersion(_:of:)` checks ownership, throws when it does not hold, and otherwise delegates, so there is one restore path rather than two. The old method stays for `deck-builder`'s certified proofs.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckVersionStorageTests"]
      expect_output: "Test restoringAVersionOfAnotherDeckIsRefused() passed"
      covers: ["R3.AC6"]
    - command: ["swift", "test", "--filter", "DeckVersionStorageTests"]
      expect_output: "Test aRefusedRestoreLeavesBothDecksUntouched() passed"
      covers: ["R3.AC6"]
    - command: ["swift", "test", "--filter", "DeckVersionStorageTests"]
      expect_output: "Test theGuardedRestoreAppliesAVersionOfItsOwnDeck() passed"
      covers: ["R3.AC6"]

- [x] 4. Mark where you are, and read what you marked
  - Requirements: `R1.AC1`, `R1.AC2`, `R1.AC3`, `R1.AC4`, `R2.AC1`, `R2.AC2`, `R2.AC4`, `NFR2`, `NFR4`
  - Design: Architecture, Simplicity And Elegance Review
  - Notes: `DeckEditorViewModel` takes `history` as an optional port, the way it already takes `editing` and `catalogue`: absent means the editor cannot offer a history rather than offering one that fails. Saving and listing report through the existing `lastFailure` rather than three new flags. A version's display name is its label or its formatted moment, which is how an unnamed version reads as when it was taken without a window being involved. `versions(of:)` returns oldest first, so the model reverses rather than changing a query `deck-builder` certified; ties within a second break on identifier. Listing is one call, with no per-row deck read.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test savingAVersionStoresItAndTheEditorSeesIt() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test anUnnamedVersionReadsAsTheMomentItWasTaken() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test anEditorWithNoDeckOffersNoHistory() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test aFailedSaveIsReportedAndLeavesTheDeckAlone() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test versionsAreListedNewestFirstWithTiesBrokenByIdentifier() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test eachVersionReportsItsNameItsMomentAndItsSize() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test aDeckThatWasNeverVersionedSaysSo() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test openingTheHistoryReadsStorageOnceAndNeedsNoNetwork() passed"
      covers: ["NFR2", "NFR4"]

- [x] 5. Go back, without going back by accident
  - Requirements: `R3.AC1`, `R3.AC2`, `R3.AC3`, `R3.AC4`, `R3.AC5`, `NFR1`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: `askRestore` arms, `cancelRestore` clears, and `confirmRestore(_:)` **takes** the identifier rather than reading the armed value — the alert's dismissal clears it before the action runs, which is the defect found in the collection screen, the settings window, deck deletion and deck renaming. After a restore the editor reloads through the same `load(deckID:)` every edit uses, so the card list and the legality report are the restored deck with no second refresh path. The pre-restore version is written by storage that already does it; this task asserts it rather than adding it.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test askingToRestoreChangesNothingUntilItIsConfirmed() passed"
      covers: ["R3.AC1", "NFR1"]
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test aConfirmedRestoreSetsEverySectionToTheVersionsCounts() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test theEditorShowsTheRestoredDeckWithoutBeingReopened() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test theReplacedStateBecomesAVersionThatRestoresBack() passed"
      covers: ["R3.AC4", "NFR1"]
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test aFailedRestoreLeavesTheDeckExactlyAsItWas() passed"
      covers: ["R3.AC5"]
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test aRestoreConfirmedBeforeTheDismissalClearedItStillHappens() passed"
      covers: ["R3.AC1", "NFR1"]

- [x] 6. Reach all of it from the keyboard
  - Requirements: `R4.AC1`, `R4.AC2`, `NFR3`
  - Design: Architecture, Requirement Coverage
  - Notes: The panel opens and closes on the model, so the shortcut in the window has something to call and the behaviour is provable without one. Moving through versions stops at the ends rather than wrapping, matching the card detail's focus stepping: a held key must not cycle silently. Every row reads as a sentence naming what the version is, when it was taken and how large it is, which is what a screen reader announces.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test theHistoryOpensAndClosesOnTheModel() passed"
      covers: ["R4.AC1"]
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test theSelectionWalksTheVersionsAndStopsAtTheEnds() passed"
      covers: ["R4.AC2"]
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test aVersionAnnouncesWhatItIsWhenItWasTakenAndHowLarge() passed"
      covers: ["NFR3"]
    - command: ["swift", "test", "--filter", "DeckVersionHistoryTests"]
      expect_output: "Test anUnreadableVersionCannotBeChosenForRestoring() passed"
      covers: ["R4.AC2"]

- [x] 7. Put the panel in the editor
  - Requirements: `R4.AC1`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: The history takes the preview's place beside the deck — one panel, two things it can show — with a keyboard shortcut to toggle it, and the restore confirmation on its own presentation level via `.background { Color.clear.alert(...) }`. Stacked on the same view as the deletion dialog, SwiftUI shows one and silently drops the rest, which is how a deck could be renamed and not deleted. The composition root binds the port to the repository it already builds. This is the task this project cannot prove automatically: there is no view-level harness, so the proof is a source assertion that the panel and the separate presentation level exist, plus the app building, with the limitation recorded rather than dressed up.
  - Verification:
    - command: ["sh", "-c", "grep -q 'DeckHistoryPanel' Packages/Features/YGOFeatureDeckBuilder/Sources/YGOFeatureDeckBuilder/DeckEditorView.swift && echo HISTORY_PANEL_PRESENT"]
      expect_output: "HISTORY_PANEL_PRESENT"
      covers: ["R4.AC1"]
    - command: ["sh", "-c", "grep -q 'history:' App/YGODeckManagerApp.swift && echo HISTORY_PORT_BOUND"]
      expect_output: "HISTORY_PORT_BOUND"
      covers: ["R4.AC1"]
    - command: ["swift", "build"]
      expect_exit: 0
      covers: ["R4.AC1"]
      timeout: 30m
