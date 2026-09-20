---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-20T09:22:01Z
last_modified: 2026-09-20T10:19:24Z
approved_fingerprint: sha256:416915d8331fadda440d49d96f0c568714094cd6b5eb9207862d1c046f6e399c
source_design_approved_at: 2026-09-20T09:14:18Z
source_design_fingerprint: sha256:055d45a896ab7f72ab67ac84d8b8b2c2eae42984496ab790a25b6921fc686f9c
---

# Implementation Plan

Fifteen executable tasks. Every leaf carries its own new assertions.

Task 1 comes first because two later tasks cannot be proven without it: the recorded fixture holds no card whose `treated_as` value differs from its own name, and the catalog does not yet store that value at all. It also re-verifies `card-catalog`, whose evidence the `CatalogWriter` change invalidates.

The test-runner marker asserted throughout is `Test <name>() passed`, confirmed against this toolchain during the `card-catalog` work.

- [x] 1. Store card limit names and extend the recorded fixture
  - Requirements: `R3.AC3`
  - Design: Data Model, Verification Plan
  - Notes: Migration `v002` adds `card.limit_name`, and `CatalogWriter` fills it with the upstream `treated_as` value when it differs from the card's own name and with the card's name otherwise. `fixtures/catalog-en.json` and `catalog-it.json` are regenerated from the live dataset to include `Harpie Lady 1`, `2` and `3`, `A Legendary Ocean` and `Fusion Substitute`, so the shared-limit cases exist to be tested at all. The change to `CatalogWriter` is additive, so `card-catalog`'s own proofs must still pass unchanged.
  - Verification:
    - command: ["swift", "test", "--filter", "CardLimitNameTests"]
      expect_output: "Test storesTreatedAsNameWhenItDiffersFromTheCardName() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "CardLimitNameTests"]
      expect_output: "Test storesTheCardsOwnNameWhenNoTreatedAsApplies() passed"
    - command: ["swift", "test", "--filter", "CatalogWriterTests"]
      expect_output: "Test storesEveryArtworkIdentifierAgainstItsCard() passed"

- [x] 2. Model decks, sections and violations in YGOCore
  - Requirements: `R1.AC1`
  - Design: Architecture, Data Model
  - Notes: `Deck`, `DeckSection`, `DeckSlot`, `DeckViolation`, `DeckCardIndex` and the `DeckRepository` and `DeckValidating` protocols. A violation carries the card it names, the count held and the count permitted, because `NFR5` requires it to read as a sentence.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckModelTests"]
      expect_output: "Test newDeckHasChosenNameFormatAndThreeEmptySections() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "DeckModelTests"]
      expect_output: "Test violationDescribesCardHeldCountAndPermittedCount() passed"

- [x] 3. Add the deck schema and repository lifecycle
  - Requirements: `R1.AC2`, `R1.AC3`, `R1.AC4`, `R1.AC5`, `R1.AC6`, `R1.AC7`
  - Design: Data Model, Failure Modes And Tradeoffs
  - Notes: Migration `v002` also creates `deck`, `deck_slot`, `deck_version`, `folder`, `tag` and `deck_tag`. `SQLiteDeckRepository` adds and removes cards, renames, changes format, records modification times, duplicates independently, and refuses to delete without a confirmation.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckRepositoryTests"]
      expect_output: "Test addingCardRaisesItsCountInThatSectionOnly() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "DeckRepositoryTests"]
      expect_output: "Test removingLastCopyDropsTheEntryEntirely() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "DeckRepositoryTests"]
      expect_output: "Test changingFormatKeepsCardsAndChangesReportedViolations() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "DeckRepositoryTests"]
      expect_output: "Test editRecordsALaterModificationTime() passed"
      covers: ["R1.AC5"]
    - command: ["swift", "test", "--filter", "DeckRepositoryTests"]
      expect_output: "Test deletionWithoutConfirmationLeavesTheDeckRetrievable() passed"
      covers: ["R1.AC6"]
    - command: ["swift", "test", "--filter", "DeckRepositoryTests"]
      expect_output: "Test duplicateIsIndependentOfItsOriginal() passed"
      covers: ["R1.AC7"]

