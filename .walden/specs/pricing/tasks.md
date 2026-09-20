---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-20T21:30:07Z
last_modified: 2026-09-20T21:39:14Z
approved_fingerprint: sha256:097995e58f53ff74449523bf7a13ea0a3c34fd4e3bde7eb494442ded47b491f1
source_design_approved_at: 2026-09-20T21:30:07Z
source_design_fingerprint: sha256:9b25a5119bfe4cac8af98a9bc9cf7357518a9c7bdb6e050e4497cd8ec99b7b3d
---

# Implementation Plan

Eight executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

Task 1 comes first because `Money` is what makes `NFR2` true by construction rather than by care, and everything after it sums money.

The figures asserted in tasks 3 and 4 come from the user's own database: a card priced at €0.02 on one source and €999.99 on another, and ten thousand copies at €0.89 which floating point cannot sum exactly.

- [x] 1. Model money, sources and currency
  - Requirements: `NFR2`
  - Design: Architecture, Data Model
  - Notes: `Money` holds integer cents and a currency taken from its source. Adding two currencies is refused by the type, because `C7` forbids conversion and a review cannot be relied on to catch it. `PriceSource` records which of the five carry asking prices rather than market prices, so nobody later adds them to an average.
  - Verification:
    - command: ["swift", "test", "--filter", "MoneyTests"]
      expect_output: "Test summingTenThousandPricesIsExact() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "MoneyTests"]
      expect_output: "Test refusesToAddAcrossCurrencies() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "MoneyTests"]
      expect_output: "Test namesTheTwoSourcesThatCarryAskingPrices() passed"

- [x] 2. Quote a card from the chosen source
  - Requirements: `R1.AC1`, `R1.AC2`, `R1.AC3`, `R1.AC4`, `R1.AC5`
  - Design: Architecture, Data Model
  - Notes: `PriceQuote` carries the chosen source's figure, every source's figure, and when they were observed. An unpriced card is unpriced, never zero. Every printing of a card costs the same, because the source publishes one figure per card.
  - Verification:
    - command: ["swift", "test", "--filter", "PriceQuoteTests"]
      expect_output: "Test reportsTheChosenSourcesFigure() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "PriceQuoteTests"]
      expect_output: "Test reportsEverySourceAlongsideTheChosenOne() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "PriceQuoteTests"]
      expect_output: "Test anUnpricedCardIsUnpricedNotZero() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "PriceQuoteTests"]
      expect_output: "Test carriesWhenThePriceWasObserved() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "PriceQuoteTests"]
      expect_output: "Test everyPrintingOfACardCostsTheSame() passed"
      covers: ["R1.AC5"]

- [x] 3. Flag the cards the sources disagree about
  - Requirements: `R2.AC1`, `R2.AC2`, `R2.AC3`, `R2.AC4`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: A card is disputed when another source exceeds the chosen one tenfold. Its chosen-source price still counts in every total: deciding which figure is wrong would be inventing data. Tested against the real shape — €0.02 against €999.99.
  - Verification:
    - command: ["swift", "test", "--filter", "PriceDisputeTests"]
      expect_output: "Test marksACardWhenAnotherSourceExceedsItTenfold() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "PriceDisputeTests"]
      expect_output: "Test namesTheDisagreeingSourceAndTheRatio() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "PriceDisputeTests"]
      expect_output: "Test aDisputedCardStillCountsInEveryTotal() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "PriceDisputeTests"]
      expect_output: "Test reportsHowManyDisputedCardsAreBehindATotal() passed"
      covers: ["R2.AC4"]

- [x] 4. Value a collection
  - Requirements: `R3.AC1`, `R3.AC2`, `R3.AC3`, `R3.AC4`, `R3.AC5`
  - Design: Simplicity And Elegance Review
  - Notes: The sum of cents over the copies held, with coverage carried in the result rather than computed by a second call. Broken down by rarity and by storage location, and reported beside what the user recorded as paid.
  - Verification:
    - command: ["swift", "test", "--filter", "CollectionValueTests"]
      expect_output: "Test sumsEachCopyAtTheChosenSource() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "CollectionValueTests"]
      expect_output: "Test excludesUnpricedCopiesAndSaysHowMany() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "CollectionValueTests"]
      expect_output: "Test perRarityValuesSumToTheTotal() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "CollectionValueTests"]
      expect_output: "Test perLocationValuesSumToTheTotal() passed"
      covers: ["R3.AC4"]
    - command: ["swift", "test", "--filter", "CollectionValueTests"]
      expect_output: "Test reportsValueBesideWhatWasPaid() passed"
      covers: ["R3.AC5"]

