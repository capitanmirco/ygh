---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-22T12:37:07Z
last_modified: 2026-09-22T12:44:53Z
approved_fingerprint: sha256:f8423b9b37268bbf0a9b1629ff21c86cb469438077d9a3a5470a24df7c6bf42d
source_design_approved_at: 2026-09-22T12:36:32Z
source_design_fingerprint: sha256:e31a525d4bf020a0b2143cd0ff647fe5fbdb0ec4266339e91ce7a1dfd89ce294
---

# Implementation Plan

Six executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

The suites are `DeckTagStorageTests` and `DeckLabelTests`; both names and both paths were checked as unused before planning, because a test file written over an existing one destroys another specification's proofs in silence.

Storage first: a deck cannot carry a label the reader does not return, and the normalisation rule is the only part of this feature that can be quietly wrong. The controls come last, because they are the part this project cannot prove.

Measured on 2026-09-22: `tag` and `deck_tag` hold 0 rows, `addTag` and `decks(withTag:)` are the whole of the tag store, `changeFormat` exists on the repository and on the library view model with no caller, and both of the user's decks are GOAT by the importer's guess.

- [x] 1. Let a deck carry its labels
  - Requirements: `R2.AC1`, `NFR4`
  - Design: Architecture
  - Notes: `Deck` gains `tags: [String]`, defaulted to empty so `deck-builder`'s certified tests keep compiling unchanged. `allDecks` reads the whole list's tags in one grouped query and hands each deck its own; `loadDeck` keeps its single-deck read. Reading tags per deck would double an N+1 that already exists for slots, which is what `NFR4` forbids.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckTagStorageTests"]
      expect_output: "Test aDeckReadFromStorageCarriesItsTags() passed"
      covers: ["R2.AC1"]
      timeout: 30m
    - command: ["swift", "test", "--filter", "DeckTagStorageTests"]
      expect_output: "Test theWholeListsTagsArriveWithoutAQueryPerDeck() passed"
      covers: ["NFR4"]
    - command: ["swift", "test", "--filter", "DeckTagStorageTests"]
      expect_output: "Test aDeckWithNoTagsCarriesAnEmptyList() passed"
      covers: ["R2.AC1"]

- [x] 2. One tag, however it is typed, and removable from one deck alone
  - Requirements: `R2.AC3`, `R2.AC4`, `R2.AC5`, `R2.AC6`
  - Design: Architecture, Options Considered, Failure Modes And Tradeoffs
  - Notes: `tag.name` is `UNIQUE` and SQLite compares case-sensitively, so the rule lives in the lookup — `WHERE name = ? COLLATE NOCASE` — rather than in a migration this feature is not allowed to write. The first spelling is kept: rewriting a label the user typed is the surprising option. A name that is empty once trimmed is refused before any write. `removeTag` deletes one `deck_tag` row, so the tag survives on every other deck and remains available to add again; that is why there is no confirmation for it.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckTagStorageTests"]
      expect_output: "Test spellingAndSpacesMakeOneTagKeepingTheFirstSpelling() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "DeckTagStorageTests"]
      expect_output: "Test anEmptyTagIsRefusedBeforeAnythingIsWritten() passed"
      covers: ["R2.AC5"]
    - command: ["swift", "test", "--filter", "DeckTagStorageTests"]
      expect_output: "Test removingATagFromOneDeckLeavesItOnTheOthers() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "DeckTagStorageTests"]
      expect_output: "Test everyTagInUseIsListedOnceInOrder() passed"
      covers: ["R2.AC6"]

- [x] 3. Name the four writes a feature module can call
  - Requirements: `R1.AC1`
  - Design: Architecture
  - Notes: `DeckLabelling` in `YGOCore`, with `SQLiteDeckRepository` conforming through the methods it now has. `changeFormat` joins the protocol rather than being written again: it is certified by `deck-builder` and only ever lacked a caller.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckTagStorageTests"]
      expect_output: "Test theRepositoryAnswersTheLabellingPort() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "DeckTagStorageTests"]
      expect_output: "Test aFormatChangeThroughThePortIsStored() passed"
      covers: ["R1.AC1"]

