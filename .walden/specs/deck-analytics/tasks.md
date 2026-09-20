---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-20T14:10:01Z
last_modified: 2026-09-20T14:20:34Z
approved_fingerprint: sha256:50a5af1de9e16cbb7b980ea7d1516a02650a1a05b20697d77da2700b1e1bdcbf
source_design_approved_at: 2026-09-20T14:09:51Z
source_design_fingerprint: sha256:784280ab087167cfd9d4431441fb0d7322ca25dc15d0fc78d2c6c9196626264d
---

# Implementation Plan

Nine executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

Task 1 comes first because the hand size decides every figure the rest of the plan computes, and because extending `DeckCardIndex` invalidates two sealed specifications that must be re-proven before anything is built on top of them.

The figures asserted in tasks 2, 3 and 8 were computed independently before any code existed: 0.338, 0.394, 0.233 and 0.098. They are the targets, not the output.

- [x] 1. Encode the hand size rule and extend the card snapshot
  - Requirements: `R3.AC1`, `R3.AC2`, `R3.AC3`
  - Design: Architecture, Data Model
  - Notes: `CardFormat.firstPlayerDraws` is true for GOAT, OCG GOAT and Edison and false for the modern formats, taken from those formats' rule documents since the catalog does not publish it. `OpeningHand.size(format:playingFirst:)` follows from it. `DeckCardIndex.Entry` gains `type`, `level`, `attribute` and `race`, which the breakdowns need; the change is additive, so the other specifications' proofs must still pass.
  - Verification:
    - command: ["swift", "test", "--filter", "OpeningHandTests"]
      expect_output: "Test retroFormatsDealSixCardsOnThePlay() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "OpeningHandTests"]
      expect_output: "Test modernFormatsDealFiveCardsOnThePlay() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "OpeningHandTests"]
      expect_output: "Test everyFormatDealsSixCardsOnTheDraw() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "DeckModelTests"]
      expect_output: "Test cardIndexAnswersByCardIdentifier() passed"

- [x] 2. Compute the odds of opening one card
  - Requirements: `R1.AC1`, `R1.AC2`, `R1.AC3`, `R1.AC4`, `R1.AC5`
  - Design: Architecture, Options Considered
  - Notes: Exact integer arithmetic. The hand caps every binomial at `k ≤ 6`, so the largest coefficient a sixty-card deck produces is `C(60, 6) = 50,063,860` and nothing overflows. Probabilities are computed against the main section alone.
  - Verification:
    - command: ["swift", "test", "--filter", "HypergeometricTests"]
      expect_output: "Test threeCopiesInFortyOnFiveCardsIsThirtyFourPercent() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "HypergeometricTests"]
      expect_output: "Test reportsAProbabilityForEachNumberOfCopiesHeld() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "HypergeometricTests"]
      expect_output: "Test countsOnlyTheMainSection() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "HypergeometricTests"]
      expect_output: "Test reportsZeroForACardTheDeckDoesNotHold() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "HypergeometricTests"]
      expect_output: "Test reportsCertaintyWhenTheDeckIsSmallerThanTheHand() passed"
      covers: ["R1.AC5"]
    - command: ["swift", "test", "--filter", "HypergeometricTests"]
      expect_output: "Test largestCoefficientASixtyCardDeckNeedsIsExact() passed"

- [x] 3. Compute the odds of opening a combination
  - Requirements: `R2.AC1`, `R2.AC2`, `R2.AC3`, `R2.AC4`, `R2.AC5`
  - Design: Options Considered
  - Notes: Direct enumeration of the draw counts rather than inclusion-exclusion, because the user may require more than one copy of a piece and inclusion-exclusion does not extend to that. With a hand of six the sum has a few dozen terms.
  - Verification:
    - command: ["swift", "test", "--filter", "CombinationOddsTests"]
      expect_output: "Test threeAndThreeInFortyOnFiveCardsIsTenPercent() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "CombinationOddsTests"]
      expect_output: "Test aCombinationNeverExceedsItsLeastLikelyMember() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "CombinationOddsTests"]
      expect_output: "Test aSingleCardCombinationEqualsTheSingleCardFigure() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "CombinationOddsTests"]
      expect_output: "Test reportsZeroWhenAMemberIsAbsentFromTheDeck() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "CombinationOddsTests"]
      expect_output: "Test requiringTwoCopiesIsRarerThanRequiringOne() passed"
      covers: ["R2.AC5"]

- [x] 4. Follow the play order and say what was assumed
  - Requirements: `R3.AC4`, `R3.AC5`
  - Design: Architecture
  - Notes: A reported figure carries the hand size it was computed against, so a reader never has to know their format's first-turn rule to interpret it.
  - Verification:
    - command: ["swift", "test", "--filter", "PlayOrderTests"]
      expect_output: "Test switchingPlayOrderRecomputesEveryFigure() passed"
      covers: ["R3.AC4"]
    - command: ["swift", "test", "--filter", "PlayOrderTests"]
      expect_output: "Test everyReportedFigureCarriesItsHandSize() passed"
      covers: ["R3.AC5"]