- [x] 4. Validate composition limits
  - Requirements: `R2.AC1`, `R2.AC2`, `R2.AC3`, `R2.AC4`, `R2.AC5`
  - Design: Architecture, Simplicity And Elegance Review
  - Notes: `DeckValidator` size and placement passes over a `DeckCardIndex`. Pure functions, no database.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckSizeRuleTests"]
      expect_output: "Test mainSectionIsLegalBetweenFortyAndSixtyCards() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "DeckSizeRuleTests"]
      expect_output: "Test extraSectionIsLegalUpToFifteenCards() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "DeckSizeRuleTests"]
      expect_output: "Test sideSectionIsLegalUpToFifteenCards() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "DeckPlacementRuleTests"]
      expect_output: "Test extraDeckCardOutsideExtraSectionIsReportedByName() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "DeckPlacementRuleTests"]
      expect_output: "Test mainDeckCardInExtraSectionIsReportedByName() passed"
      covers: ["R2.AC5"]

- [x] 5. Choose a card's section automatically
  - Requirements: `R2.AC6`
  - Design: Architecture
  - Notes: Adding a card with no section chosen places it by its frame. The rule lives beside the placement validation so the two cannot disagree.
  - Verification:
    - command: ["swift", "test", "--filter", "DefaultSectionTests"]
      expect_output: "Test placesExtraDeckFramesInTheExtraSectionAndTheRestInMain() passed"
      covers: ["R2.AC6"]

- [x] 6. Count copies across sections, artworks and shared limit names
  - Requirements: `R3.AC1`, `R3.AC2`, `R3.AC3`, `R3.AC5`
  - Design: Data Model, Simplicity And Elegance Review
  - Notes: Counting groups on `limit_name`, summing every artwork and all three sections. The absolute three-copy ceiling applies even where no ban list exists.
  - Verification:
    - command: ["swift", "test", "--filter", "CopyCountingTests"]
      expect_output: "Test countsCopiesAcrossMainExtraAndSideTogether() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "CopyCountingTests"]
      expect_output: "Test countsEveryArtworkOfACardAsTheSameCard() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "CopyCountingTests"]
      expect_output: "Test countsCardsSharingALimitNameTogether() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "CopyCountingTests"]
      expect_output: "Test reportsMoreThanThreeCopiesEvenWithoutABanList() passed"
      covers: ["R3.AC5"]

- [x] 7. Enforce the allowance a ban status permits
  - Requirements: `R3.AC4`
  - Design: Architecture
  - Notes: A violation names the card, the count held and the count permitted, so the interface has a sentence rather than a boolean.
  - Verification:
    - command: ["swift", "test", "--filter", "BanAllowanceTests"]
      expect_output: "Test reportsHeldCountAgainstPermittedCountForARestrictedCard() passed"
      covers: ["R3.AC4"]

- [x] 8. Judge a deck against its own format
  - Requirements: `R4.AC1`, `R4.AC2`, `R4.AC3`, `R4.AC4`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: The user's own deck files are the fixture: both are legal in GOAT and carry known violations in TCG, which is exactly the difference a fixed-format validator would get wrong.
  - Verification:
    - command: ["swift", "test", "--filter", "FormatLegalityTests"]
      expect_output: "Test judgesEachCardAgainstTheDecksOwnFormat() passed"
      covers: ["R4.AC1"]
    - command: ["swift", "test", "--filter", "FormatLegalityTests"]
      expect_output: "Test reportsCardOutsideTheFormatsPoolByName() passed"
      covers: ["R4.AC2"]
    - command: ["swift", "test", "--filter", "FormatLegalityTests"]
      expect_output: "Test reportsRealGoatDecksAsLegalInGoat() passed"
      covers: ["R4.AC3"]
    - command: ["swift", "test", "--filter", "FormatLegalityTests"]
      expect_output: "Test reportsEveryViolationRatherThanTheFirst() passed"
      covers: ["R4.AC4"]

