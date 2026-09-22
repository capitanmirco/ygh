---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-22T14:53:25Z
last_modified: 2026-09-22T14:53:27Z
approved_fingerprint: sha256:207bd6094d26a00d5306d5140e0cc97108f3908eceb77a2f405d0753d1b7cb55
source_design_approved_at: 2026-09-22T14:45:19Z
source_design_fingerprint: sha256:5bcdf52a908fa6b030051370666cd9c58ff2b0fee4009098ecf163e82c652c9e
---

# Implementation Plan

Five executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

The suite is `AnalyticsControlsTests`; the name and the path were checked unused before planning.

Task 5's second proof asserts `start(on: deckID)` rather than `listing:`. The first draft asserted the second, which was already in the app target before this feature began and would therefore have passed whatever this task did.

The assumed format comes first. It is the only part of this feature that can be quietly wrong: a figure computed under the wrong opening-hand size is still a plausible-looking number, and nothing else on the screen would contradict it.

Measured on 2026-09-22: both of the user's decks are GOAT with a forty-card main deck, `OpeningHand` gives the player going first six cards in GOAT, OCG GOAT and Edison and five elsewhere, and the statistics screen reads whichever deck the window last selected.

- [x] 1. Read a deck as though it were played elsewhere
  - Requirements: `R2.AC1`, `R2.AC2`, `R2.AC3`, `R2.AC4`
  - Design: Architecture, Options Considered
  - Notes: The format reaches the arithmetic inside the deck value, through `OpeningHand`, so assuming another one is a copy with `format` substituted and no change to `YGOAnalytics` at all. `R2.AC4` is structural rather than promised: the model holds no writing port and the only mutated `Deck` is a local value. The screen names the format it assumed, and says when that is not the deck's own — a figure that does not state its assumption is a figure nobody can check.
  - Verification:
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test aDeckCanBeReadAsThoughItWerePlayedInAnotherFormat() passed"
      covers: ["R2.AC1"]
      timeout: 30m
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test theAssumedFormatChangesTheOpeningHandAndEveryFigureWithIt() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test theScreenNamesTheFormatItsFiguresAssume() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test readingADeckInFourFormatsNeverWritesTheDeck() passed"
      covers: ["R2.AC4"]

- [x] 2. Choose which deck the figures describe
  - Requirements: `R1.AC1`, `R1.AC2`, `R1.AC3`, `R1.AC4`, `R1.AC5`
  - Design: Architecture, Options Considered
  - Notes: The chooser reads the library through `DeckRepository`, the same port the deck list uses, and `choose(deckID:)` loads the deck and its index and hands the reading copy to the `load(deck:index:)` that `deck-analytics` is certified through. An empty library is a state, not an empty menu: a chooser with nothing in it beside empty figures leaves the reader looking for a deck they never made.
  - Verification:
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test everyStoredDeckIsOfferedInTheOrderTheLibraryUses() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test choosingAnotherDeckReportsThatDecksFigures() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test theFiguresNameTheDeckTheyDescribe() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test anEmptyLibrarySaysSoRatherThanOfferingAnEmptyChooser() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test theStatisticsStartOnTheDeckChosenElsewhere() passed"
      covers: ["R1.AC5"]

- [x] 3. Measure the deck against a published list
  - Requirements: `R3.AC1`, `R3.AC2`, `R3.AC3`, `R3.AC4`, `R3.AC5`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: The verdict is `deck-legality`'s, read here and shown as one line: how many cards are over, and which list said so. Resolving the list a format implies is now the same rule in two screens, so it moves to `BanlistRevision.implied(for:in:)` and the editor's method delegates to it — `deck-legality`'s proofs keep describing the behaviour they were written for. A format no published list covers reports no verdict, the same stance the editor takes, because a deck measured against a list that does not govern it looks authoritative and is wrong.
  - Verification:
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test theScreenReportsWhetherTheDeckIsWithinTheChosenList() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test theVerdictNamesTheListAndItsDate() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test changingTheListChangesTheVerdictForTheSameDeck() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test aFormatNoListCoversReportsNoVerdict() passed"
      covers: ["R3.AC4"]
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test measuringAgainstSeveralListsNeverWritesTheDeck() passed"
      covers: ["R3.AC5"]

- [x] 4. Make the dealt hand follow the choices
  - Requirements: `R4.AC1`, `R4.AC2`, `R4.AC3`, `NFR1`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: A hand left on screen after the format changed is six cards under a five-card rule, and it looks like evidence — so every choice clears it rather than recomputing it, including the play order, which already recomputed the figures and now clears the hand with them. The hand's size comes from the reading copy, so it is the size the assumed format and the play order imply rather than the stored deck's.
  - Verification:
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test theHandIsDealtFromTheDeckNowChosen() passed"
      covers: ["R4.AC1"]
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test everyChoiceClearsAHandDealtUnderThePreviousOne() passed"
      covers: ["R4.AC2"]
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test theHandHoldsWhatTheAssumedFormatAndPlayOrderImply() passed"
      covers: ["R4.AC3"]
    - command: ["swift", "test", "--filter", "AnalyticsControlsTests"]
      expect_output: "Test everyFigureStatesTheDeckTheFormatAndThePlayOrder() passed"
      covers: ["NFR1"]

- [x] 5. Put the three choosers on the screen
  - Requirements: `NFR4`, `NFR2`, `NFR3`
  - Design: Architecture, Simplicity And Elegance Review
  - Notes: A `Menu` for the deck, a `Picker` for the assumed format and a `Menu` for the list, above the figures. Nothing presents anything: the statistics screen holds no alert and no sheet, and this adds none. The composition root binds the three ports to objects it already builds. This is the part this project cannot prove automatically — the proof is a source assertion that the choosers are declared and the app building, and the limitation is recorded rather than dressed up.
  - Verification:
    - command: ["sh", "-c", "grep -q 'AnalyticsControls' Packages/Features/YGOFeatureAnalytics/Sources/YGOFeatureAnalytics/AnalyticsView.swift && echo ANALYTICS_CONTROLS_PRESENT"]
      expect_output: "ANALYTICS_CONTROLS_PRESENT"
      covers: ["NFR4"]
    - command: ["sh", "-c", "grep -q 'start(on: deckID)' App/YGODeckManagerApp.swift && echo ANALYTICS_PORTS_BOUND"]
      expect_output: "ANALYTICS_PORTS_BOUND"
      covers: ["NFR2", "NFR3"]
    - command: ["swift", "build"]
      expect_exit: 0
      covers: ["NFR4"]
      timeout: 30m
