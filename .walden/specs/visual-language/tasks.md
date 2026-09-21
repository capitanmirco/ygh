---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T12:41:23Z
last_modified: 2026-09-21T12:52:23Z
approved_fingerprint: sha256:575a832e245aedbfe9d10e3fc84bfaf746871214a68da2c7eac3bd380ae678cd
source_design_approved_at: 2026-09-21T12:41:23Z
source_design_fingerprint: sha256:c4396fcba0b83a642b4aba2cc4d80549e797b37da447cae1b9ca4e0fae88c1b6
---

# Implementation Plan

Eight executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

Task 1 comes first because the palette is the one thing here that can be objectively wrong: the game's own effect-monster orange is this application's "limited", and only measuring catches that. Everything after it is applying values that have already been proven separable.

The figures asserted below were measured against the user's own database and the existing tokens on 2026-09-21: 17 frame types resolving to 11 colours, 5,975 effect monsters against 685 normal ones, seven extra-deck frames, and three restriction colours already spoken for.

- [x] 1. Measure the palette before trusting it
  - Requirements: `R1.AC1`, `R1.AC3`, `R1.AC4`, `R1.AC5`
  - Design: Architecture, Data Model
  - Notes: `Palette.frame(_:)` over a table of measured values, with the five pendulum variants deriving from their base frame and an unknown frame falling back to the neutral. The thresholds are the proof: ΔE ≥ 25 from any restriction colour and ΔE ≥ 18 between any two base frames, computed in CIE76 Lab with no dependency. `frameComponents(_:)` exposes the raw triples so the test measures rather than trusts.
  - Verification:
    - command: ["swift", "test", "--filter", "FramePaletteTests"]
      expect_output: "Test everyFrameIncludingPendulumVariantsResolves() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "FramePaletteTests"]
      expect_output: "Test noTwoBaseFramesAreCloserThanEighteenDeltaE() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "FramePaletteTests"]
      expect_output: "Test theSevenExtraDeckFramesAreSeparableByColourAlone() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "FramePaletteTests"]
      expect_output: "Test noFrameComesWithinTwentyFiveDeltaEOfARestrictionColour() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "FramePaletteTests"]
      expect_output: "Test theRestrictionColoursKeepTheirMeaningAndTheirValues() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "FramePaletteTests"]
      expect_output: "Test anUnknownFrameFallsBackToTheNeutralRatherThanVanishing() passed"
      covers: ["R1.AC5"]

- [x] 2. Make every colour survive both appearances
  - Requirements: `R2.AC3`, `R2.AC4`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: Silver synchro disappears on a light surface and near-black Xyz on a dark one, so every frame colour is a light value and a dark value rather than one value and hope. Markers are held to 3:1 against their own appearance's surface — a marker nobody can see is not a marker — and text to 4.5:1, which is what `R2.AC3` asks for.
  - Verification:
    - command: ["swift", "test", "--filter", "AppearanceContrastTests"]
      expect_output: "Test everyMarkerHoldsThreeToOneAgainstItsOwnSurface() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "AppearanceContrastTests"]
      expect_output: "Test everyTextPairHoldsFourAndAHalfToOneInBothAppearances() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "AppearanceContrastTests"]
      expect_output: "Test everyColourResolvesInBothAppearances() passed"
      covers: ["R2.AC4"]

- [x] 3. Give the interface a scale
  - Requirements: `R3.AC1`, `R3.AC2`, `R3.AC3`
  - Design: Data Model, Simplicity And Elegance Review
  - Notes: Five sizes between 11 and 13 points is not a scale; it is a wall. A screen title at 22, a section heading at 15, body at 13, a figure at 17 with monospaced digits, and a caption at 11. The figure style matters beyond looks: a changing total that shifts the text beside it is the kind of thing nobody reports and everybody notices.
  - Verification:
    - command: ["swift", "test", "--filter", "TypographyScaleTests"]
      expect_output: "Test theFiveLevelsAreStrictlyOrderedInProminence() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "TypographyScaleTests"]
      expect_output: "Test figuresUseMonospacedDigitsSoNothingShifts() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "TypographyScaleTests"]
      expect_output: "Test theThreeElevationLevelsDifferInBothAppearances() passed"
      covers: ["R3.AC3"]

