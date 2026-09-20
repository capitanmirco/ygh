---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-19T17:33:54Z
last_modified: 2026-09-20T08:58:44Z
approved_fingerprint: sha256:67925deb9e872ffe9352decd1c2a0707817cf0ffc5814f96f450d699ce0e8513
source_design_approved_at: 2026-09-19T17:26:49Z
source_design_fingerprint: sha256:3c24832766ac1b1caf5482255872c86cde9c060f39d2ff48633687eda5dd5128
---

# Implementation Plan

Nineteen executable tasks. Every leaf carries its own new assertions; no leaf claims an acceptance criterion through an unchanged pre-existing pass.

The whole plan is blocked on Xcode. Probed on this machine: the Command Line Tools ship `Testing.framework` but not its macro plugin (`plugin for module 'TestingMacros' not found`), and `XCTest` does not resolve at all (`unable to resolve module dependency: 'XCTest'`). `swift build` and the GRDB dependency do work today — GRDB 7.11.1 resolves and a live FTS5 probe through GRDB matched `avidita` against `Anfora dell'Avidità` — but no test can run until Xcode is installed.

Task 1 exists partly to confirm the test-runner output marker that every later proof asserts on. If swift-testing's summary line differs from the assumed `Test <name>() passed`, the proofs are corrected through a task-plan revision and re-review, not by editing sealed proofs in place.

- [x] 1. Establish the package skeleton, test harness and fixtures
  - Requirements: `NFR7`
  - Design: Architecture
  - Notes: Root `Package.swift` declaring the module targets under `Packages/`, Swift 6 language mode on every target, `.build/` ignored by git, GRDB pinned, and trimmed JSON fixtures captured from the live English and Italian datasets into `fixtures/`. The harness test asserts the package compiles and runs under strict concurrency.
  - Verification:
    - command: ["swift", "build"]
      expect_output: "Build complete!"
    - command: ["swift", "test", "--filter", "ToolchainHarnessTests"]
      expect_output: "Test buildsUnderStrictConcurrency() passed"
      covers: ["NFR7"]
    - command: ["sh", "-c", "test -s fixtures/catalog-en.json && test -s fixtures/catalog-it.json"]

- [x] 2. Model the domain types and repository protocols in YGOCore
  - Requirements: `R6.AC6`
  - Design: Architecture, Data Model
  - Notes: `Card`, `Artwork`, `CardFormat`, `BanStatus`, `CopyAllowance`, plus the `CardRepository`, `CatalogSyncing`, `ArtworkProviding` and `BanListEditing` protocols. The allowance mapping is the observable behaviour.
  - Verification:
    - command: ["swift", "test", "--filter", "CopyAllowanceTests"]
      expect_output: "Test mapsEachBanStatusToItsCopyAllowance() passed"
      covers: ["R6.AC6"]

- [x] 3. Define the v001 schema migration
  - Requirements: `R8.AC2`
  - Design: Data Model
  - Notes: Every table in the design's schema block, the FTS5 external-content table with `unicode61 remove_diacritics 2`, its synchronisation triggers, and the indexes the filter columns need. Completing the migration records the schema version.
  - Verification:
    - command: ["swift", "test", "--filter", "SchemaMigrationTests"]
      expect_output: "Test recordsSchemaVersionAfterMigrating() passed"
      covers: ["R8.AC2"]
    - command: ["swift", "test", "--filter", "SchemaShapeTests"]
      expect_output: "Test createsEveryDeclaredTableAndIndex() passed"

- [x] 4. Implement backup-then-migrate startup with restore on failure
  - Requirements: `R8.AC1`, `R8.AC3`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: `DatabaseBootstrapper` copies the database file before running the migrator and restores that copy if any migration throws. A deliberately failing migration fixture drives the restore path.
  - Verification:
    - command: ["swift", "test", "--filter", "DatabaseBootstrapperTests"]
      expect_output: "Test writesBackupBeforeApplyingMigrations() passed"
      covers: ["R8.AC1"]
    - command: ["swift", "test", "--filter", "DatabaseBootstrapperTests"]
      expect_output: "Test restoresBackupWhenMigrationFails() passed"
      covers: ["R8.AC3"]

- [x] 5. Implement the shared rate limiter
  - Requirements: `R4.AC8`, `NFR5`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: Token-bucket `actor` at ten permits per second, driven by an injected clock so the test is deterministic and fast. Both the JSON client and the image fetcher acquire from this one instance.
  - Verification:
    - command: ["swift", "test", "--filter", "RateLimiterTests"]
      expect_output: "Test neverExceedsTenPermitsInAnyOneSecondWindow() passed"
      covers: ["R4.AC8", "NFR5"]
    - command: ["swift", "test", "--filter", "RateLimiterTests"]
      expect_output: "Test haltsAfterUpstreamRejectsWithTooManyRequests() passed"

