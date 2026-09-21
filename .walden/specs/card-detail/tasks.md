---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T08:49:38Z
last_modified: 2026-09-21T09:10:18Z
approved_fingerprint: sha256:0a2fecc5310e1bc30a904c6954e63440d9c762fc155478df3becb80cf8ff0b82
source_design_approved_at: 2026-09-21T08:49:38Z
source_design_fingerprint: sha256:4fe9d2911cc48cfcee5108c7c697defceb79339fec11c533ee941a85db16d9ee
---

# Implementation Plan

Nine executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

Task 1 comes first because `R1.AC4` cannot be shown without a count, and the count is where this feature can go silently wrong: the counting statement is the search statement with two clauses removed, and the arguments of those clauses must go with them.

The figures asserted below were measured against the user's own database on 2026-09-21: 14,566 cards, 2,981 untranslated, 85 with no release date, 552 with no printing, 289 with no price, 124 with several artworks, an empty collection, and two decks both holding Upstart Goblin.

- [x] 1. Count what a query matches
  - Requirements: `R1.AC4`
  - Design: Architecture, Data Model
  - Notes: `CardSearchCounting` is a new port rather than a method on `CardSearching`, which every offline stub conforms to. The counting statement reuses the builder's joins and conditions, emits `SELECT COUNT(*)`, and drops the ordering and the paging **with their bound arguments**. The recorded lesson on `card-catalog` was exactly this: arguments appended in construction order bind to the wrong placeholders and return a plausible wrong number rather than an error, so the proof asserts membership-derived counts, not just non-zero ones.
  - Verification:
    - command: ["swift", "test", "--filter", "CardSearchCountingTests"]
      expect_output: "Test countsTheWholeCatalogWhenNothingNarrowsIt() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "CardSearchCountingTests"]
      expect_output: "Test theCountMatchesWhatAnUnpagedSearchWouldReturn() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "CardSearchCountingTests"]
      expect_output: "Test countingIsUnaffectedByLimitOffsetAndOrdering() passed"
      covers: ["R1.AC4"]

- [x] 2. Open on the catalog and narrow while typing
  - Requirements: `R1.AC1`, `R1.AC2`, `R1.AC3`, `R1.AC6`, `R1.AC7`
  - Design: Architecture
  - Notes: The browser loads on appearing instead of waiting for a submit, and each change to the query text starts a load that supersedes the one before it. A result arriving for text the user has moved past is discarded rather than shown, which a stub repository can prove by answering out of order. No debounce: the query costs 3.9 ms and a timer would tax every keystroke.
  - Verification:
    - command: ["swift", "test", "--filter", "BrowserNarrowingTests"]
      expect_output: "Test opensShowingCardsWithoutBeingAsked() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "BrowserNarrowingTests"]
      expect_output: "Test clearingTheQueryReturnsToTheWholeCatalog() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "BrowserNarrowingTests"]
      expect_output: "Test narrowsOnEveryChangeWithoutSubmitting() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "BrowserNarrowingTests"]
      expect_output: "Test aSupersededResultNeverReachesTheGrid() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "BrowserNarrowingTests"]
      expect_output: "Test filtersAloneNarrowWithNoQueryText() passed"
      covers: ["R1.AC6"]
    - command: ["swift", "test", "--filter", "BrowserNarrowingTests"]
      expect_output: "Test noMatchesIsASettledAnswerNotAnEmptyGrid() passed"
      covers: ["R1.AC7"]

- [x] 3. Show the next batch
  - Requirements: `R1.AC4`, `R1.AC5`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: 200 at a time by decision, so the grid never holds 14,566 live tiles reaching for 417 MB of thumbnails. A batch is tagged with the query that asked for it, so an advance answered after the query changed is discarded instead of appended to a different result.
  - Verification:
    - command: ["swift", "test", "--filter", "BrowserPagingTests"]
      expect_output: "Test reportsHowManyMatchAndHowManyAreShown() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "BrowserPagingTests"]
      expect_output: "Test advancingHoldsFourHundredInOrderWithNoRepeats() passed"
      covers: ["R1.AC5"]
    - command: ["swift", "test", "--filter", "BrowserPagingTests"]
      expect_output: "Test advancingPastTheEndIsRefusedNotShownEmpty() passed"
      covers: ["R1.AC5"]
    - command: ["swift", "test", "--filter", "BrowserPagingTests"]
      expect_output: "Test aBatchForAnAbandonedQueryIsDiscarded() passed"
      covers: ["R1.AC5"]

