---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-22T13:32:53Z
last_modified: 2026-09-22T13:39:34Z
approved_fingerprint: sha256:32125824669c1fd004df1657a80da4f90b93afb03db615328f699b69a571755e
source_design_approved_at: 2026-09-22T13:32:13Z
source_design_fingerprint: sha256:3a67359e4fcd941c925b0a2728ac165362da6c7a9a00cce7cff6f9c0db2a69bb
---

# Implementation Plan

Five executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

The suites are `DeckListJudgementTests` and `DeckLegalityTests`; both names and both paths were checked unused before planning.

The read comes first, because every number this feature shows comes out of it and a wrong join is the one failure here that would look right.

Measured on the user's own database on 2026-09-22: 177 stored lists, Pot of Greed `limited` on TCG 2005-03-01 and `forbidden` on TCG 2010-03-01, `LR-Chaos Turbo` holding 0 forbidden cards under the first and 12 under the second, `Lockdown Burn` 0 and 4, and 203 catalog cards carrying no `konami_id`.

- [x] 1. Read a deck the way a list sees it
  - Requirements: `R2.AC1`, `R2.AC2`, `R2.AC3`, `R2.AC5`, `R3.AC3`, `NFR1`
  - Design: Architecture, Options Considered
  - Notes: One statement joining `deck_slot`, `card` and `banlist_entry` for the chosen revision, summing copies per card. `ListedDeckCard` carries the status, the copies held, the copies permitted and whether the card could be matched at all — a card with no `konami_id` is unmatched rather than unrestricted, because the second reads exactly like a correct answer. Copies are summed rather than counted as entries: three copies of a limited card are one card over its allowance, not three findings.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckListJudgementTests"]
      expect_output: "Test aDeckIsJudgedCardByCardAgainstTheChosenList() passed"
      covers: ["R2.AC1"]
      timeout: 30m
    - command: ["swift", "test", "--filter", "DeckListJudgementTests"]
      expect_output: "Test aCardTheListDoesNotNameIsUnrestricted() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "DeckListJudgementTests"]
      expect_output: "Test aCardWithNoKonamiIdentifierIsUnmatchedNotUnrestricted() passed"
      covers: ["R2.AC5"]
    - command: ["swift", "test", "--filter", "DeckListJudgementTests"]
      expect_output: "Test copiesAreSummedPerCardRatherThanCountedPerEntry() passed"
      covers: ["R2.AC3", "R3.AC3"]
    - command: ["swift", "test", "--filter", "DeckListJudgementTests"]
      expect_output: "Test judgingAWholeDeckIsOneReadOfTheList() passed"
      covers: ["NFR1"]

- [x] 2. Say which list a format is played under
  - Requirements: `R1.AC2`, `R1.AC3`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: `CardFormat.impliedList` maps the formats that have one: TCG, OCG and Master Duel to their newest stored list, GOAT to TCG March 2005 and Edison to TCG March 2010. Those two dates are a judgement about community formats rather than published data, which is why they are a default and not a rule. Duel Links, Speed Duel and Common Charity imply none, and saying nothing is the honest answer: judging them against the current TCG list would look authoritative and be wrong.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckLegalityTests"]
      expect_output: "Test theEraFormatsImplyTheListTheyAreNamedFor() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "DeckLegalityTests"]
      expect_output: "Test theCurrentFormatsImplyTheirNewestStoredList() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "DeckLegalityTests"]
      expect_output: "Test aFormatWithNoPublishedListImpliesNone() passed"
      covers: ["R1.AC3"]