- [x] 6. Implement the catalog API client with tolerant decoding
  - Requirements: `R2.AC1`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: Version and dataset requests against recorded fixtures, never a live host. Decoding ignores unknown fields and tolerates missing optional ones; a missing required field throws.
  - Verification:
    - command: ["swift", "test", "--filter", "CatalogClientTests"]
      expect_output: "Test requestsCatalogVersionBeforeAnyDataset() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "CatalogDecodingTests"]
      expect_output: "Test ignoresUnknownFieldsAndThrowsOnMissingRequiredField() passed"

- [x] 7. Implement the single-transaction catalog writer
  - Requirements: `R1.AC2`, `R1.AC5`, `R6.AC1`, `R6.AC2`, `R7.AC1`
  - Design: Data Model, Simplicity And Elegance Review
  - Notes: One `write` transaction persisting cards, artwork identifiers, format memberships, upstream ban statuses, printings and prices. Shared by the seed and update paths. Upstream ban rows are written with `source = 'upstream'`.
  - Verification:
    - command: ["swift", "test", "--filter", "CatalogWriterTests"]
      expect_output: "Test leavesCatalogEmptyWhenPersistenceFailsPartway() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "CatalogWriterTests"]
      expect_output: "Test storesPricesWithSourceValueAndObservationTime() passed"
      covers: ["R1.AC5"]
    - command: ["swift", "test", "--filter", "CatalogWriterTests"]
      expect_output: "Test storesFormatMembershipPerCard() passed"
      covers: ["R6.AC1"]
    - command: ["swift", "test", "--filter", "CatalogWriterTests"]
      expect_output: "Test storesUpstreamBanStatusesWithUpstreamSource() passed"
      covers: ["R6.AC2"]
    - command: ["swift", "test", "--filter", "CatalogWriterTests"]
      expect_output: "Test storesEveryArtworkIdentifierAgainstItsCard() passed"
      covers: ["R7.AC1"]

- [x] 8. Implement the seed path with progress and failure containment
  - Requirements: `R1.AC1`, `R1.AC3`, `R1.AC4`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: `CatalogSynchronizer` takes the seed path only when the catalog holds no cards, exposes a stage and a completion proportion while running, and leaves the catalog empty with a retryable error when retrieval throws.
  - Verification:
    - command: ["swift", "test", "--filter", "CatalogSeedTests"]
      expect_output: "Test retrievesFullDatasetOnlyWhenCatalogIsEmpty() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "CatalogSeedTests"]
      expect_output: "Test reportsStageAndIncreasingProportionWhileSeeding() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "CatalogSeedTests"]
      expect_output: "Test leavesCatalogEmptyAndOffersRetryWhenRetrievalFails() passed"
      covers: ["R1.AC4"]

- [x] 9. Implement the update path
  - Requirements: `R2.AC2`, `R2.AC3`, `R2.AC4`, `R2.AC5`, `R2.AC6`, `R2.AC7`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: Compare stored against upstream version; retrieve and upsert on difference, skip on equality, record version and completion time on success, keep running on a failed version request, and leave the prior catalog untouched when an upsert throws. The user-triggered refresh reuses this path.
  - Verification:
    - command: ["swift", "test", "--filter", "CatalogUpdateTests"]
      expect_output: "Test upsertsChangedCardsWhenUpstreamVersionDiffers() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "CatalogUpdateTests"]
      expect_output: "Test skipsDatasetRequestWhenVersionsMatch() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "CatalogUpdateTests"]
      expect_output: "Test storesVersionAndCompletionTimeAfterUpdate() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "CatalogUpdateTests"]
      expect_output: "Test startsOnStoredCatalogWhenVersionRequestFails() passed"
      covers: ["R2.AC5"]
    - command: ["swift", "test", "--filter", "CatalogUpdateTests"]
      expect_output: "Test userRefreshPerformsSameVersionCheckAsStartup() passed"
      covers: ["R2.AC6"]
    - command: ["swift", "test", "--filter", "CatalogUpdateTests"]
      expect_output: "Test retainsPriorCatalogWhenUpsertFails() passed"
      covers: ["R2.AC7"]

- [x] 10. Implement bilingual storage and presentation
  - Requirements: `R3.AC1`, `R3.AC2`, `R3.AC3`, `R3.AC4`
  - Design: Data Model, Failure Modes And Tradeoffs
  - Notes: Retrieve the Italian dataset alongside the English one and join on the card identifier, which the Italian response carries. `CardPresentation` returns Italian where present, complete English otherwise, and flags the fallback. Italian rows for unknown identifiers are discarded.
  - Verification:
    - command: ["swift", "test", "--filter", "BilingualCatalogTests"]
      expect_output: "Test storesItalianAndEnglishTextJoinedByCardIdentifier() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "CardPresentationTests"]
      expect_output: "Test presentsItalianTextWhenTranslationExists() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "CardPresentationTests"]
      expect_output: "Test presentsCompleteEnglishTextWhenTranslationIsAbsent() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "CardPresentationTests"]
      expect_output: "Test marksFallbackTextAsUntranslated() passed"
      covers: ["R3.AC4"]