- [x] 9. Judge formats whose restrictions the user maintains
  - Requirements: `R4.AC5`, `R4.AC6`
  - Design: Failure Modes And Tradeoffs
  - Notes: Edison and Master Duel have no upstream ban list, so their verdicts rest on user-recorded entries and must say so rather than implying authority.
  - Verification:
    - command: ["swift", "test", "--filter", "UserMaintainedFormatTests"]
      expect_output: "Test appliesUserRecordedRestrictionAndClearsWithIt() passed"
      covers: ["R4.AC5"]
    - command: ["swift", "test", "--filter", "UserMaintainedFormatTests"]
      expect_output: "Test marksAVerdictAsUserMaintainedForFormatsWithoutAnUpstreamList() passed"
      covers: ["R4.AC6"]

- [x] 10. Read and write `.ydk` files
  - Requirements: `R5.AC1`, `R6.AC1`
  - Design: Architecture, Simplicity And Elegance Review
  - Notes: `YDKFileReader` and `YDKFileWriter` in `YGODeckIO`, producing and consuming three arrays of passcodes. Tolerates comment lines, blank lines and both line endings. The user's own files are the fixtures.
  - Verification:
    - command: ["swift", "test", "--filter", "YDKFileTests"]
      expect_output: "Test readsRealDeckFileIntoItsThreeSections() passed"
      covers: ["R5.AC1"]
    - command: ["swift", "test", "--filter", "YDKFileTests"]
      expect_output: "Test writtenFileReadsBackAsTheSameDeck() passed"
      covers: ["R6.AC1"]
    - command: ["swift", "test", "--filter", "YDKFileTests"]
      expect_output: "Test toleratesCommentsBlankLinesAndCarriageReturns() passed"

- [x] 11. Encode and decode YDKe links
  - Requirements: `R5.AC6`, `R6.AC2`
  - Design: Verification Plan
  - Notes: `ydke://<main>!<extra>!<side>!`, each section standard base64 with padding over little-endian 32-bit passcodes. Verified against the published example, which decodes to two real cards.
  - Verification:
    - command: ["swift", "test", "--filter", "YDKeCodecTests"]
      expect_output: "Test decodesThePublishedExampleIntoItsPasscodes() passed"
      covers: ["R5.AC6"]
    - command: ["swift", "test", "--filter", "YDKeCodecTests"]
      expect_output: "Test encodedLinkDecodesBackToTheSamePasscodes() passed"
      covers: ["R6.AC2"]

- [x] 12. Import a deck from a file or a link
  - Requirements: `R5.AC2`, `R5.AC3`, `R5.AC4`, `R5.AC5`, `R5.AC7`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: One resolver serves both formats: it resolves artwork identifiers through the catalog, reports passcodes it cannot resolve without failing the import, names the deck after its file, and proposes the format in which the deck holds fewest violations. Malformed input is rejected before anything is written.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckImportTests"]
      expect_output: "Test resolvesAlternateArtworkPasscodeFromARealDeckFile() passed"
      covers: ["R5.AC2"]
    - command: ["swift", "test", "--filter", "DeckImportTests"]
      expect_output: "Test importsKnownCardsAndReportsTheUnresolvedPasscode() passed"
      covers: ["R5.AC3"]
    - command: ["swift", "test", "--filter", "DeckImportTests"]
      expect_output: "Test namesTheDeckAfterItsFile() passed"
      covers: ["R5.AC4"]
    - command: ["swift", "test", "--filter", "DeckImportTests"]
      expect_output: "Test proposesTheFormatWithFewestViolations() passed"
      covers: ["R5.AC5"]
    - command: ["swift", "test", "--filter", "DeckImportTests"]
      expect_output: "Test malformedInputStoresNoDeck() passed"
      covers: ["R5.AC7"]

- [x] 13. Export a deck without changing it
  - Requirements: `R6.AC3`, `R6.AC4`
  - Design: Data Model, Options Considered
  - Notes: Export reads `deck_slot.artwork_id`, so a deck round-tripped through the application keeps the printings the user holds. An illegal deck exports like any other.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckExportTests"]
      expect_output: "Test exportsTheArtworkTheDeckHoldsNotThePrimaryOne() passed"
      covers: ["R6.AC3"]
    - command: ["swift", "test", "--filter", "DeckExportTests"]
      expect_output: "Test exportsAndReimportsAnIllegalDeckIntact() passed"
      covers: ["R6.AC4"]

