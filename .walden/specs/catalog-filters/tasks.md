---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T13:32:28Z
last_modified: 2026-09-21T13:46:38Z
approved_fingerprint: sha256:466d5d4199c29cc0a8444e5706974d449772647b878ba342f1aa9341dc421f57
source_design_approved_at: 2026-09-21T13:31:44Z
source_design_fingerprint: sha256:89758c4540797ca55fa30c1d4842767f918f974b0766660958240c65bdf12d2a
---

# Implementation Plan

Eight executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

Task 1 comes first because `-1` is the trap in this feature: attack and defence store it where the card prints "?", and a range that admits it answers "weak monsters" with monsters nobody can measure.

The figures asserted below were measured against the user's own database on 2026-09-21: 14,566 cards — 9,365 monsters, 2,886 spells, 2,085 traps, 230 others — 9,364 with an attack value, 523 with no TCG release date, 87 monster types, 662 archetypes, and zero stored banlist revisions.

- [x] 1. Derive card type, and keep "?" out of the numbers
  - Requirements: `R1.AC1`, `R1.AC7`
  - Design: Architecture, Data Model
  - Notes: The catalog stores seventeen frames and no card type, so `CardType` is a grouping of frames that expands before it reaches SQL and reuses a condition that already works. Every numeric range gains `>= 0`, and "?" becomes its own filter: *how strong is it* and *is it knowable* are two questions. Filtering `-1` out in Swift afterwards would make the reported count and the shown rows disagree.
  - Verification:
    - command: ["swift", "test", "--filter", "CardTypeFilterTests"]
      expect_output: "Test spellsAloneAdmitOnlySpells() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "CardTypeFilterTests"]
      expect_output: "Test everySeventeenFramesGroupsIntoOneOfFourTypes() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "CardTypeFilterTests"]
      expect_output: "Test aRangeFromZeroDoesNotAdmitACardPrintingAQuestionMark() passed"
      covers: ["R1.AC7"]
    - command: ["swift", "test", "--filter", "CardTypeFilterTests"]
      expect_output: "Test theUnknownStatsFilterFindsThemInstead() passed"
      covers: ["R1.AC7"]

- [x] 2. Reach the filters the model already had
  - Requirements: `R1.AC2`, `R1.AC3`, `R1.AC4`, `R1.AC6`
  - Design: Architecture, Requirement Coverage
  - Notes: Attribute, level, monster type, archetype and the attack and defence bands are already in `CardFilters` and already reach SQL; what none of them has is a caller. Proven through the view model rather than the builder, because reaching them is the thing that was missing. A card with no level is absent from a level range rather than counted as zero.
  - Verification:
    - command: ["swift", "test", "--filter", "CardPropertyFilterTests"]
      expect_output: "Test darkAdmitsOnlyDarkMonstersAndNoSpellOrTrap() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "CardPropertyFilterTests"]
      expect_output: "Test aLevelRangeExcludesCardsWithNoLevelRatherThanCountingThemAsZero() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "CardPropertyFilterTests"]
      expect_output: "Test monsterTypeAndArchetypeEachAdmitOnlyTheirMembers() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "CardPropertyFilterTests"]
      expect_output: "Test anAttackBandAdmitsOnlyMonstersInsideIt() passed"
      covers: ["R1.AC6"]

- [x] 3. Narrow by when and where
  - Requirements: `R2.AC1`, `R2.AC2`, `R2.AC3`, `R2.AC4`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: Release dates are ISO strings, so a year range is two string comparisons against an indexed column — no new column and no parsing. The 523 cards with no date are excluded by the null comparison, and saying how many is a second count with the year clause dropped rather than an estimate.
  - Verification:
    - command: ["swift", "test", "--filter", "EraFilterTests"]
      expect_output: "Test aYearRangeAdmitsOnlyCardsReleasedInThoseYears() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "EraFilterTests"]
      expect_output: "Test theUndatedCardsHiddenByAYearRangeAreCounted() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "EraFilterTests"]
      expect_output: "Test goatAdmitsOnlyTheGoatPool() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "EraFilterTests"]
      expect_output: "Test theStatusShownIsTheOneForTheChosenFormat() passed"
      covers: ["R2.AC4"]

- [x] 4. Narrow by a published list, with that list's own statuses
  - Requirements: `R3.AC1`, `R3.AC2`, `R3.AC3`, `R3.AC5`
  - Design: Architecture, Data Model, Options Considered
  - Notes: `R3.AC1` narrows to the cards a list named; `R3.AC2` is the harder half, because the status shown must come from `banlist_entry` rather than from `ban_status`. The two never mix: with a list chosen the grid shows history, without one it shows the catalog's current view, and blending them would state something neither source says. Proven against the 2005-03-01 TCG list, 77 cards.
  - Verification:
    - command: ["swift", "test", "--filter", "PublishedListFilterTests"]
      expect_output: "Test theMarch2005ListAdmitsItsSeventySevenCardsAndNoOthers() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "PublishedListFilterTests"]
      expect_output: "Test aCardForbiddenThenAndFreeNowShowsForbidden() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "PublishedListFilterTests"]
      expect_output: "Test withNoListChosenTheCurrentStatusIsShownInstead() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "PublishedListFilterTests"]
      expect_output: "Test theChooserOffersTheStoredListsOldestFirst() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "PublishedListFilterTests"]
      expect_output: "Test aListNamingAnUnknownCardReportsTheDifference() passed"
      covers: ["R3.AC5"]