- [x] 5. Cost a deck and what it takes to finish one
  - Requirements: `R4.AC1`, `R4.AC2`, `R4.AC3`, `R4.AC4`, `R4.AC5`
  - Design: Options Considered
  - Notes: The same sum over a deck's slots, and over the shortfall `collection-tracker` already computes. Counting the missing copies again here would be a second implementation of a proven rule, and the two would eventually disagree.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckCostTests"]
      expect_output: "Test sumsEveryCopyAcrossEverySection() passed"
      covers: ["R4.AC1"]
    - command: ["swift", "test", "--filter", "DeckCostTests"]
      expect_output: "Test completionCostsOnlyWhatIsMissing() passed"
      covers: ["R4.AC2"]
    - command: ["swift", "test", "--filter", "DeckCostTests"]
      expect_output: "Test aFullyOwnedDeckCostsNothingToComplete() passed"
      covers: ["R4.AC3"]
    - command: ["swift", "test", "--filter", "DeckCostTests"]
      expect_output: "Test ranksTheDecksDearestCardsByWhatTheyContribute() passed"
      covers: ["R4.AC4"]
    - command: ["swift", "test", "--filter", "DeckCostTests"]
      expect_output: "Test excludesUnpricedCardsAndSaysHowMany() passed"
      covers: ["R4.AC5"]

- [x] 6. Rank the most valuable cards held
  - Requirements: `R5.AC1`, `R5.AC2`, `R5.AC3`
  - Design: Requirement Coverage
  - Notes: Ranked by what the copies held are worth together, not by unit price, because two at ten is worth more than one at fifteen.
  - Verification:
    - command: ["swift", "test", "--filter", "MostValuableTests"]
      expect_output: "Test ranksByTheValueOfTheCopiesHeld() passed"
      covers: ["R5.AC1"]
    - command: ["swift", "test", "--filter", "MostValuableTests"]
      expect_output: "Test namesCopyCountAndWhereTheCopiesAre() passed"
      covers: ["R5.AC2"]
    - command: ["swift", "test", "--filter", "MostValuableTests"]
      expect_output: "Test marksDisputedCardsInTheRanking() passed"
      covers: ["R5.AC3"]

- [x] 7. Make every figure say what it is
  - Requirements: `R6.AC1`, `R6.AC2`, `R6.AC3`, `R6.AC4`
  - Design: Simplicity And Elegance Review, Failure Modes And Tradeoffs
  - Notes: Source, observation time, coverage and the fact that a figure is an estimate are carried by the result type, so a total cannot be built without them. The reason is named too: the source publishes one price per card, not one per printing, so a Secret Rare and a Common carry the same figure.
  - Verification:
    - command: ["swift", "test", "--filter", "ValuationHonestyTests"]
      expect_output: "Test everyFigureNamesItsSource() passed"
      covers: ["R6.AC1"]
    - command: ["swift", "test", "--filter", "ValuationHonestyTests"]
      expect_output: "Test everyFigureCarriesWhenPricesWereObserved() passed"
      covers: ["R6.AC2"]
    - command: ["swift", "test", "--filter", "ValuationHonestyTests"]
      expect_output: "Test everyFigureSaysItIsAnEstimateAndWhy() passed"
      covers: ["R6.AC3"]
    - command: ["swift", "test", "--filter", "ValuationHonestyTests"]
      expect_output: "Test everyFigureReportsWhatItCouldNotValue() passed"
      covers: ["R6.AC4"]

- [x] 8. Build the valuation view and measure its budgets
  - Requirements: `NFR1`, `NFR3`, `NFR4`, `NFR5`, `NFR6`
  - Design: Architecture, Requirement Coverage
  - Notes: The valuation view over `YGOCore` types: the collection's worth, a deck's cost, the most valuable cards, and a source picker. Every figure renders as a sentence naming the amount, the source and the coverage, and everything is keyboard reachable. The budget check values ten thousand copies.
  - Verification:
    - command: ["swift", "build"]
      expect_output: "Build complete!"
      covers: ["NFR6"]
    - command: ["swift", "test", "--filter", "PricingBudgetTests"]
      expect_output: "Test valuesTenThousandCopiesUnderTwoHundredMilliseconds() passed"
      covers: ["NFR1"]
      timeout: 20m
    - command: ["swift", "test", "--filter", "PricingBudgetTests"]
      expect_output: "Test everyFigureIsComputedOffline() passed"
      covers: ["NFR3"]
    - command: ["swift", "test", "--filter", "PricingBudgetTests"]
      expect_output: "Test noFigureIsPresentedWithoutItsQualifications() passed"
      covers: ["NFR4"]
    - command: ["swift", "test", "--filter", "PricingAccessibilityTests"]
      expect_output: "Test everyFigureReadsAsASentenceNamingAmountSourceAndCoverage() passed"
      covers: ["NFR5"]
    - command: ["swift", "test", "--filter", "PricingAccessibilityTests"]
      expect_output: "Test reachesValuationScreensByKeyboardAlone() passed"
      covers: ["NFR5"]