- [x] 14. Organise decks and keep their history
  - Requirements: `R7.AC1`, `R7.AC2`, `R7.AC3`, `R7.AC4`, `R8.AC1`, `R8.AC2`, `R8.AC3`, `R8.AC4`
  - Design: Data Model
  - Notes: Folders, tags and deck search, plus versions stored as JSON snapshots. Deleting a folder releases its decks; restoring a version stores the replaced state first.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckOrganisationTests"]
      expect_output: "Test deckMovedIntoAFolderListsUnderItAndNotAtTopLevel() passed"
      covers: ["R7.AC1"]
    - command: ["swift", "test", "--filter", "DeckOrganisationTests"]
      expect_output: "Test taggedDeckListsUnderEachOfItsTags() passed"
      covers: ["R7.AC2"]
    - command: ["swift", "test", "--filter", "DeckOrganisationTests"]
      expect_output: "Test deletingAFolderKeepsItsDecks() passed"
      covers: ["R7.AC3"]
    - command: ["swift", "test", "--filter", "DeckOrganisationTests"]
      expect_output: "Test searchingDecksByNameReturnsOnlyTheMatch() passed"
      covers: ["R7.AC4"]
    - command: ["swift", "test", "--filter", "DeckVersionTests"]
      expect_output: "Test savedVersionKeepsPreEditCounts() passed"
      covers: ["R8.AC1"]
    - command: ["swift", "test", "--filter", "DeckVersionTests"]
      expect_output: "Test restoringAVersionReturnsExactlyItsCounts() passed"
      covers: ["R8.AC2"]
    - command: ["swift", "test", "--filter", "DeckVersionTests"]
      expect_output: "Test restoringStoresTheReplacedStateAsAVersion() passed"
      covers: ["R8.AC3"]
    - command: ["swift", "test", "--filter", "DeckVersionTests"]
      expect_output: "Test versionsSurviveUnrelatedDeletionsAndAReopen() passed"
      covers: ["R8.AC4"]

- [x] 15. Build the deck editor and measure its budgets
  - Requirements: `NFR1`, `NFR2`, `NFR3`, `NFR4`, `NFR5`, `NFR6`
  - Design: Architecture, Requirement Coverage
  - Notes: The deck editor over `YGOCore` protocols: three sections, a card list, and a violation report where each entry reads as a sentence and everything is keyboard reachable. The budget checks measure re-evaluation latency on a sixty-card deck, confirm every rule resolves offline, and confirm an export and re-import is identical.
  - Verification:
    - command: ["swift", "build"]
      expect_output: "Build complete!"
      covers: ["NFR6"]
    - command: ["swift", "test", "--filter", "DeckEditorTests"]
      expect_output: "Test reEvaluationAfterAnEditStaysUnderFiftyMilliseconds() passed"
      covers: ["NFR1"]
      timeout: 20m
    - command: ["swift", "test", "--filter", "DeckEditorTests"]
      expect_output: "Test noEditImportOrRestoreLosesADeckWithoutConfirmation() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "DeckEditorTests"]
      expect_output: "Test everyDeckRuleResolvesWithNoNetworkAvailable() passed"
      covers: ["NFR3"]
    - command: ["swift", "test", "--filter", "DeckEditorTests"]
      expect_output: "Test exportedAndReimportedDeckIsIdenticalSectionBySection() passed"
      covers: ["NFR4"]
    - command: ["swift", "test", "--filter", "DeckEditorAccessibilityTests"]
      expect_output: "Test everyViolationReadsAsASentenceNamingCardAndRule() passed"
      covers: ["NFR5"]
    - command: ["swift", "test", "--filter", "DeckEditorAccessibilityTests"]
      expect_output: "Test reachesSectionsCardListAndReportByKeyboardAlone() passed"
      covers: ["NFR5"]
