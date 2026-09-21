---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T07:42:13Z
last_modified: 2026-09-21T07:57:06Z
approved_fingerprint: sha256:40df42cdbe50ce37667f5407ca7b5fbdbfcea7026b8a780ef0a1fba96ed693ed
source_design_approved_at: 2026-09-21T07:42:13Z
source_design_fingerprint: sha256:bf162521c06d8d63016f6c74e38b9a4ebd6baa8b49d24eeac6ac75fe0904d8fa
---

# Implementation Plan

Nine executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

Task 1 comes first because every later proof reads a recorded list. All 177 lists are 0.43 MB, so they are recorded whole rather than sampled: a test that stores three lists cannot check that the stored count matches what the source publishes.

The figures asserted below were measured against the published data on 2026-09-21: 73 TCG lists from 1999-08-01 to 2026-05-18, and 77 entries on the 2005-03-01 TCG list, being 18 forbidden, 44 limited and 15 semi-limited.

- [x] 1. Record the published lists and decode a status
  - Requirements: `R1.AC3`
  - Design: Architecture, Data Model
  - Notes: Fetch the four directory listings and every dated body into `fixtures/banlist/`, with a manifest naming the source and the date recorded. `BanlistStatus` in `YGOCore` maps the published 0, 1 and 2 and has no fourth case, because `C3` says absence carries the remaining meaning and a type with an `unlimited` case invites a row that stores it.
  - Verification:
    - command: ["swift", "test", "--filter", "BanlistFixtureTests"]
      expect_output: "Test recordsEveryPublishedListAcrossTheFourFormats() passed"
    - command: ["swift", "test", "--filter", "BanlistFixtureTests"]
      expect_output: "Test decodesTheMarch2005ListAsSeventySevenEntries() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "BanlistFixtureTests"]
      expect_output: "Test decodesTheThreePublishedStatusesAndNoFourth() passed"
      covers: ["R1.AC3"]

- [x] 2. Add the history tables
  - Requirements: `R1.AC2`, `R1.AC4`
  - Design: Data Model
  - Notes: Migration `v005_banlist_history` adds `banlist_revision` and `banlist_entry`. `UNIQUE(format_code, effective_date)` is what makes a second synchronisation a question rather than a download. The existing `ban_status` table is not touched: it is `card-catalog`'s certified contract, and `R4.AC3` reports disagreement instead of reconciling it.
  - Verification:
    - command: ["swift", "test", "--filter", "BanlistSchemaTests"]
      expect_output: "Test migratesToVersionFiveWithoutTouchingBanStatus() passed"
    - command: ["swift", "test", "--filter", "BanlistSchemaTests"]
      expect_output: "Test aStoredRevisionCarriesItsDateAndFormat() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "BanlistSchemaTests"]
      expect_output: "Test twoFormatsShareADateAndStayDistinct() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "BanlistSchemaTests"]
      expect_output: "Test refusesASecondRevisionForTheSameFormatAndDate() passed"
      covers: ["R1.AC4"]

- [x] 3. Enumerate the lists and fetch their bodies
  - Requirements: `R1.AC1`, `R1.AC5`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: `YAMLYugiBanlistClient` lists `data/<format>` through the contents API and fetches bodies from Pages, two hosts declared in `C1`. `current.vector.json` is a pointer at a dated list and `upcoming.vector.json` is not yet in force: both are skipped, so no list is stored twice under two names. Driven by the recorded listings, never a live host.
  - Verification:
    - command: ["swift", "test", "--filter", "BanlistClientTests"]
      expect_output: "Test enumeratesSeventyThreeTCGListsFromNineteenNinetyNine() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "BanlistClientTests"]
      expect_output: "Test skipsTheCurrentAndUpcomingPointers() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "BanlistClientTests"]
      expect_output: "Test reportsFailureWhenTheSourceIsUnreachable() passed"
      covers: ["R1.AC5"]
    - command: ["swift", "test", "--filter", "BanlistClientTests"]
      expect_output: "Test reportsFailureWhenEnumerationSucceedsAndBodiesDoNot() passed"
      covers: ["R1.AC5"]

- [x] 4. Store what the synchronisation returned
  - Requirements: `R1.AC1`, `R1.AC3`, `R1.AC4`, `R1.AC6`
  - Design: Architecture, Data Model
  - Notes: The synchroniser fetches the enumerated dates minus those already stored; the set of stored dates is the cursor, so there is no incremental bookmark to keep correct. Entries are keyed by the `konami_id` the source published rather than resolved to a card, so an identifier the catalog lacks is stored and counted rather than dropped, and becomes answerable when the catalog catches up.
  - Verification:
    - command: ["swift", "test", "--filter", "BanlistSyncTests"]
      expect_output: "Test storesEveryEnumeratedListForEachFormat() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "BanlistSyncTests"]
      expect_output: "Test storesTheMarch2005ListAsEighteenForbiddenFortyFourLimitedFifteenSemi() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "BanlistSyncTests"]
      expect_output: "Test aSecondSynchronisationFetchesNoBodyAndChangesNothing() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "BanlistSyncTests"]
      expect_output: "Test storesTheOtherEntriesAndReportsOneUnmatched() passed"
      covers: ["R1.AC6"]
    - command: ["swift", "test", "--filter", "BanlistSyncTests"]
      expect_output: "Test keepsStoredHistoryWhenTheSourceGoesAway() passed"
      covers: ["R1.AC5"]