- [x] 11. Implement artwork identifier resolution
  - Requirements: `R7.AC2`, `R7.AC3`
  - Design: Data Model
  - Notes: Resolve any stored artwork identifier to its card, and report an identifier absent from the catalog as unresolved rather than returning a nearest match. The multi-artwork fixture uses a card with three identifiers, as confirmed in the live data.
  - Verification:
    - command: ["swift", "test", "--filter", "ArtworkResolutionTests"]
      expect_output: "Test resolvesEveryAlternateArtworkIdentifierToOneCard() passed"
      covers: ["R7.AC2"]
    - command: ["swift", "test", "--filter", "ArtworkResolutionTests"]
      expect_output: "Test reportsUnknownIdentifierAsUnresolved() passed"
      covers: ["R7.AC3"]

- [x] 12. Implement ban status defaults, user editing and preservation
  - Requirements: `R6.AC3`, `R6.AC4`, `R6.AC5`
  - Design: Data Model, Simplicity And Elegance Review
  - Notes: A missing row means Unlimited. Formats without upstream ban data accept user-recorded statuses stored with `source = 'user'`, and an update deletes only `source = 'upstream'` rows so those survive.
  - Verification:
    - command: ["swift", "test", "--filter", "BanStatusTests"]
      expect_output: "Test reportsUnlimitedWhenNoBanRowExists() passed"
      covers: ["R6.AC3"]
    - command: ["swift", "test", "--filter", "BanStatusTests"]
      expect_output: "Test persistsUserRecordedStatusForFormatWithoutUpstreamData() passed"
      covers: ["R6.AC4"]
    - command: ["swift", "test", "--filter", "BanStatusTests"]
      expect_output: "Test retainsUserStatusesWhileReplacingUpstreamOnes() passed"
      covers: ["R6.AC5"]

- [x] 13. Implement the artwork store
  - Requirements: `R4.AC1`, `R4.AC9`
  - Design: Data Model, Options Considered
  - Notes: Sharded directory layout under Application Support, presence recorded in `artwork_cache`, reads served only from disk, and a purge that empties the directory while leaving card records intact.
  - Verification:
    - command: ["swift", "test", "--filter", "ArtworkStoreTests"]
      expect_output: "Test servesStoredArtworkWithFetcherDisabled() passed"
      covers: ["R4.AC1"]
    - command: ["swift", "test", "--filter", "ArtworkStoreTests"]
      expect_output: "Test purgeEmptiesDirectoryAndKeepsCardRecords() passed"
      covers: ["R4.AC9"]

- [x] 14. Implement artwork prefetch, resume and on-demand retrieval
  - Requirements: `R4.AC2`, `R4.AC3`, `R4.AC4`, `R4.AC5`, `R4.AC6`, `R4.AC7`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: Prefetch starts after a successful seed, reports stored against expected counts, keeps queries answerable while running, resumes by anti-join after interruption, retrieves a full-resolution image on detail open, and yields a named placeholder when artwork is unavailable.
  - Verification:
    - command: ["swift", "test", "--filter", "ArtworkPrefetchTests"]
      expect_output: "Test beginsThumbnailRetrievalAfterSeedCompletes() passed"
      covers: ["R4.AC2"]
    - command: ["swift", "test", "--filter", "ArtworkPrefetchTests"]
      expect_output: "Test reportsStoredCountAdvancingAgainstExpectedTotal() passed"
      covers: ["R4.AC3"]
    - command: ["swift", "test", "--filter", "ArtworkPrefetchTests"]
      expect_output: "Test answersSearchWhilePrefetchIsRunning() passed"
      covers: ["R4.AC4"]
    - command: ["swift", "test", "--filter", "ArtworkPrefetchTests"]
      expect_output: "Test requestsOnlyMissingThumbnailsAfterInterruption() passed"
      covers: ["R4.AC5"]
    - command: ["swift", "test", "--filter", "ArtworkPrefetchTests"]
      expect_output: "Test retrievesFullImageOnDetailOpenAndNotAgain() passed"
      covers: ["R4.AC6"]
    - command: ["swift", "test", "--filter", "ArtworkPrefetchTests"]
      expect_output: "Test yieldsNamedPlaceholderWhenArtworkUnavailable() passed"
      covers: ["R4.AC7"]

