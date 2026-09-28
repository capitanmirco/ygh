---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-27T12:23:54Z
last_modified: 2026-09-27T12:29:26Z
approved_fingerprint: sha256:a90d956f55843d917d42ead7ca3ec361d6ed17e29d9f6ccd5c511c72924a60c5
source_design_approved_at: 2026-09-27T12:21:34Z
source_design_fingerprint: sha256:9a0da7567fe59ee1d73b1908f03ffd1697d952120413711bee6c9cfabf3729bd
---

# Implementation Plan

Four executable tasks. The runner marker asserted throughout is `Test <name>() passed`, for test names that do not exist before the task that adds them, so no proof can pass on an unchanged suite.

The suite is `CollectionShortfallTests` in `Tests/YGOSyncTests/CollectionShortfallTests.swift`; the path is untracked and the suite name unused, both checked on 2026-09-27.

Measured on 2026-09-27: the user's three decks miss 69, 40 and 67 copies, the collection holds one lot, and the panel says nothing is missing for each of them.

Task 4's proofs assert strings that are absent from the source today — `startShortfall(on:`, `naming: environment.collection` and the chooser's accessibility label — so they cannot pass before the panel is wired.

- [x] 1. Let the panel choose its deck
  - Requirements: `R1.AC1`, `R1.AC2`, `R1.AC3`, `R1.AC4`, `R1.AC5`, `R1.AC6`
  - Design: Architecture, Options Considered, Failure Modes And Tradeoffs
  - Notes: The `CardNaming` port in `YGOCore` and its one-line conformance on `SQLiteCollectionRepository`; `library` and `naming` as optional dependencies of `CollectionViewModel`; `ShortfallReport` with its `.missing` case; `startShortfall(on:)`, `chooseShortfallDeck(_:)` and the generation counter. `shortfall` becomes computed from the report. The names are the collection's own — Italian where translated — so the R1.AC2 proof asserts the name `cardNames` gives, not the English one.
  - Verification:
    - command: ["swift", "test", "--filter", "CollectionShortfallTests"]
      expect_output: "Test everyStoredDeckIsOfferedInLibraryOrder() passed"
      covers: ["R1.AC1"]
      timeout: 30m
    - command: ["swift", "test", "--filter", "CollectionShortfallTests"]
      expect_output: "Test choosingADeckReportsWhatItNeedsUnderTheCollectionsNames() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "CollectionShortfallTests"]
      expect_output: "Test choosingAnotherDeckReplacesTheReport() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "CollectionShortfallTests"]
      expect_output: "Test theReportNamesTheDeckItDescribes() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "CollectionShortfallTests"]
      expect_output: "Test theReportStartsFromTheDeckSelectedInTheWindow() passed"
      covers: ["R1.AC5"]
    - command: ["swift", "test", "--filter", "CollectionShortfallTests"]
      expect_output: "Test choosingEveryDeckInTurnWritesNothing() passed"
      covers: ["R1.AC6"]
    - command: ["swift", "test", "--filter", "CollectionShortfallTests"]
      expect_output: "Test theCollectionAnswersCardNamesInItalianWhereTranslated() passed"

- [x] 2. Say only what is known
  - Requirements: `R2.AC1`, `R2.AC2`, `R2.AC3`, `R2.AC4`
  - Design: Architecture, Simplicity And Elegance Review, Failure Modes And Tradeoffs
  - Notes: The remaining `ShortfallReport` cases and their headlines. `computeShortfall(for:names:)` stops turning a failed read of owned copies into "owns nothing" and reports `.unavailable`; `isShortfallSatisfied` becomes "the report is `.satisfied`". The R2.AC3 proof uses a collection reader whose owned-copies read throws, declared in the suite. `collection-tracker`'s two accessibility proofs, which read `shortfall` and `isShortfallSatisfied`, are re-run here to show their success path is unchanged; they claim no new criterion.
  - Verification:
    - command: ["swift", "test", "--filter", "CollectionShortfallTests"]
      expect_output: "Test withNoDeckChosenThePanelAsksForOneAndClaimsNothing() passed"
      covers: ["R2.AC1"]
      timeout: 30m
    - command: ["swift", "test", "--filter", "CollectionShortfallTests"]
      expect_output: "Test anEmptyLibraryIsSaidRatherThanOfferedAsAnEmptyChooser() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "CollectionShortfallTests"]
      expect_output: "Test aFailedReadIsReportedAsUnavailableNotAsAListOrItsAbsence() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "CollectionShortfallTests"]
      expect_output: "Test nothingMissingIsSaidOnlyWhenTrueAndNamesTheDeck() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "CollectionAccessibilityTests"]
      expect_output: "Test everyShortfallEntryReadsAsASentence() passed"

- [x] 3. Follow the collection as it changes
  - Requirements: `R3.AC1`
  - Design: Architecture
  - Notes: `reload()`, which every write on the collection screen already ends with, recomputes the report for the chosen deck from the deck and names it already holds. No new refresh path.
  - Verification:
    - command: ["swift", "test", "--filter", "CollectionShortfallTests"]
      expect_output: "Test recordingACopyShrinksTheReportWithoutChoosingAgain() passed"
      covers: ["R3.AC1"]
      timeout: 30m

- [x] 4. Put the chooser and the report on the screen
  - Requirements: `NFR3`, `NFR4`
  - Design: Architecture, Simplicity And Elegance Review, Verification Plan
  - Notes: A `Menu` of decks (name · format) above a `switch` over `shortfallReport` in `CollectionView`, which now takes a `startingDeck` and calls `startShortfall(on:)` before `reload()` in its `.task`. The composition root passes `library: environment.deckRepository`, `naming: environment.collection` and `startingDeck: selectedDeck`. Nothing presents anything. This is the part this project cannot prove automatically: the proofs are source assertions and the app building, and the drawn panel is checked by hand in the running application.
  - Verification:
    - command: ["sh", "-c", "grep -q 'Mazzo confrontato con la collezione' Packages/Features/YGOFeatureCollection/Sources/YGOFeatureCollection/CollectionView.swift && grep -q 'startShortfall(on:' Packages/Features/YGOFeatureCollection/Sources/YGOFeatureCollection/CollectionView.swift && echo SHORTFALL_CHOOSER_PRESENT"]
      expect_output: "SHORTFALL_CHOOSER_PRESENT"
      covers: ["NFR4"]
    - command: ["sh", "-c", "grep -q 'naming: environment.collection' App/YGODeckManagerApp.swift && grep -q 'startingDeck: selectedDeck' App/YGODeckManagerApp.swift && echo SHORTFALL_PORTS_BOUND"]
      expect_output: "SHORTFALL_PORTS_BOUND"
      covers: ["NFR3"]
    - command: ["swift", "build"]
      expect_exit: 0
      timeout: 30m