- [x] 4. Read where a card was printed and when it came out
  - Requirements: `R2.AC4`, `R2.AC5`, `R3.AC1`, `R3.AC2`
  - Design: Data Model
  - Notes: Printings and release dates are read together because both belong to the catalog and neither is on the `Card` type. Widening `Card` for two fields one panel reads would touch a type five certified specifications construct. Asserted against real shapes: 78 printings for Blue-Eyes White Dragon, a card among the 552 with none, and a card among the 85 with neither date.
  - Verification:
    - command: ["swift", "test", "--filter", "CardPrintingReadTests"]
      expect_output: "Test readsSeventyEightPrintingsWithSetCodeAndRarity() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "CardPrintingReadTests"]
      expect_output: "Test aCardWithNoPrintingReportsNoneRecorded() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "CardPrintingReadTests"]
      expect_output: "Test reportsBothReleaseDatesEachNamedByItsRegion() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "CardPrintingReadTests"]
      expect_output: "Test aCardWithNeitherDateReportsAnUnknownRelease() passed"
      covers: ["R2.AC5"]

- [x] 5. Read the copies owned and the decks using them
  - Requirements: `R4.AC1`, `R4.AC2`, `R4.AC3`, `R4.AC4`
  - Design: Data Model
  - Notes: `CollectionWriting.entries(forCard:)` returns a location identifier and not its name, so holdings are read here rather than reused. A copy whose location was deleted reports as unfiled, which is what the schema's `ON DELETE SET NULL` already means. Deck usage is reported per section, because a card in the main deck and the side deck is two facts, not one total. Proven against seeded data, since the live collection holds nothing.
  - Verification:
    - command: ["swift", "test", "--filter", "CardHoldingsReadTests"]
      expect_output: "Test reportsCopiesInEachLocationWithItsName() passed"
      covers: ["R4.AC1"]
    - command: ["swift", "test", "--filter", "CardHoldingsReadTests"]
      expect_output: "Test anUnfiledCopyIsReportedNotDropped() passed"
      covers: ["R4.AC1"]
    - command: ["swift", "test", "--filter", "CardHoldingsReadTests"]
      expect_output: "Test anEmptyCollectionReportsNoCopyHeld() passed"
      covers: ["R4.AC2"]
    - command: ["swift", "test", "--filter", "CardHoldingsReadTests"]
      expect_output: "Test reportsBothDecksUsingTheCardWithTheirCounts() passed"
      covers: ["R4.AC3"]
    - command: ["swift", "test", "--filter", "CardHoldingsReadTests"]
      expect_output: "Test mainAndSideAreReportedSeparately() passed"
      covers: ["R4.AC4"]

- [x] 6. Assemble a card's detail
  - Requirements: `R2.AC2`, `R2.AC3`, `R3.AC3`, `R3.AC4`, `R3.AC5`, `R3.AC6`
  - Design: Architecture, Data Model, Simplicity And Elegance Review
  - Notes: `CardDetailLoader` in the new `YGOFeatureCardDetail` fans out to the ports and returns one `CardDetail`. Every section is `Section<T>` with an explicit absent case, so a view cannot render "nothing recorded" as an empty table by forgetting a branch. An unpriced source is unpriced, never zero, and the figures carry the time they were observed rather than the time the panel opened.
  - Verification:
    - command: ["swift", "test", "--filter", "CardDetailAssemblyTests"]
      expect_output: "Test readsNameTypeAndEffectInTheChosenLanguage() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "CardDetailAssemblyTests"]
      expect_output: "Test anUntranslatedCardReadsEnglishAndSaysSo() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "CardDetailAssemblyTests"]
      expect_output: "Test reportsEachSourcesFigureWithItsCurrency() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "CardDetailAssemblyTests"]
      expect_output: "Test aMissingSourceIsUnpricedNotZero() passed"
      covers: ["R3.AC4"]
    - command: ["swift", "test", "--filter", "CardDetailAssemblyTests"]
      expect_output: "Test pricesCarryWhenTheyWereObserved() passed"
      covers: ["R3.AC5"]
    - command: ["swift", "test", "--filter", "CardDetailAssemblyTests"]
      expect_output: "Test statesThatAPriceDescribesTheCardNotThePrinting() passed"
      covers: ["R3.AC6"]