- [x] 15. Implement full-text search with weighted ranking
  - Requirements: `R5.AC1`, `R5.AC2`
  - Design: Data Model, Options Considered
  - Notes: One `MATCH` query over the external-content table, ordered by `bm25` with the two name columns weighted far above the two description columns. Diacritic folding was confirmed through GRDB against system SQLite 3.45.3.
  - Verification:
    - command: ["swift", "test", "--filter", "CardSearchTests"]
      expect_output: "Test findsSameCardByItalianOnlyAndEnglishOnlySubstrings() passed"
      covers: ["R5.AC1"]
    - command: ["swift", "test", "--filter", "CardSearchTests"]
      expect_output: "Test matchesAccentedNameFromUnaccentedQuery() passed"
      covers: ["R5.AC1"]
    - command: ["swift", "test", "--filter", "CardSearchTests"]
      expect_output: "Test ranksExactNameMatchAboveEffectTextMatches() passed"
      covers: ["R5.AC2"]

- [x] 16. Implement the filter query builder
  - Requirements: `R5.AC3`, `R5.AC4`, `R5.AC5`, `R5.AC6`
  - Design: Data Model
  - Notes: Filters compose conjunctively over indexed columns, removal recomputes from the remainder, an unsatisfiable combination yields a settled empty state distinct from loading, and every query resolves locally.
  - Verification:
    - command: ["swift", "test", "--filter", "CardFilterTests"]
      expect_output: "Test everyResultSatisfiesEveryAppliedFilter() passed"
      covers: ["R5.AC3"]
    - command: ["swift", "test", "--filter", "CardFilterTests"]
      expect_output: "Test removingFilterYieldsSetOfRemainingFiltersAlone() passed"
      covers: ["R5.AC4"]
    - command: ["swift", "test", "--filter", "CardFilterTests"]
      expect_output: "Test unsatisfiableCombinationYieldsSettledEmptyState() passed"
      covers: ["R5.AC5"]
    - command: ["swift", "test", "--filter", "CardFilterTests"]
      expect_output: "Test resolvesEveryQueryWithClientThrowingOnEveryCall() passed"
      covers: ["R5.AC6"]

- [x] 17. Build the browser feature with language switching and accessibility
  - Requirements: `R3.AC5`, `NFR6`
  - Design: Architecture, Requirement Coverage
  - Notes: An `@Observable` view model depending only on `YGOCore` protocols. Changing language re-presents stored text with no retrieval. Search field, filter controls and grid are keyboard reachable, and every card element exposes its name and card type.
  - Verification:
    - command: ["swift", "test", "--filter", "BrowserViewModelTests"]
      expect_output: "Test languageSwitchRePresentsTextWithoutAnyRequest() passed"
      covers: ["R3.AC5"]
    - command: ["swift", "test", "--filter", "BrowserAccessibilityTests"]
      expect_output: "Test exposesNameAndCardTypeForEveryGridElement() passed"
      covers: ["NFR6"]
    - command: ["swift", "test", "--filter", "BrowserAccessibilityTests"]
      expect_output: "Test reachesSearchFiltersAndGridByKeyboardAlone() passed"
      covers: ["NFR6"]

- [x] 18. Wire the composition root and prove end-to-end offline operation
  - Requirements: `NFR4`
  - Design: Architecture
  - Notes: The app target binds protocols to concrete implementations and runs the startup flow. The proof drives a seeded store with every outbound call stubbed to throw and asserts that search, filtering, ban reporting, artwork resolution and language switching all still work.
  - Verification:
    - command: ["swift", "build"]
      expect_output: "Build complete!"
    - command: ["swift", "test", "--filter", "OfflineIntegrationTests"]
      expect_output: "Test everyFeatureWorksWithAllOutboundCallsThrowing() passed"
      covers: ["NFR4"]

- [x] 19. Measure the performance and storage budgets
  - Requirements: `NFR1`, `NFR2`, `NFR3`
  - Design: Verification Plan
  - Notes: Against a full-size synthetic catalog, measure search latency, confirm reads proceed while a sync write is open, and measure the database file and thumbnail directory sizes. The generated catalog is written outside the repository so the measurement does not alter the worktree.
  - Verification:
    - command: ["swift", "test", "--filter", "CatalogPerformanceTests"]
      expect_output: "Test searchLatencyP95StaysUnderOneHundredMilliseconds() passed"
      covers: ["NFR1"]
      timeout: 30m
    - command: ["swift", "test", "--filter", "CatalogPerformanceTests"]
      expect_output: "Test readsProceedConcurrentlyWithOpenSyncWrite() passed"
      covers: ["NFR2"]
      timeout: 30m
    - command: ["swift", "test", "--filter", "CatalogBudgetTests"]
      expect_output: "Test databaseAndThumbnailSizesStayWithinBudget() passed"
      covers: ["NFR3"]
      timeout: 30m