- [x] 3. Turn what was read into a verdict
  - Requirements: `R2.AC4`, `R3.AC1`, `R3.AC2`, `R3.AC4`
  - Design: Architecture, Simplicity And Elegance Review
  - Notes: `DeckListVerdict` computes its totals from the array rather than storing four numbers that can disagree with it — the first draft held them and they were four ways to be out of step. Over the allowance is `held > permitted`, so one copy of a forbidden card is marked and one copy of a limited card is not. Every verdict names the revision it came from, which is what stops *legale* from being a claim about nothing in particular.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckLegalityTests"]
      expect_output: "Test theVerdictCountsForbiddenLimitedSemiLimitedAndUnmatched() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "DeckLegalityTests"]
      expect_output: "Test aDeckIsWithinTheListOnlyWhenNoCardIsOverItsAllowance() passed"
      covers: ["R3.AC2", "R2.AC4"]
    - command: ["swift", "test", "--filter", "DeckLegalityTests"]
      expect_output: "Test oneCopyOfAForbiddenCardIsOverButOneCopyOfALimitedIsNot() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "DeckLegalityTests"]
      expect_output: "Test everyVerdictNamesTheListAndTheDateItCameFrom() passed"
      covers: ["R3.AC4"]

- [x] 4. Judge the open deck, and let the user change the question
  - Requirements: `R1.AC1`, `R1.AC4`, `R1.AC5`, `R1.AC6`, `NFR2`, `NFR4`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: `DeckEditorViewModel` takes `judging` as an optional port, the shape `editing`, `history` and `labels` already use. Opening a deck judges it against the list its format implies; choosing another re-judges without reopening. Nothing here holds a writing port, so `R1.AC6` is structural rather than a promise: there is no path from this panel to a change of format. The user's own decks are the measure — `LR-Chaos Turbo` moves from 0 forbidden to 12 between the two era lists.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckLegalityTests"]
      expect_output: "Test openingAGoatDeckJudgesItAgainstTheMarch2005List() passed"
      covers: ["R1.AC1", "R1.AC2"]
    - command: ["swift", "test", "--filter", "DeckLegalityTests"]
      expect_output: "Test choosingAnotherListReJudgesWithoutReopeningTheDeck() passed"
      covers: ["R1.AC5"]
    - command: ["swift", "test", "--filter", "DeckLegalityTests"]
      expect_output: "Test everyStoredListIsOfferedGroupedByFormatNewestFirst() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "DeckLegalityTests"]
      expect_output: "Test judgingAgainstSixListsLeavesTheDeckExactlyAsItWas() passed"
      covers: ["R1.AC6"]
    - command: ["swift", "test", "--filter", "DeckLegalityTests"]
      expect_output: "Test judgingReadsOnlyStoredListsAndNeedsNoNetwork() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "DeckLegalityTests"]
      expect_output: "Test aDeckWhoseFormatHasNoListSaysSoInsteadOfBeingJudged() passed"
      covers: ["NFR4"]

- [x] 5. Put the verdict beside the deck
  - Requirements: `R4.AC1`, `R4.AC2`, `NFR3`
  - Design: Architecture, Options Considered
  - Notes: A third thing the side panel can show, after the card preview and the history, one at a time and each with its own shortcut. A `Menu` for the list, grouped by format and newest first. No sheet and no alert: the editor already holds a confirmation dialog and a restore alert, and every recorded failure in this project is presentations competing on one view. Each row announces the card, its status, the copies held and the copies permitted, which is the only part of `R4` a window is needed for; the rest is proven on the model.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckLegalityTests"]
      expect_output: "Test eachJudgedCardAnnouncesNameStatusHeldAndPermitted() passed"
      covers: ["R4.AC2", "NFR3"]
    - command: ["swift", "test", "--filter", "DeckLegalityTests"]
      expect_output: "Test thePanelOpensAndTheSelectionWalksTheJudgedCards() passed"
      covers: ["R4.AC1"]
    - command: ["sh", "-c", "grep -q 'DeckLegalityPanel' Packages/Features/YGOFeatureDeckBuilder/Sources/YGOFeatureDeckBuilder/DeckEditorView.swift && echo LEGALITY_PANEL_PRESENT"]
      expect_output: "LEGALITY_PANEL_PRESENT"
      covers: ["R4.AC1"]
    - command: ["sh", "-c", "grep -q 'judging:' App/YGODeckManagerApp.swift && echo JUDGING_PORT_BOUND"]
      expect_output: "JUDGING_PORT_BOUND"
      covers: ["R4.AC1"]
    - command: ["swift", "build"]
      expect_exit: 0
      covers: ["NFR3"]
      timeout: 30m
