---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T14:41:01Z
last_modified: 2026-09-21T14:44:16Z
approved_fingerprint: sha256:3f187a06ef7d443e85c284fe5beba1c74c2baa634d72c0cdf5654afb7056f58a
source_design_approved_at: 2026-09-21T14:41:01Z
source_design_fingerprint: sha256:e5d0205e7358148d9b55de44699cb621620272aeac4dc569c48362f48089494a
---

# Implementation Plan

Five executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

Task 1 builds the table and task 2 proves it covers the catalog, because a translation that is 90% complete is a screen that reads half in English.

The figures asserted below were measured against the user's own database on 2026-09-21: 101 distinct card kinds of which 54 are `Skill - <character>`, 87 monster types of which 53 are those same character names and one is empty, 7 attributes and 48 printing rarities.

- [x] 1. Build the vocabulary
  - Requirements: `R1.AC1`, `R1.AC2`, `R1.AC3`, `R1.AC4`, `R1.AC5`
  - Design: Architecture, Data Model
  - Notes: Whole terms rather than composed ones: `Fusion Pendulum Effect Monster` is four words, and Italian leads with the noun, so word-by-word substitution produces the right words in the wrong order. Every lookup takes its argument as its default, so the miss case and the hit case are the same call and no caller branches. Rarities are translated only where the Italian market renames them — "Secret Rare" is what it is called here.
  - Verification:
    - command: ["swift", "test", "--filter", "VocabularyTests"]
      expect_output: "Test cardKindsReadInItalian() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "VocabularyTests"]
      expect_output: "Test attributesReadInItalian() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "VocabularyTests"]
      expect_output: "Test monsterTypesReadInItalian() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "VocabularyTests"]
      expect_output: "Test raritiesAreTranslatedOnlyWhereItalyRenamesThem() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "VocabularyTests"]
      expect_output: "Test anUnknownTermIsReturnedUnchangedRatherThanBlanked() passed"
      covers: ["R1.AC5"]

- [x] 2. Cover what the catalog actually holds
  - Requirements: `R3.AC1`, `R3.AC2`, `R3.AC3`, `R3.AC4`
  - Design: Architecture, Verification Plan
  - Notes: 54 of the 101 kinds carry a character's name and 53 of the 87 types are those names again, upstream-truncated to thirteen characters. Those resolve through their prefix or as themselves, because `R2.AC3` keeps proper names as published and the missing letters would be ours to invent. The coverage check walks the catalog's own distinct values rather than a list someone typed.
  - Verification:
    - command: ["swift", "test", "--filter", "VocabularyCoverageTests"]
      expect_output: "Test allSevenAttributesResolve() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "VocabularyCoverageTests"]
      expect_output: "Test everyCardKindTheCatalogHoldsResolves() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "VocabularyCoverageTests"]
      expect_output: "Test everyMonsterTypeTheCatalogHoldsResolves() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "VocabularyCoverageTests"]
      expect_output: "Test skillKindsTranslateTheirPrefixAndKeepTheirName() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "VocabularyCoverageTests"]
      expect_output: "Test theUntranslatedCountIsZeroForTheCatalogAsItStands() passed"
      covers: ["R3.AC4"]

- [x] 3. Use it on every screen that shows a card
  - Requirements: `R2.AC1`, `R2.AC2`
  - Design: Data Model, Simplicity And Elegance Review
  - Notes: `humanReadableType` is printed raw in four places — the grid tile, the detail panel, a deck row and a collection row. Each becomes one call to the same function, which is what makes `R2.AC1` true by construction rather than by discipline. The literal scan then holds it that way.
  - Verification:
    - command: ["swift", "test", "--filter", "VocabularyUsageTests"]
      expect_output: "Test theSameCardReadsTheSameOnEveryScreen() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "VocabularyUsageTests"]
      expect_output: "Test noFeatureSourceTranslatesAnUpstreamTermItself() passed"
      covers: ["R2.AC2"]

- [x] 4. Keep proper names, and match on what is shown
  - Requirements: `R2.AC3`, `R2.AC4`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: An archetype, a set and a format are published names and stay as they are; translating "Blue-Eyes" would make a card unfindable by the name printed on it. The monster type filter shows Italian, so it has to match Italian — a field that displays "Incantatore" and finds nothing when you type it is worse than one that displays English.
  - Verification:
    - command: ["swift", "test", "--filter", "VocabularyProperNameTests"]
      expect_output: "Test archetypesSetsAndFormatsAreShownAsPublished() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "VocabularyProperNameTests"]
      expect_output: "Test typingIncantatoreFindsSpellcaster() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "VocabularyProperNameTests"]
      expect_output: "Test theFilterStillMatchesTheUpstreamTermToo() passed"
      covers: ["R2.AC4"]

- [x] 5. Hold the budgets
  - Requirements: `NFR1`, `NFR2`, `NFR3`, `NFR4`
  - Design: Verification Plan, Requirement Coverage
  - Notes: A grid holds 200 tiles and each translates one term, so the cost is measured at that size rather than argued to be negligible. The honesty check is the one that matters as the game grows: a term nobody has translated yet must reach the screen, not vanish from it.
  - Verification:
    - command: ["swift", "build"]
      expect_output: "Build complete!"
      covers: ["NFR4"]
    - command: ["swift", "test", "--filter", "VocabularyBudgetTests"]
      expect_output: "Test translatingTwoHundredTilesCostsNothingMeasurable() passed"
      covers: ["NFR1"]
    - command: ["swift", "test", "--filter", "VocabularyBudgetTests"]
      expect_output: "Test noTermIsEverLostOnItsWayToTheScreen() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "VocabularyBudgetTests"]
      expect_output: "Test whatIsReadAloudIsTheTranslatedTerm() passed"
      covers: ["NFR3"]
