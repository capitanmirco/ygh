---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-20T10:39:23Z
last_modified: 2026-09-20T13:46:08Z
approved_fingerprint: sha256:64c99696310e3687e1fc55f760ddf2c540af1522dbaf7df4ececb4cf23dc46a5
source_design_approved_at: 2026-09-20T10:38:13Z
source_design_fingerprint: sha256:e61e3e7943ba8e1d773c0a91236e8ad8f42160ba421a603a544f2bf5d5a0631b
---

# Implementation Plan

Ten executable tasks. Every leaf carries its own new assertions, and the runner marker asserted throughout is `Test <name>() passed`.

Task 8 is the one to read carefully: it asserts that the shortfall counts cards rather than limit names, which is the difference between telling the user a deck is buildable and telling them the truth.

- [x] 1. Model collection entries and conditions in YGOCore
  - Requirements: `R2.AC1`
  - Design: Architecture, Data Model
  - Notes: `CollectionEntry`, `CardCondition`, `StorageLocation`, `CollectionTotals` and the `CollectionRecording` protocol. Condition is a closed enumeration over the five grades the trading-card market uses, with a stored form the database checks against.
  - Verification:
    - command: ["swift", "test", "--filter", "CollectionModelTests"]
      expect_output: "Test offersTheFiveMarketConditionGrades() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "CollectionModelTests"]
      expect_output: "Test conditionRoundTripsThroughItsStoredForm() passed"

- [x] 2. Add the collection schema and record copies
  - Requirements: `R1.AC1`, `R1.AC2`, `R1.AC3`, `R1.AC6`
  - Design: Data Model, Failure Modes And Tradeoffs
  - Notes: Migration `v004_collection` creates `storage_location` and `collection_entry` with its indexes. `SQLiteCollectionRepository` adds, removes and sets counts, and the foreign key refuses a printing the catalog does not hold.
  - Verification:
    - command: ["swift", "test", "--filter", "CollectionRecordingTests"]
      expect_output: "Test recordingAPrintingRaisesOnlyItsOwnCount() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "CollectionRecordingTests"]
      expect_output: "Test removingTheLastCopyDropsTheEntry() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "CollectionRecordingTests"]
      expect_output: "Test settingACountStoresItAndZeroRemovesTheEntry() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "CollectionRecordingTests"]
      expect_output: "Test refusesAPrintingTheCatalogDoesNotHold() passed"
      covers: ["R1.AC6"]

- [x] 3. Record cards the catalog lists no printing for
  - Requirements: `R1.AC4`, `R1.AC5`
  - Design: Data Model, Options Considered
  - Notes: 552 cards carry no printing and 30 of those are legal in TCG, so `print_id` is nullable and a copy may be recorded against its card alone. A card's total counts every printing plus any such entries.
  - Verification:
    - command: ["swift", "test", "--filter", "CollectionRecordingTests"]
      expect_output: "Test recordsACardThatHasNoPrintingInTheCatalog() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "CollectionRecordingTests"]
      expect_output: "Test countsACardsCopiesAcrossAllOfItsPrintings() passed"
      covers: ["R1.AC5"]

- [x] 4. Record what distinguishes one lot from another
  - Requirements: `R2.AC2`, `R2.AC3`, `R2.AC4`, `R2.AC5`, `R2.AC6`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: Price per copy, acquisition date, notes, and condition as part of a lot's identity. An absent price is stored as absent and contributes nothing to a total rather than zeroing it.
  - Verification:
    - command: ["swift", "test", "--filter", "CollectionLotTests"]
      expect_output: "Test storesWhatACopyCostAndWhenItWasAcquired() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "CollectionLotTests"]
      expect_output: "Test storesALotWithNeitherPriceNorDate() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "CollectionLotTests"]
      expect_output: "Test editingOneFieldLeavesTheOthersAlone() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "CollectionLotTests"]
      expect_output: "Test keepsDifferentConditionsAsSeparateLots() passed"
      covers: ["R2.AC5"]
    - command: ["swift", "test", "--filter", "CollectionLotTests"]
      expect_output: "Test totalSpendMultipliesPricePerCopyAndSkipsUnpricedLots() passed"
      covers: ["R2.AC6"]

