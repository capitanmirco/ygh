---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T09:25:37Z
last_modified: 2026-09-21T09:39:30Z
approved_fingerprint: sha256:34473f8f05118c1c1b4a6472652e2fcd920ccc80ff5549c981f27df525f4e539
source_design_approved_at: 2026-09-21T09:24:43Z
source_design_fingerprint: sha256:9a3c82f124dd779e1424537fe92b865ea06ababdb8599b6fbc28f675e8325025
---

# Implementation Plan

Eight executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

Tasks 1 and 2 come first because the two write operations are what everything else stands on: the editor calls them, and undo is built from their inverses rather than from a third way of changing a deck.

The figures asserted below come from the user's own decks: LR-Chaos Turbo holds 40 main, 15 extra and 15 side; 28 slots hold more than one copy and 8 hold three; two cards already sit in two sections of the same deck.

- [x] 1. Set how many copies a section holds
  - Requirements: `R2.AC1`, `R2.AC2`, `R2.AC3`
  - Design: Architecture, Data Model
  - Notes: `DeckEditing` is a new port rather than two more methods on `DeckBuilding`, which every stub in `deck-builder`'s offline proofs conforms to. Setting zero is removal, so `R2.AC2` needs no code of its own. Writing stays permissive: four copies are held and the violation is reported, which is the contract `deck-builder` settled and this does not reopen.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckQuantityTests"]
      expect_output: "Test setsASectionToHoldExactlyThatManyCopies() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "DeckQuantityTests"]
      expect_output: "Test settingZeroRemovesTheCardFromThatSectionOnly() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "DeckQuantityTests"]
      expect_output: "Test anIllegalCountIsAppliedAndReported() passed"
      covers: ["R2.AC3"]

- [x] 2. Move copies between sections in one transaction
  - Requirements: `R3.AC1`, `R3.AC2`, `R3.AC3`, `R3.AC4`, `R3.AC5`, `R3.AC6`
  - Design: Architecture, Data Model, Failure Modes And Tradeoffs
  - Notes: One write block, not a remove followed by an add: between two calls the deck holds fewer cards than it should, and a failure in the second loses the copies. `DELETE ... WHERE quantity <= ?` runs before the `UPDATE`, because the schema refuses a zero quantity before any tidying could run — a trap this project has already paid for once. The `ON CONFLICT` clause is what makes moving into an occupied section a sum rather than a second row.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckMoveTests"]
      expect_output: "Test movingTwoCopiesLeavesTheTotalUnchanged() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "DeckMoveTests"]
      expect_output: "Test theMovedCopiesKeepTheirArtwork() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "DeckMoveTests"]
      expect_output: "Test movingIntoAnOccupiedSectionSumsIntoOneEntry() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "DeckMoveTests"]
      expect_output: "Test movingEveryCopyLeavesNoEntryBehind() passed"
      covers: ["R3.AC4"]
    - command: ["swift", "test", "--filter", "DeckMoveTests"]
      expect_output: "Test movingASectionOntoItselfChangesNothing() passed"
      covers: ["R3.AC5"]
    - command: ["swift", "test", "--filter", "DeckMoveTests"]
      expect_output: "Test askingToMoveMoreThanIsHeldMovesWhatIsThere() passed"
      covers: ["R3.AC6"]

- [x] 3. Offer cards to put in
  - Requirements: `R1.AC1`, `R1.AC2`, `R1.AC3`, `R1.AC4`
  - Design: Architecture, Simplicity And Elegance Review
  - Notes: The browser's behaviour applied to the editor's own list: load on opening, narrow on change, and narrow again by the deck's format so a GOAT deck is never offered a card it cannot hold. Placement by card type is the validator's own rule, so a card the editor puts somewhere is never then reported for being there.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckCandidateTests"]
      expect_output: "Test offersCardsWithoutBeingAskedOnOpening() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "DeckCandidateTests"]
      expect_output: "Test narrowsCandidatesOnEveryChangeWithoutSubmitting() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "DeckCandidateTests"]
      expect_output: "Test offersOnlyCardsLegalInTheDecksFormat() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "DeckCandidateTests"]
      expect_output: "Test placesACardInTheSectionItsTypeBelongsIn() passed"
      covers: ["R1.AC4"]

- [x] 4. Stop swallowing failures
  - Requirements: `R2.AC4`, `R2.AC5`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: The editor calls the repository with `try?` today, so an add that throws leaves the deck unchanged and says nothing — indistinguishable from one that succeeded and did nothing. Every operation becomes a caught failure the editor reports, and the deck is reloaded from storage afterwards, which is what makes the shown deck the stored deck by construction rather than by care.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckEditFailureTests"]
      expect_output: "Test aRefusedWriteIsReportedAndTheDeckIsUnchanged() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "DeckEditFailureTests"]
      expect_output: "Test theShownDeckIsTheStoredDeckAfterEveryEdit() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "DeckEditFailureTests"]
      expect_output: "Test legalityIsReportedForTheEditedDeck() passed"
      covers: ["R2.AC5"]