- [x] 5. Get the lists into the application
  - Requirements: `R3.AC4`, `R4.AC1`, `R4.AC2`, `R4.AC3`, `R4.AC4`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: `banlist-history` proved the synchroniser and nothing ever called it: the user's database holds zero revisions, so every card's history panel currently says no list has been downloaded. On demand rather than at launch, because 177 files at every start would cost every session for data most do not need. Driven by the recorded lists, never a live host.
  - Verification:
    - command: ["swift", "test", "--filter", "BanlistWiringTests"]
      expect_output: "Test beforeAnySynchronisationTheChooserSaysSoRatherThanBeingEmpty() passed"
      covers: ["R3.AC4"]
    - command: ["swift", "test", "--filter", "BanlistWiringTests"]
      expect_output: "Test aSynchronisationStoresWhatTheSourcePublished() passed"
      covers: ["R4.AC1"]
    - command: ["swift", "test", "--filter", "BanlistWiringTests"]
      expect_output: "Test progressIsReportedAndSearchKeepsAnswering() passed"
      covers: ["R4.AC2"]
    - command: ["swift", "test", "--filter", "BanlistWiringTests"]
      expect_output: "Test aFailedSynchronisationKeepsWhatWasStoredAndSaysSo() passed"
      covers: ["R4.AC3"]
    - command: ["swift", "test", "--filter", "BanlistWiringTests"]
      expect_output: "Test afterwardsEveryListQuestionAnswersOffline() passed"
      covers: ["R4.AC4"]

- [x] 6. Say what the filters did
  - Requirements: `R5.AC1`, `R5.AC2`, `R5.AC3`, `R5.AC4`, `R5.AC5`
  - Design: Data Model, Simplicity And Elegance Review
  - Notes: `FilterOutcome` carries the three numbers the honesty criteria need, so no screen computes them a second way and disagrees. `appliedFilters` holds sentences rather than flags, which is what lets an empty grid name what emptied it and what a screen reader has to read. Owned-only against the empty collection reports that nothing is owned rather than showing an unexplained blank.
  - Verification:
    - command: ["swift", "test", "--filter", "FilterOutcomeTests"]
      expect_output: "Test twoFiltersAdmitOnlyCardsSatisfyingBoth() passed"
      covers: ["R5.AC1"]
    - command: ["swift", "test", "--filter", "FilterOutcomeTests"]
      expect_output: "Test eachAppliedFilterIsNamedAndAnUnsetOneIsNot() passed"
      covers: ["R5.AC2"]
    - command: ["swift", "test", "--filter", "FilterOutcomeTests"]
      expect_output: "Test clearingReturnsTheCountToTheWholeCatalog() passed"
      covers: ["R5.AC3"]
    - command: ["swift", "test", "--filter", "FilterOutcomeTests"]
      expect_output: "Test anEmptyResultNamesTheFiltersResponsible() passed"
      covers: ["R5.AC4"]
    - command: ["swift", "test", "--filter", "FilterOutcomeTests"]
      expect_output: "Test ownedOnlyAgainstAnEmptyCollectionSaysNothingIsOwned() passed"
      covers: ["R5.AC5"]

- [x] 7. Put them somewhere, and make them reachable
  - Requirements: `R1.AC5`, `R5.AC6`
  - Design: Architecture, Options Considered
  - Notes: A panel rather than a popover, because `R5.AC2` needs the applied filters visible while the grid changes and a popover that stays open covers what it is changing. 87 monster types and 662 archetypes cannot be menus, so those two fields narrow as you type. Every filter is settable and clearable without a pointer, which is the difference between a panel and a mouse trap.
  - Verification:
    - command: ["swift", "test", "--filter", "FilterPanelTests"]
      expect_output: "Test typingNarrowsTheSixHundredAndSixtyTwoArchetypes() passed"
      covers: ["R1.AC5"]
    - command: ["swift", "test", "--filter", "FilterPanelTests"]
      expect_output: "Test typingNarrowsTheEightySevenMonsterTypes() passed"
      covers: ["R1.AC5"]
    - command: ["swift", "test", "--filter", "FilterPanelTests"]
      expect_output: "Test everyFilterIsSetAndClearedWithoutAPointer() passed"
      covers: ["R5.AC6"]

- [x] 8. Hold the budgets
  - Requirements: `NFR1`, `NFR2`, `NFR3`, `NFR4`, `NFR5`
  - Design: Verification Plan, Requirement Coverage
  - Notes: Measured against a full-sized catalog with the lists stored, because a filter that is instant on six cards is not evidence. The offline check runs every filter including the published-list one with every outbound call throwing.
  - Verification:
    - command: ["swift", "build"]
      expect_output: "Build complete!"
      covers: ["NFR5"]
    - command: ["swift", "test", "--filter", "FilterBudgetTests"]
      expect_output: "Test applyingAFilterUpdatesResultsWithinOneHundredFiftyMilliseconds() passed"
      covers: ["NFR1"]
      timeout: 20m
    - command: ["swift", "test", "--filter", "FilterBudgetTests"]
      expect_output: "Test everyHiddenCardIsCountedAndExplained() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "FilterBudgetTests"]
      expect_output: "Test everyFilterResolvesOfflineOnceTheListsAreStored() passed"
      covers: ["NFR3"]
    - command: ["swift", "test", "--filter", "FilterBudgetTests"]
      expect_output: "Test everyFilterReadsAsASentenceNamingWhatItNarrows() passed"
      covers: ["NFR4"]