- [x] 5. Keep track of where copies are
  - Requirements: `R3.AC1`, `R3.AC2`, `R3.AC3`, `R3.AC4`
  - Design: Data Model
  - Notes: Locations are a table and a nullable column. A deleted location releases its copies, which the schema guarantees rather than the code remembering to.
  - Verification:
    - command: ["swift", "test", "--filter", "StorageLocationTests"]
      expect_output: "Test createdLocationIsRetrievableUnderItsName() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "StorageLocationTests"]
      expect_output: "Test assignedCopyListsUnderItsLocationAndNotAmongUnfiled() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "StorageLocationTests"]
      expect_output: "Test deletingALocationKeepsItsCopiesAsUnfiled() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "StorageLocationTests"]
      expect_output: "Test reportsEachLocationHoldingACardWithItsCount() passed"
      covers: ["R3.AC4"]

- [x] 6. Total and search the collection
  - Requirements: `R4.AC1`, `R4.AC2`, `R4.AC5`
  - Design: Requirement Coverage
  - Notes: Distinct cards against total copies, search by name restricted to what is owned, and an empty collection distinguishable from a filter that matches nothing.
  - Verification:
    - command: ["swift", "test", "--filter", "CollectionBrowsingTests"]
      expect_output: "Test reportsDistinctCardsAndTotalCopies() passed"
      covers: ["R4.AC1"]
    - command: ["swift", "test", "--filter", "CollectionBrowsingTests"]
      expect_output: "Test searchReturnsOwnedCardsOnly() passed"
      covers: ["R4.AC2"]
    - command: ["swift", "test", "--filter", "CollectionBrowsingTests"]
      expect_output: "Test emptyCollectionIsDistinctFromAFilterMatchingNothing() passed"
      covers: ["R4.AC5"]

- [x] 7. Filter the collection and break it down by rarity
  - Requirements: `R4.AC3`, `R4.AC4`
  - Design: Data Model, Options Considered
  - Notes: Filters compose conjunctively over the entry joined to its printing, so rarity is read from the catalog rather than from a copy of it. The per-rarity figures must sum to the collection's total.
  - Verification:
    - command: ["swift", "test", "--filter", "CollectionFilterTests"]
      expect_output: "Test everyResultSatisfiesEveryAppliedFilter() passed"
      covers: ["R4.AC3"]
    - command: ["swift", "test", "--filter", "CollectionFilterTests"]
      expect_output: "Test perRarityCountsSumToTheCollectionTotal() passed"
      covers: ["R4.AC4"]

- [x] 8. Report what a deck still needs
  - Requirements: `R5.AC1`, `R5.AC2`, `R5.AC3`, `R5.AC4`, `R5.AC5`, `R5.AC6`
  - Design: Architecture, Options Considered
  - Notes: A pure `ShortfallCalculator` in `YGOCore` over a deck's per-card counts and the collection's per-card counts. It counts **cards, not limit names**: owning three `Harpie Lady 2` does not let anyone play a deck listing `Harpie Lady 1`, and reusing the deck validator's tally here would report a deck as buildable when it is not.
  - Verification:
    - command: ["swift", "test", "--filter", "ShortfallTests"]
      expect_output: "Test reportsHowManyMoreCopiesADeckNeeds() passed"
      covers: ["R5.AC1"]
    - command: ["swift", "test", "--filter", "ShortfallTests"]
      expect_output: "Test countsOwnedCopiesAcrossEveryPrinting() passed"
      covers: ["R5.AC2"]
    - command: ["swift", "test", "--filter", "ShortfallTests"]
      expect_output: "Test reportsNothingMissingForAFullyOwnedDeck() passed"
      covers: ["R5.AC3"]
    - command: ["swift", "test", "--filter", "ShortfallTests"]
      expect_output: "Test countsEverySectionOfTheDeck() passed"
      covers: ["R5.AC4"]
    - command: ["swift", "test", "--filter", "ShortfallTests"]
      expect_output: "Test reportsTheFullCountForACardOwnedNotAtAll() passed"
      covers: ["R5.AC5"]
    - command: ["swift", "test", "--filter", "ShortfallTests"]
      expect_output: "Test leavesTheDeckAndTheCollectionUnchanged() passed"
      covers: ["R5.AC6"]
    - command: ["swift", "test", "--filter", "ShortfallTests"]
      expect_output: "Test doesNotSatisfyOneCardWithAnotherSharingItsLimit() passed"