- [x] 5. Break a deck down by its own numbers
  - Requirements: `R4.AC1`, `R4.AC2`, `R4.AC3`, `R4.AC4`, `R4.AC5`
  - Design: Simplicity And Elegance Review
  - Notes: One pass over the slots, accumulating into dictionaries. Copies count, not distinct cards, and the extra section is reported apart from the main one.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckBreakdownTests"]
      expect_output: "Test typeCountsSumToTheMainSectionSize() passed"
      covers: ["R4.AC1"]
    - command: ["swift", "test", "--filter", "DeckBreakdownTests"]
      expect_output: "Test levelCountsCoverOnlyMonstersThatHaveALevel() passed"
      covers: ["R4.AC2"]
    - command: ["swift", "test", "--filter", "DeckBreakdownTests"]
      expect_output: "Test attributeAndRaceCountsSumToTheCardsCarryingThem() passed"
      covers: ["R4.AC3"]
    - command: ["swift", "test", "--filter", "DeckBreakdownTests"]
      expect_output: "Test countsCopiesRatherThanDistinctCards() passed"
      covers: ["R4.AC4"]
    - command: ["swift", "test", "--filter", "DeckBreakdownTests"]
      expect_output: "Test reportsTheExtraSectionApartFromTheMainOne() passed"
      covers: ["R4.AC5"]

- [x] 6. Deal hands that can be reproduced
  - Requirements: `R5.AC1`, `R5.AC2`, `R5.AC3`
  - Design: Options Considered
  - Notes: SplitMix64 with an explicit seed, because the system generator cannot be seeded and a figure nobody can reproduce cannot be tested. Drawing takes from what the deck has left.
  - Verification:
    - command: ["swift", "test", "--filter", "HandSimulatorTests"]
      expect_output: "Test dealtHandHoldsTheFormatsSizeAndNoExtraCopies() passed"
      covers: ["R5.AC1"]
    - command: ["swift", "test", "--filter", "HandSimulatorTests"]
      expect_output: "Test oneSeedDealsOneSequence() passed"
      covers: ["R5.AC2"]
    - command: ["swift", "test", "--filter", "HandSimulatorTests"]
      expect_output: "Test drawingTakesFromWhatIsLeft() passed"
      covers: ["R5.AC3"]

- [x] 7. Measure how often a condition is met
  - Requirements: `R5.AC4`, `R5.AC5`
  - Design: Failure Modes And Tradeoffs
  - Notes: The proof that matters is that the simulation converges on the closed form: simulating a single card's presence must land near the exact hypergeometric figure for the same inputs. A sample count travels with every simulated result, so a rough figure is never read as a precise one.
  - Verification:
    - command: ["swift", "test", "--filter", "SimulatedOddsTests"]
      expect_output: "Test simulationConvergesOnTheExactFigure() passed"
      covers: ["R5.AC4"]
    - command: ["swift", "test", "--filter", "SimulatedOddsTests"]
      expect_output: "Test everySimulatedResultCarriesItsSampleCount() passed"
      covers: ["R5.AC5"]

- [x] 8. Turn the probability into a decision
  - Requirements: `R6.AC1`, `R6.AC2`, `R6.AC3`
  - Design: Requirement Coverage
  - Notes: The same hypergeometric function called across copy counts and deck sizes, so the table cannot drift from the single-card figure.
  - Verification:
    - command: ["swift", "test", "--filter", "CopyCountTableTests"]
      expect_output: "Test figuresRiseWithEachAdditionalCopy() passed"
      covers: ["R6.AC1"]
    - command: ["swift", "test", "--filter", "CopyCountTableTests"]
      expect_output: "Test fortyAgainstSixtyDiffersByWhatTheDistributionGives() passed"
      covers: ["R6.AC2"]
    - command: ["swift", "test", "--filter", "CopyCountTableTests"]
      expect_output: "Test noFigureFallsOutsideZeroToOne() passed"
      covers: ["R6.AC3"]

- [x] 9. Build the analytics view and measure its budgets
  - Requirements: `NFR1`, `NFR2`, `NFR3`, `NFR4`, `NFR5`, `NFR6`, `NFR7`
  - Design: Architecture, Requirement Coverage
  - Notes: The analytics view over `YGOCore` types: the breakdowns, the probability table, and a dealt hand. Figures read as sentences naming the card, the probability and the hand size, and everything is keyboard reachable. The budget checks measure exact-calculation latency on a sixty-card deck and confirm the feature answers offline.
  - Verification:
    - command: ["swift", "build"]
      expect_output: "Build complete!"
      covers: ["NFR7"]
    - command: ["swift", "test", "--filter", "AnalyticsBudgetTests"]
      expect_output: "Test everyExactFigureIsComputedUnderTenMilliseconds() passed"
      covers: ["NFR1"]
      timeout: 20m
    - command: ["swift", "test", "--filter", "AnalyticsBudgetTests"]
      expect_output: "Test integerArithmeticStaysExactAcrossEveryDeckSize() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "AnalyticsBudgetTests"]
      expect_output: "Test seededSimulationReproducesAcrossInstances() passed"
      covers: ["NFR3"]
    - command: ["swift", "test", "--filter", "AnalyticsBudgetTests"]
      expect_output: "Test simulatedAndExactFiguresAreNeverConfused() passed"
      covers: ["NFR4"]
    - command: ["swift", "test", "--filter", "AnalyticsBudgetTests"]
      expect_output: "Test everyCalculationAnswersOffline() passed"
      covers: ["NFR5"]
    - command: ["swift", "test", "--filter", "AnalyticsAccessibilityTests"]
      expect_output: "Test everyFigureReadsAsASentenceNamingCardProbabilityAndHandSize() passed"
      covers: ["NFR6"]
    - command: ["swift", "test", "--filter", "AnalyticsAccessibilityTests"]
      expect_output: "Test reachesBreakdownsAndTableByKeyboardAlone() passed"
      covers: ["NFR6"]