- [x] 7. Show what the game has done to it
  - Requirements: `R5.AC1`, `R5.AC2`, `R5.AC3`, `R5.AC4`, `R5.AC5`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: The history section calls `BanlistTimelineBuilder` with the card's release date, a parameter it already takes, so the panel adds no arithmetic. Two absences that read alike are separate cases: a card never restricted, and a card among the 203 with no `konami_id` whose history cannot be looked up at all. A disagreement between the two sources shows both figures and prefers neither.
  - Verification:
    - command: ["swift", "test", "--filter", "CardDetailHistoryTests"]
      expect_output: "Test reportsTheCurrentStatusInTheChosenFormat() passed"
      covers: ["R5.AC1"]
    - command: ["swift", "test", "--filter", "CardDetailHistoryTests"]
      expect_output: "Test reportsEachChangeWithItsDateAndBothStatuses() passed"
      covers: ["R5.AC2"]
    - command: ["swift", "test", "--filter", "CardDetailHistoryTests"]
      expect_output: "Test aCardOnNoListSaysNeverRestricted() passed"
      covers: ["R5.AC3"]
    - command: ["swift", "test", "--filter", "CardDetailHistoryTests"]
      expect_output: "Test aCardWithoutAKonamiIdSaysHistoryUnavailable() passed"
      covers: ["R5.AC4"]
    - command: ["swift", "test", "--filter", "CardDetailHistoryTests"]
      expect_output: "Test neverRestrictedAndUnavailableAreDifferentAnswers() passed"
      covers: ["R5.AC3", "R5.AC4"]
    - command: ["swift", "test", "--filter", "CardDetailHistoryTests"]
      expect_output: "Test aDisagreementShowsBothFiguresNamed() passed"
      covers: ["R5.AC5"]

- [x] 8. Open the panel beside the results
  - Requirements: `R2.AC1`, `R2.AC6`, `R2.AC7`
  - Design: Architecture, Options Considered, Failure Modes And Tradeoffs
  - Notes: An inspector column, so selecting a second card is one click rather than close-and-click. That is what `R2.AC7` protects: the grid keeps its cards, its order and its scroll position while the panel changes. A card among the 124 with several artworks offers each of them; a card with one offers no chooser. A section whose read fails reports itself unavailable instead of taking the panel down.
  - Verification:
    - command: ["swift", "test", "--filter", "CardDetailPanelTests"]
      expect_output: "Test selectingACardOpensItsDetailBesideTheResults() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "CardDetailPanelTests"]
      expect_output: "Test aCardWithSeveralArtworksOffersEachOfThem() passed"
      covers: ["R2.AC6"]
    - command: ["swift", "test", "--filter", "CardDetailPanelTests"]
      expect_output: "Test aSingleArtworkCardOffersNoChooser() passed"
      covers: ["R2.AC6"]
    - command: ["swift", "test", "--filter", "CardDetailPanelTests"]
      expect_output: "Test selectingAnotherCardLeavesTheResultsUndisturbed() passed"
      covers: ["R2.AC7"]
    - command: ["swift", "test", "--filter", "CardDetailPanelTests"]
      expect_output: "Test aFailingSectionReportsItselfAndTheRestStillRenders() passed"
      covers: ["R2.AC1"]

- [x] 9. Hold the budgets
  - Requirements: `NFR1`, `NFR2`, `NFR3`, `NFR4`, `NFR5`, `NFR6`
  - Design: Verification Plan, Requirement Coverage
  - Notes: Narrowing has to feel like filtering rather than searching, and the panel has to be readable the moment it opens, so both are measured rather than assumed. The offline check builds the whole panel with every outbound call throwing; only the full artwork is allowed to be missing. The absence check walks all six ways a piece can be missing and asserts that none of them renders as zero or as a blank.
  - Verification:
    - command: ["swift", "build"]
      expect_output: "Build complete!"
      covers: ["NFR6"]
    - command: ["swift", "test", "--filter", "CardDetailBudgetTests"]
      expect_output: "Test narrowingFollowsAKeystrokeWithinOneHundredFiftyMilliseconds() passed"
      covers: ["NFR1"]
      timeout: 20m
    - command: ["swift", "test", "--filter", "CardDetailBudgetTests"]
      expect_output: "Test everyStoredSectionIsReadyWithinOneHundredMilliseconds() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "CardDetailBudgetTests"]
      expect_output: "Test everySectionButTheArtworkIsProducedOffline() passed"
      covers: ["NFR3"]
    - command: ["swift", "test", "--filter", "CardDetailBudgetTests"]
      expect_output: "Test noAbsentPieceIsRenderedAsZeroOrBlank() passed"
      covers: ["NFR4"]
    - command: ["swift", "test", "--filter", "CardDetailAccessibilityTests"]
      expect_output: "Test everyFigureReadsAsASentenceNamingItAndItsSource() passed"
      covers: ["NFR5"]
    - command: ["swift", "test", "--filter", "CardDetailAccessibilityTests"]
      expect_output: "Test reachesGridPanelAndEverySectionByKeyboardAlone() passed"
      covers: ["NFR5"]