- [x] 4. Choose a format, and narrow the list by a label
  - Requirements: `R1.AC3`, `R1.AC4`, `R3.AC1`, `R3.AC2`, `R3.AC3`, `R3.AC4`
  - Design: Architecture, Simplicity And Elegance Review
  - Notes: `DeckLibraryViewModel` already holds `changeFormat` and already reloads; what it lacks is a chooser's worth of state and a filter. The filter is a computed predicate over `decks`, not a second array kept in step: this project has already been bitten by a stale copy of that list. An empty filtered result is a different thing from an empty library and has to read differently.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckLabelTests"]
      expect_output: "Test everyFormatIsOfferedWithTheDecksOwnMarked() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "DeckLabelTests"]
      expect_output: "Test aFailedFormatChangeKeepsTheFormatItHad() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "DeckLabelTests"]
      expect_output: "Test filteringByATagHoldsOnlyTheDecksCarryingIt() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "DeckLabelTests"]
      expect_output: "Test clearingTheFilterRestoresTheWholeListInOrder() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "DeckLabelTests"]
      expect_output: "Test theModelSaysWhichTagItIsFilteringBy() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "DeckLabelTests"]
      expect_output: "Test aFilterThatMatchesNothingIsNotAnEmptyLibrary() passed"
      covers: ["R3.AC4"]

- [x] 5. Edit both labels from the editor, and re-judge what changed
  - Requirements: `R1.AC1`, `R1.AC2`, `R2.AC1`, `R2.AC2`, `NFR1`, `NFR2`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: `DeckEditorViewModel` takes `labels` as an optional port, the same shape as `editing`, `catalogue` and `history`. After a change it reloads through the same `load(deckID:)` every edit uses, which is how the re-judgement is immediate without a second refresh path — and the deck list follows through the `onDeckChanged` hook the editor already calls. Changing a format can turn a legal deck illegal: that is the point of `R1.AC2`, and nothing is removed from the deck when it happens.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckLabelTests"]
      expect_output: "Test theEditorStoresANewFormatAndShowsIt() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "DeckLabelTests"]
      expect_output: "Test aFormatChangeReJudgesTheDeckWithoutReopeningIt() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "DeckLabelTests"]
      expect_output: "Test theEditorAddsAndRemovesATagAndTheDeckCarriesIt() passed"
      covers: ["R2.AC1", "R2.AC2"]
    - command: ["swift", "test", "--filter", "DeckLabelTests"]
      expect_output: "Test neitherLabelEverReachesTheDecksCards() passed"
      covers: ["NFR1"]
    - command: ["swift", "test", "--filter", "DeckLabelTests"]
      expect_output: "Test labellingNeedsNoNetworkAndNoCatalogueRead() passed"
      covers: ["NFR2"]

- [x] 6. Put the controls where the labels are read
  - Requirements: `NFR3`
  - Design: Architecture, Options Considered
  - Notes: A format `Picker` in the deck's context menu and in the editor's header, the deck's tags as removable chips with a field and a `Menu` of those in use, and a filter `Menu` in the sidebar. Menus and inline fields on purpose: the deck list already hosts a sheet, two alerts and an exporter, and every recorded failure in this project is presentations competing on one view. This is the task that cannot be proven automatically here — the proof is a source assertion that the controls are declared and the app building, with the limitation recorded rather than dressed up.
  - Verification:
    - command: ["sh", "-c", "grep -q 'formatPicker' App/YGODeckManagerApp.swift && echo FORMAT_PICKER_PRESENT"]
      expect_output: "FORMAT_PICKER_PRESENT"
      covers: ["NFR3"]
    - command: ["sh", "-c", "grep -q 'DeckLabelControls' Packages/Features/YGOFeatureDeckBuilder/Sources/YGOFeatureDeckBuilder/DeckEditorView.swift && echo LABEL_CONTROLS_PRESENT"]
      expect_output: "LABEL_CONTROLS_PRESENT"
      covers: ["NFR3"]
    - command: ["sh", "-c", "grep -q 'labels:' App/YGODeckManagerApp.swift && echo LABELLING_PORT_BOUND"]
      expect_output: "LABELLING_PORT_BOUND"
      covers: ["NFR3"]
    - command: ["swift", "build"]
      expect_exit: 0
      covers: ["NFR3"]
      timeout: 30m