- [x] 4. Mark the cards in the catalog and its detail panel
  - Requirements: `R1.AC2`, `R2.AC1`, `R2.AC2`
  - Design: Architecture, Options Considered
  - Notes: The frame colour is a bar on the leading edge of a tile and a dot in the detail's header — never a fill behind text, which is the line between colourful and loud. Surfaces and text stay system-derived. The same card must carry the same colour in both places, which is what makes the colour worth learning.
  - Verification:
    - command: ["swift", "test", "--filter", "CatalogMarkerTests"]
      expect_output: "Test aCardCarriesTheSameColourInTheGridAndTheDetail() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "CatalogMarkerTests"]
      expect_output: "Test noTextIsDrawnOnASaturatedFrameColour() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "CatalogMarkerTests"]
      expect_output: "Test surfacesAndTextStaySystemDerived() passed"
      covers: ["R2.AC2"]

- [x] 5. Mark the cards in decks and in the collection
  - Requirements: `R1.AC2`, `R4.AC1`
  - Design: Architecture
  - Notes: A deck list is where frame colour earns its keep: seven extra-deck frames sorted into one section, told apart without reading a word. The collection rows take the same marker, so a card looks like itself wherever it appears.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckAndCollectionMarkerTests"]
      expect_output: "Test aDeckEntryCarriesItsFramesColour() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "DeckAndCollectionMarkerTests"]
      expect_output: "Test extraDeckEntriesAreToldApartWithoutReading() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "DeckAndCollectionMarkerTests"]
      expect_output: "Test collectionRowsUseTheSameMarkerAsEverywhereElse() passed"
      covers: ["R4.AC1"]

- [x] 6. Bring statistics and valuation with them
  - Requirements: `R4.AC1`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: These two are where half-finished would show: they are mostly numbers, and numbers in the old 13-point body text beside a restyled catalog would read as a different application. They take the figure style and the elevation levels, and their own charts take frame colour where they break a deck down by card type.
  - Verification:
    - command: ["swift", "test", "--filter", "AnalyticsAndPricingStyleTests"]
      expect_output: "Test everyFigureUsesTheFigureStyle() passed"
      covers: ["R4.AC1"]
    - command: ["swift", "test", "--filter", "AnalyticsAndPricingStyleTests"]
      expect_output: "Test aBreakdownByCardTypeUsesTheFrameColours() passed"
      covers: ["R4.AC1"]
    - command: ["swift", "test", "--filter", "AnalyticsAndPricingStyleTests"]
      expect_output: "Test allFiveScreensReadTheNewTokens() passed"
      covers: ["R4.AC1"]

- [x] 7. One definition, read everywhere
  - Requirements: `R4.AC2`, `R4.AC3`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: The rule that keeps this from unravelling: no feature source may contain a colour, a font size, a corner radius or a spacing literal. The test scans the sources rather than trusting the convention, because a single literal is invisible in review and permanent afterwards.
  - Verification:
    - command: ["swift", "test", "--filter", "TokenDisciplineTests"]
      expect_output: "Test noFeatureSourceContainsAColourOrSizeLiteral() passed"
      covers: ["R4.AC2"]
    - command: ["swift", "test", "--filter", "TokenDisciplineTests"]
      expect_output: "Test everyTokenHasExactlyOneDefinition() passed"
      covers: ["R4.AC2"]
    - command: ["swift", "test", "--filter", "TokenDisciplineTests"]
      expect_output: "Test changingATokenReachesEveryScreenWithNoOtherEdit() passed"
      covers: ["R4.AC3"]

- [x] 8. Hold the budgets
  - Requirements: `NFR1`, `NFR2`, `NFR3`, `NFR4`, `NFR5`
  - Design: Verification Plan, Requirement Coverage
  - Notes: Colour must never be the only way a fact is available, which is the one accessibility rule a colour-coded interface exists to break. The grid budget from `card-detail` is re-measured rather than assumed to have survived heavier tiles.
  - Verification:
    - command: ["swift", "build"]
      expect_output: "Build complete!"
      covers: ["NFR5"]
    - command: ["swift", "test", "--filter", "VisualLanguageBudgetTests"]
      expect_output: "Test noColourCodedFactIsAvailableOnlyAsColour() passed"
      covers: ["NFR1"]
    - command: ["swift", "test", "--filter", "VisualLanguageBudgetTests"]
      expect_output: "Test contrastHoldsInBothAppearancesAcrossThePalette() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "VisualLanguageBudgetTests"]
      expect_output: "Test narrowingStillFollowsAKeystrokeWithinOneHundredFiftyMilliseconds() passed"
      covers: ["NFR3"]
      timeout: 20m
    - command: ["swift", "test", "--filter", "VisualLanguageBudgetTests"]
      expect_output: "Test everyTokenIsReadFromOnePlace() passed"
      covers: ["NFR4"]