- [x] 9. Export and restore the collection
  - Requirements: `R6.AC1`, `R6.AC2`, `R6.AC3`, `R6.AC4`
  - Design: Simplicity And Elegance Review, Failure Modes And Tradeoffs
  - Notes: CSV, because a backup nobody can open is a backup nobody checks. Quoting is tested, including names holding commas and quotation marks. An import parses fully before writing anything, and a row naming an unknown printing is reported rather than failing the file.
  - Verification:
    - command: ["swift", "test", "--filter", "CollectionBackupTests"]
      expect_output: "Test exportsOneRowPerEntryWithEveryStoredField() passed"
      covers: ["R6.AC1"]
    - command: ["swift", "test", "--filter", "CollectionBackupTests"]
      expect_output: "Test exportClearImportRestoresTheSameCollection() passed"
      covers: ["R6.AC2"]
    - command: ["swift", "test", "--filter", "CollectionBackupTests"]
      expect_output: "Test malformedFileLeavesTheCollectionUntouched() passed"
      covers: ["R6.AC3"]
    - command: ["swift", "test", "--filter", "CollectionBackupTests"]
      expect_output: "Test importsKnownRowsAndNamesTheUnresolvedPrinting() passed"
      covers: ["R6.AC4"]
    - command: ["swift", "test", "--filter", "CollectionBackupTests"]
      expect_output: "Test quotesFieldsHoldingCommasAndQuotationMarks() passed"

- [x] 10. Build the collection view and measure its budgets
  - Requirements: `NFR1`, `NFR2`, `NFR3`, `NFR4`, `NFR5`, `NFR6`
  - Design: Architecture, Requirement Coverage
  - Notes: The collection view over `YGOCore` protocols: the owned list, its filters, and a shortfall report whose entries read as sentences and which is reachable by keyboard alone. The budget checks measure recording latency against a ten-thousand-copy collection and confirm every behaviour answers offline.
  - Verification:
    - command: ["swift", "build"]
      expect_output: "Build complete!"
      covers: ["NFR6"]
    - command: ["swift", "test", "--filter", "CollectionBudgetTests"]
      expect_output: "Test recordingACopyUpdatesTotalsUnderFiftyMilliseconds() passed"
      covers: ["NFR1"]
      timeout: 20m
    - command: ["swift", "test", "--filter", "CollectionBudgetTests"]
      expect_output: "Test noRemovalOrImportLosesCopiesWithoutConfirmation() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "CollectionBudgetTests"]
      expect_output: "Test everyCollectionBehaviourAnswersOffline() passed"
      covers: ["NFR3"]
    - command: ["swift", "test", "--filter", "CollectionBudgetTests"]
      expect_output: "Test shortfallAndDeckValidationAgreeOnCopyCounts() passed"
      covers: ["NFR4"]
    - command: ["swift", "test", "--filter", "CollectionAccessibilityTests"]
      expect_output: "Test everyShortfallEntryReadsAsASentence() passed"
      covers: ["NFR5"]
    - command: ["swift", "test", "--filter", "CollectionAccessibilityTests"]
      expect_output: "Test reachesListFiltersAndShortfallByKeyboardAlone() passed"
      covers: ["NFR5"]