- [x] 5. Undo and redo an edit
  - Requirements: `R4.AC1`, `R4.AC2`, `R4.AC3`
  - Design: Architecture, Options Considered
  - Notes: `DeckEditHistory` over `DeckEdit.inverse`. Every edit's inverse is another edit of the same kind, so undo reuses the two write operations and there is no third way of changing a deck. Adding and removing are expressed as count changes, which is why `R4.AC3` is one implementation and not four.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckHistoryTests"]
      expect_output: "Test undoRestoresTheDeckSectionBySection() passed"
      covers: ["R4.AC1"]
    - command: ["swift", "test", "--filter", "DeckHistoryTests"]
      expect_output: "Test redoAppliesTheUndoneEditAgain() passed"
      covers: ["R4.AC2"]
    - command: ["swift", "test", "--filter", "DeckHistoryTests"]
      expect_output: "Test everyKindOfEditIsUndoneToItsPriorState() passed"
      covers: ["R4.AC3"]
    - command: ["swift", "test", "--filter", "DeckHistoryTests"]
      expect_output: "Test everyEditsInverseIsAnEditOfTheSameKind() passed"
      covers: ["R4.AC3"]

- [x] 6. Keep the history honest
  - Requirements: `R4.AC4`, `R4.AC5`, `R4.AC6`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: The three cases that are easy to leave out. A redo of something that no longer follows from the current deck would apply a change to a deck it was never about, so a new edit discards it. Opening another deck clears both stacks, because a ⌘Z meant for one deck reaching another is the worst thing this feature could do.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckHistoryBoundaryTests"]
      expect_output: "Test aNewEditDiscardsWhatWasUndone() passed"
      covers: ["R4.AC4"]
    - command: ["swift", "test", "--filter", "DeckHistoryBoundaryTests"]
      expect_output: "Test undoWithNothingToUndoChangesNothingAndSaysSo() passed"
      covers: ["R4.AC5"]
    - command: ["swift", "test", "--filter", "DeckHistoryBoundaryTests"]
      expect_output: "Test openingAnotherDeckDiscardsTheHistory() passed"
      covers: ["R4.AC6"]

- [x] 7. Drop a card where it should go, and reach it by keyboard
  - Requirements: `R5.AC1`, `R5.AC2`, `R5.AC3`, `R5.AC4`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: **What is proven here is the drop handler, not the gesture.** The handler is a function: given a dragged card and a destination section, it moves or adds, and it reports which section would receive a drop. What no proof here covers is SwiftUI delivering the drag to it — `C6` states that, and those three criteria are verified by hand in the running application. `R5.AC4` is fully proven, and it is what guarantees the gesture is never the only way to do something.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckDropTests"]
      expect_output: "Test droppingADeckCardOnAnotherSectionMovesIt() passed"
      covers: ["R5.AC1"]
    - command: ["swift", "test", "--filter", "DeckDropTests"]
      expect_output: "Test droppingACandidateOnASectionAddsItThere() passed"
      covers: ["R5.AC2"]
    - command: ["swift", "test", "--filter", "DeckDropTests"]
      expect_output: "Test theSectionUnderTheDragIsTheOneReported() passed"
      covers: ["R5.AC3"]
    - command: ["swift", "test", "--filter", "DeckDropTests"]
      expect_output: "Test everyMoveAndCountChangeIsReachableByKeyboard() passed"
      covers: ["R5.AC4"]

- [x] 8. Hold the budgets
  - Requirements: `NFR1`, `NFR2`, `NFR3`, `NFR4`, `NFR5`, `NFR6`
  - Design: Verification Plan, Requirement Coverage
  - Notes: Measured against a deck the size of the user's own — 40 main, 15 extra, 15 side — because an edit that feels instant on three cards is not evidence. Durability is proven by reading the stored deck at the moment the editor reports the edit done, rather than by trusting that the write happened first.
  - Verification:
    - command: ["swift", "build"]
      expect_output: "Build complete!"
      covers: ["NFR6"]
    - command: ["swift", "test", "--filter", "DeckEditBudgetTests"]
      expect_output: "Test anEditIsReflectedWithinOneHundredMilliseconds() passed"
      covers: ["NFR1"]
      timeout: 20m
    - command: ["swift", "test", "--filter", "DeckEditBudgetTests"]
      expect_output: "Test theEditIsStoredBeforeItIsReportedDone() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "DeckEditBudgetTests"]
      expect_output: "Test everyEditIsAppliedWithNoNetwork() passed"
      covers: ["NFR5"]
    - command: ["swift", "test", "--filter", "DeckEditBudgetTests"]
      expect_output: "Test aFailedEditNeverLeavesTheShownDeckAhead() passed"
      covers: ["NFR3"]
    - command: ["swift", "test", "--filter", "DeckEditAccessibilityTests"]
      expect_output: "Test eachEntryReadsAsASentenceNamingCardSectionAndCount() passed"
      covers: ["NFR4"]
