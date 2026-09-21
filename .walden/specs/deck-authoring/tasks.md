---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T18:55:04Z
last_modified: 2026-09-21T18:55:04Z
approved_fingerprint: sha256:b4c23aa5277abdd44725f6444685893c255f1f3a2af2af7d845acdc5fa7bf04f
source_design_approved_at: 2026-09-21T18:55:04Z
source_design_fingerprint: sha256:fa69d709d91d22a8e941b371884200a107346ca08e6d8dc3e48faa877bc03ea2
---

# Implementation Plan

Six executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

Task 1 comes first because the library view model is what every other task calls. Task 4 is the round trip, which is the only check here that tests this application against another program's expectations rather than against its own.

Measured before planning: `createDeck`, `rename`, `duplicate`, `changeFormat` and `delete` are implemented and certified, and `DeckExporter` has `ydkText`, `ydkeLink` and `write(_:to:)`. None has a caller. The user's decks hold 74 slots across 65 distinct cards.

- [x] 1. Start a deck from nothing
  - Requirements: `R1.AC1`, `R1.AC2`, `R1.AC3`, `R1.AC4`, `R1.AC5`
  - Design: Architecture, Data Model
  - Notes: `createDeck(name:format:)` is certified and uncalled. The view model gives it a caller, names an unnamed deck *Nuovo mazzo* rather than storing a blank one, and reloads the list from storage after every write — the shape `deck-editing` settled, so what is shown is what is stored by construction. Two decks may share a name, because a deck is its row.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckLibraryTests"]
      expect_output: "Test creatingADeckStoresItAndOpensIt() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "DeckLibraryTests"]
      expect_output: "Test aDeckIsJudgedByTheFormatItWasCreatedFor() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "DeckLibraryTests"]
      expect_output: "Test anUnnamedDeckIsNamedRatherThanStoredBlank() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "DeckLibraryTests"]
      expect_output: "Test twoDecksMayShareAName() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "DeckLibraryTests"]
      expect_output: "Test aRefusedCreationAddsNothingAndSaysSo() passed"
      covers: ["R1.AC5"]

- [x] 2. Write a deck out
  - Requirements: `R2.AC1`, `R2.AC2`, `R2.AC3`, `R2.AC5`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: Export reads each slot's artwork rather than its card, which is what makes a deck come out holding the printings that went in. Exporting a card's primary artwork instead would rewrite the user's choice silently, on every export. Legality is not judged: a ten-card deck exports, because carrying an unfinished deck between machines is the point.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckAuthoringExportTests"]
      expect_output: "Test theFileListsEachPasscodeOncePerCopyUnderItsSection() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "DeckAuthoringExportTests"]
      expect_output: "Test theArtworkTheDeckHoldsIsTheOneExported() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "DeckAuthoringExportTests"]
      expect_output: "Test anIllegalDeckExportsAnyway() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "DeckAuthoringExportTests"]
      expect_output: "Test anUnwritableDestinationIsReportedAndLeavesNoPartialFile() passed"
      covers: ["R2.AC5"]

- [x] 3. Hand a deck over as a link
  - Requirements: `R2.AC4`
  - Design: Architecture
  - Notes: `ydke://` is how a deck is pasted into a chat rather than attached to one. The link is only useful if another program can read it, so the check decodes it back rather than asserting its shape.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckAuthoringExportTests"]
      expect_output: "Test theLinkDecodesBackToTheSameCardsInTheSameSections() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "DeckAuthoringExportTests"]
      expect_output: "Test anEmptyDeckStillProducesAValidLink() passed"
      covers: ["R2.AC4"]

- [x] 4. Prove the round trip
  - Requirements: `R2.AC6`
  - Design: Architecture, Options Considered
  - Notes: The only check here that tests this application against another program's expectations rather than its own. A format is a contract, and the cheapest way to be wrong about it is to write a file only this application can read. It goes through the real exporter and the real importer, and compares sections, cards and counts — not names, because a `.ydk` carries none.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckRoundTripTests"]
      expect_output: "Test aDeckExportedAndImportedComesBackTheSame() passed"
      covers: ["R2.AC6"]
    - command: ["swift", "test", "--filter", "DeckRoundTripTests"]
      expect_output: "Test theRoundTripKeepsTheArtworksNotJustTheCards() passed"
      covers: ["R2.AC6"]
    - command: ["swift", "test", "--filter", "DeckRoundTripTests"]
      expect_output: "Test theNameComesFromTheFileBecauseTheFormatCarriesNone() passed"
      covers: ["R2.AC6"]

- [x] 5. Rename, duplicate, delete, re-format
  - Requirements: `R3.AC1`, `R3.AC2`, `R3.AC3`, `R3.AC4`
  - Design: Data Model, Failure Modes And Tradeoffs
  - Notes: `rename` and `duplicate` exist on the repository and in no protocol, so `DeckLibraryWriting` declares them — a new port rather than two more methods on `DeckBuilding`, for the reason that has held three times already. Duplication is the repository's transaction rather than a create-then-add replay: one write instead of N, a copy instead of a rebuild, and the artworks come with it. Deleting is irreversible and therefore confirmed.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckLibraryTests"]
      expect_output: "Test renamingStoresTheNewNameAndShowsIt() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "DeckLibraryTests"]
      expect_output: "Test aDuplicateHoldsTheSameCardsAndEditingItLeavesTheOriginal() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "DeckLibraryTests"]
      expect_output: "Test deletingAsksFirstAndOnlyThenDeletes() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "DeckLibraryTests"]
      expect_output: "Test changingFormatReJudgesTheDeck() passed"
      covers: ["R3.AC4"]

- [x] 6. Hold the budgets
  - Requirements: `NFR1`, `NFR2`, `NFR3`, `NFR4`, `NFR5`, `NFR6`
  - Design: Verification Plan, Requirement Coverage
  - Notes: Measured on a seventy-card deck, because duplicating one is the operation with the most rows to move and the one a user will notice. Durability is read back from storage at the moment the view model reports the write done, rather than trusted to have happened first.
  - Verification:
    - command: ["swift", "build"]
      expect_output: "Build complete!"
      covers: ["NFR6"]
    - command: ["swift", "test", "--filter", "DeckAuthoringBudgetTests"]
      expect_output: "Test creatingDuplicatingAndExportingStayUnderTwoHundredMilliseconds() passed"
      covers: ["NFR1"]
      timeout: 20m
    - command: ["swift", "test", "--filter", "DeckAuthoringBudgetTests"]
      expect_output: "Test aWriteIsStoredBeforeItIsReportedDone() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "DeckAuthoringBudgetTests"]
      expect_output: "Test theListShownIsTheListStoredEvenAfterAFailure() passed"
      covers: ["NFR3"]
    - command: ["swift", "test", "--filter", "DeckAuthoringBudgetTests"]
      expect_output: "Test everyOperationCompletesWithNoNetwork() passed"
      covers: ["NFR4"]
    - command: ["swift", "test", "--filter", "DeckAuthoringBudgetTests"]
      expect_output: "Test everyOperationReadsAsASentence() passed"
      covers: ["NFR5"]