- [x] 5. Report a card's status on every list
  - Requirements: `R2.AC1`, `R2.AC2`, `R2.AC3`, `R2.AC5`
  - Design: Architecture, Options Considered
  - Notes: `BanlistTimeline` in the new `YGOBanlistHistory` module walks dated statuses and depends on `YGOCore` alone, so these four criteria are arithmetic over a list and are proven without a database. Absence means two things and `C5` separates them with the release date the catalog already stores: unrestricted after printing, nothing at all before it.
  - Verification:
    - command: ["swift", "test", "--filter", "BanlistTimelineTests"]
      expect_output: "Test reportsOneEntryPerListOldestFirst() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "BanlistTimelineTests"]
      expect_output: "Test aCardAbsentFromAListIsUnrestrictedOnIt() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "BanlistTimelineTests"]
      expect_output: "Test reportsNothingForListsPublishedBeforeTheCardExisted() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "BanlistTimelineTests"]
      expect_output: "Test aCardOnNoListIsReportedNeverRestricted() passed"
      covers: ["R2.AC5"]

- [x] 6. Report the dates the status changed
  - Requirements: `R2.AC4`
  - Design: Architecture, Simplicity And Elegance Review
  - Notes: The changes are the places where consecutive entries differ, so this is one pass over what task 5 already produced rather than a second query. A card forbidden in 2005 and unrestricted in 2015 changed twice, and a card on no list never changed.
  - Verification:
    - command: ["swift", "test", "--filter", "BanlistChangeTests"]
      expect_output: "Test reportsExactlyTwoChangesWithTheirDates() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "BanlistChangeTests"]
      expect_output: "Test aCardThatNeverMovedReportsNoChanges() passed"
      covers: ["R2.AC4"]

- [x] 7. Report a list as it stood
  - Requirements: `R3.AC1`, `R3.AC2`, `R3.AC3`
  - Design: Architecture, Data Model
  - Notes: `SQLiteBanlistHistory` reads revisions and entries and joins card names through `konami_id`. The difference between two lists includes the cards newly named and those dropped, because dropping a card from a list is a change in its status even though it leaves no row.
  - Verification:
    - command: ["swift", "test", "--filter", "BanlistListTests"]
      expect_output: "Test reportsTheMarch2005ListWithNamesAndStatuses() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "BanlistListTests"]
      expect_output: "Test reportsTCGListsInDateOrderWithNoGaps() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "BanlistListTests"]
      expect_output: "Test reportsTheCardsWhoseStatusDiffersBetweenConsecutiveLists() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "BanlistListTests"]
      expect_output: "Test countsADroppedCardAsChanged() passed"
      covers: ["R3.AC3"]

- [x] 8. Say where it came from and when it disagrees
  - Requirements: `R4.AC1`, `R4.AC2`, `R4.AC3`, `NFR4`
  - Design: Data Model, Failure Modes And Tradeoffs
  - Notes: Source and fetch time live on the revision rather than in a constant, so a row knows its own origin and a second source would not need the code to change. The two sources agreed on all 222 cards they both described when this was written, which is evidence and not a guarantee: a disagreement is reported naming both figures, never reconciled.
  - Verification:
    - command: ["swift", "test", "--filter", "BanlistProvenanceTests"]
      expect_output: "Test namesASourceThatIsNotTheCatalogs() passed"
      covers: ["R4.AC1"]
    - command: ["swift", "test", "--filter", "BanlistProvenanceTests"]
      expect_output: "Test carriesItsOwnLastSynchronisationIndependentOfTheCatalogs() passed"
      covers: ["R4.AC2"]
    - command: ["swift", "test", "--filter", "BanlistProvenanceTests"]
      expect_output: "Test reportsADisagreementNamingBothStatuses() passed"
      covers: ["R4.AC3"]
    - command: ["swift", "test", "--filter", "BanlistProvenanceTests"]
      expect_output: "Test agreesWithTheCatalogOnTheCurrentTCGList() passed"
      covers: ["NFR4"]

- [x] 9. Hold the budgets
  - Requirements: `NFR1`, `NFR2`, `NFR3`, `NFR5`
  - Design: Verification Plan, Requirement Coverage
  - Notes: A card's history is at most 73 rows and an index on `konami_id` finds them, so the 20 ms budget is measured rather than assumed. Independence is proven in both directions: the catalog's own proofs pass with the banlist source unreachable, and every question in `R2` and `R3` answers with no network.
  - Verification:
    - command: ["swift", "build"]
      expect_output: "Build complete!"
      covers: ["NFR5"]
    - command: ["swift", "test", "--filter", "BanlistBudgetTests"]
      expect_output: "Test reportsAFullHistoryWithinTwentyMilliseconds() passed"
      covers: ["NFR1"]
      timeout: 20m
    - command: ["swift", "test", "--filter", "BanlistBudgetTests"]
      expect_output: "Test theCatalogIsUnaffectedByAnUnreachableBanlistSource() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "BanlistBudgetTests"]
      expect_output: "Test theHistoryIsUnaffectedByAnUnreachableCatalog() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "BanlistBudgetTests"]
      expect_output: "Test answersEveryHistoryQuestionOffline() passed"
      covers: ["NFR3"]
