---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-19T17:16:14Z
last_modified: 2026-09-19T17:16:14Z
approved_fingerprint: sha256:22b95dd0c20c807a8e0ca98575d5e47b179fd4aa45b93c5b44cab5af0300f54c
---

# Requirements Document

## Introduction

The card catalog is the foundation every other feature of YGODeckManager builds on. It acquires the complete Yu-Gi-Oh! card pool from the YGOPRODeck public API, stores it locally so the application works without a network connection, caches card artwork on disk as the API's terms require, and exposes fast search and filtering over the whole pool.

This feature covers acquisition, storage, artwork caching, language handling, format and ban-status data, artwork-identifier resolution, and the browse/search surface. It does not cover deck construction, collection tracking, statistics or price presentation, which are separate specifications that consume this catalog.

Measured characteristics of the upstream source, confirmed against the live API on 2026-09-19: the English dataset is 14,566 cards in a single 23.7 MB response; the Italian dataset is 11,599 cards in 17.3 MB and carries a `name_en` field for linking; there are 14,730 distinct artwork identifiers; thumbnails average about 24 KB and full-resolution images about 138 KB.

## Requirements

### R1 Initial catalog acquisition

**User Story:** As a duelist opening the application for the first time, I want the complete card pool to be downloaded and stored locally, so that I can search and build decks without depending on a network connection afterwards.

#### Acceptance Criteria

1. `R1.AC1` WHEN the application starts and the local catalog holds no cards, the system SHALL retrieve the complete English card dataset from the upstream card API.
   - Acceptance check: starting against an empty database yields a stored card count equal to the count in the retrieved dataset; starting again against the populated database performs no dataset retrieval.
2. `R1.AC2` WHEN a complete card dataset has been retrieved, the system SHALL commit every card record in a single atomic transaction.
   - Acceptance check: a failure injected partway through persistence leaves the catalog empty; no intermediate partial card count is ever observable.
3. `R1.AC3` WHILE initial catalog acquisition is in progress, the system SHALL report the acquisition stage and its completion proportion.
   - Acceptance check: an observer sampling the exposed progress during acquisition sees a stage label and a proportion that increases toward completion, rather than an undifferentiated busy state.
4. `R1.AC4` IF initial catalog acquisition fails, THEN the system SHALL leave the catalog empty and present the failure as a retryable condition.
   - Acceptance check: with the upstream host unreachable on first start, the application finishes starting, the catalog is empty, a retry affordance is offered, and no partially populated catalog remains.
5. `R1.AC5` WHEN card records are persisted, the system SHALL store each card's per-source market prices together with the time they were observed.
   - Acceptance check: after acquisition the stored price rows for a known card carry a source name, a numeric value and an observation timestamp.

### R2 Catalog updates

**User Story:** As a duelist, I want the catalog to pick up newly released cards and banlist changes, so that my decks are validated against current data without me managing downloads.

#### Acceptance Criteria

1. `R2.AC1` WHEN the application starts and the local catalog holds cards, the system SHALL request the upstream catalog version identifier.
   - Acceptance check: a start against a populated catalog issues exactly one version request and no dataset request until that response is evaluated.
2. `R2.AC2` IF the upstream catalog version differs from the stored version, THEN the system SHALL retrieve the current dataset and upsert every changed card record.
   - Acceptance check: with a stored version deliberately set to an older value, a start retrieves the dataset and a card whose upstream fields changed reflects the new values; unrelated cards keep their stored values and identifiers.
3. `R2.AC3` IF the upstream catalog version equals the stored version, THEN the system SHALL skip dataset retrieval.
   - Acceptance check: a second start immediately after a successful update issues the version request but no dataset request.
4. `R2.AC4` WHEN a catalog update completes successfully, the system SHALL store the upstream version identifier and the time the update completed.
   - Acceptance check: the stored sync record after an update carries the version identifier returned upstream and a completion timestamp later than the one it replaced.
5. `R2.AC5` IF the version request fails, THEN the system SHALL continue starting against the existing local catalog.
   - Acceptance check: with the upstream host unreachable and a populated catalog present, the application starts, search returns results, and the failure is reported without blocking use.
6. `R2.AC6` WHEN the user requests a catalog refresh, the system SHALL perform the version check and any resulting update.
   - Acceptance check: invoking the refresh action outside of startup produces the same version check and conditional update as a start would.
7. `R2.AC7` IF a catalog update fails after the dataset has been retrieved, THEN the system SHALL retain the previously stored catalog unchanged.
   - Acceptance check: a failure injected during upsert leaves stored card count, card values and stored version identical to their pre-update state.

### R3 Bilingual card text

**User Story:** As an Italian-speaking duelist, I want card names and effect text in Italian where a translation exists, so that I can read what a card does in my own language without losing access to the cards that have no translation.

#### Acceptance Criteria

1. `R3.AC1` WHEN the catalog is acquired or updated, the system SHALL retrieve and persist the Italian card dataset in addition to the English dataset.
   - Acceptance check: after acquisition, a card known to have an Italian translation carries both an Italian and an English name and effect text in storage.
2. `R3.AC2` WHERE an Italian translation exists for a card and Italian is the selected language, the system SHALL present that card's name and effect text in Italian.
   - Acceptance check: with Italian selected, a card known to be translated displays its Italian name and effect text rather than the English ones.
3. `R3.AC3` IF no Italian translation exists for a card and Italian is the selected language, THEN the system SHALL present that card's English name and effect text.
   - Acceptance check: with Italian selected, a card known to lack a translation displays complete English name and effect text, never an empty or placeholder value.
4. `R3.AC4` WHERE presented card text has fallen back to English, the system SHALL mark that text as untranslated.
   - Acceptance check: a translated card and an untranslated card are distinguishable in the interface without opening either one's source data.
5. `R3.AC5` WHEN the user changes the selected card language, the system SHALL present card text in the new language without retrieving any dataset.
   - Acceptance check: switching language with the network unavailable changes the presented names and effect text immediately.

### R4 Artwork cache

**User Story:** As a duelist, I want card images stored on my own machine, so that browsing stays fast and offline, and so that the application respects the upstream host's prohibition on hotlinking.

#### Acceptance Criteria

1. `R4.AC1` The system SHALL present card artwork exclusively from the local image store.
   - Acceptance check: with all outbound traffic to the image host blocked, every already-stored image still renders; no rendered view resolves a remote image address.
2. `R4.AC2` WHEN initial catalog acquisition completes, the system SHALL begin retrieving every card thumbnail into the local image store as background work.
   - Acceptance check: after acquisition completes, the count of stored thumbnails rises over time with no further user action.
3. `R4.AC3` WHILE thumbnail retrieval is in progress, the system SHALL report the number of thumbnails stored against the total expected.
   - Acceptance check: the exposed counts sampled twice during retrieval are both present, and the stored count of the later sample is greater than the earlier one.
4. `R4.AC4` WHILE thumbnail retrieval is in progress, the system SHALL continue to serve search and navigation requests.
   - Acceptance check: a search issued while retrieval is running returns its full result set, and its latency is within the same budget as a search issued while idle.
5. `R4.AC5` WHEN the application starts after thumbnail retrieval was interrupted, the system SHALL resume retrieval for the thumbnails that are not yet stored.
   - Acceptance check: after an interruption at a known partial count, a restart retrieves only the missing thumbnails and does not re-retrieve stored ones.
6. `R4.AC6` WHEN the user opens a card detail view whose full-resolution image is absent from the local image store, the system SHALL retrieve that image and store it.
   - Acceptance check: opening a card whose full image is absent results in that image being present in the store afterwards, and reopening it issues no further retrieval.
7. `R4.AC7` IF a card's artwork is absent from the local image store and cannot be retrieved, THEN the system SHALL present a placeholder carrying that card's name.
   - Acceptance check: with the image host unreachable, a card with no stored artwork still renders as an identifiable, named element rather than a blank or broken one.
8. `R4.AC8` The system SHALL issue at most ten outbound requests per second across all upstream hosts combined.
   - Acceptance check: a measurement window taken during concurrent catalog and image retrieval contains no one-second interval with more than ten outbound requests.
9. `R4.AC9` WHEN the user requests that the image store be emptied, the system SHALL delete the stored images and retain all card records.
   - Acceptance check: after the operation the image store occupies no space, stored card count is unchanged, and decks and search still work.

### R5 Search and filtering

**User Story:** As a duelist, I want to find any card in the pool by name, by effect text, or by its game attributes, so that I can assemble a deck without leaving the application.

#### Acceptance Criteria

1. `R5.AC1` WHEN the user enters search text, the system SHALL return the cards whose name or effect text matches that text in either stored language.
   - Acceptance check: searching an Italian-only substring returns the translated card, and searching an English-only substring returns the same card.
2. `R5.AC2` WHEN search results are returned, the system SHALL order cards matched on name ahead of cards matched only on effect text.
   - Acceptance check: a query that is both an exact card name and a common phrase in other cards' effect text places the exactly named card first.
3. `R5.AC3` WHEN the user applies any combination of the card-property filters, the system SHALL return only the cards that satisfy every applied filter at once.
   - Acceptance check: two filters that are individually non-empty but jointly unsatisfiable return no cards, and every card in a satisfiable combined result independently satisfies each applied filter.
4. `R5.AC4` WHEN the user removes a filter, the system SHALL return results computed from the remaining filters.
   - Acceptance check: removing one filter from a combination yields exactly the result set that the remaining filters produce when applied on their own.
5. `R5.AC5` IF a search or filter combination matches no card, THEN the system SHALL present an empty result state distinct from an in-progress state.
   - Acceptance check: a deliberately unsatisfiable query shows a settled "no matches" state that a user cannot confuse with loading.
6. `R5.AC6` The system SHALL resolve every search and filter query against local storage only.
   - Acceptance check: with all outbound traffic blocked, every search and filter combination still returns its full correct result set.

### R6 Format membership and ban status

**User Story:** As a duelist who plays several formats, I want to know which formats a card is legal in and how many copies each format permits, so that a deck can be validated against the format I actually play.

#### Acceptance Criteria

1. `R6.AC1` WHEN the catalog is acquired or updated, the system SHALL persist each card's format memberships.
   - Acceptance check: a card known to be absent from a given format carries no membership for it, and a card known to be present carries one.
2. `R6.AC2` WHEN the catalog is acquired or updated, the system SHALL persist each card's ban status for every format whose ban data the upstream source provides.
   - Acceptance check: cards known to be Forbidden, Limited and Semi-Limited in a provided format each carry the corresponding stored status.
3. `R6.AC3` WHERE a card carries no stored ban status for a format it belongs to, the system SHALL report that card as Unlimited in that format.
   - Acceptance check: a card absent from a format's ban data reports Unlimited rather than an unknown or missing status.
4. `R6.AC4` WHERE a format's ban data is not provided by the upstream source, the system SHALL allow the user to record and amend that format's ban statuses locally.
   - Acceptance check: a ban status entered by hand for such a format is reported for that card afterwards and survives a restart.
5. `R6.AC5` WHEN a catalog update replaces upstream ban data, the system SHALL retain the user-recorded ban statuses for formats the upstream source does not provide.
   - Acceptance check: after an update, hand-entered statuses for a non-provided format are unchanged while provided formats reflect the new upstream data.
6. `R6.AC6` The system SHALL report the maximum permitted copies implied by each ban status as three for Unlimited, two for Semi-Limited, one for Limited and zero for Forbidden.
   - Acceptance check: for a card of each status, the reported copy allowance matches that mapping.

### R7 Artwork identifier resolution

**User Story:** As a duelist importing deck files produced by other tools, I want alternate-artwork passcodes to be recognised as the cards they depict, so that imported decks are not missing cards.

#### Acceptance Criteria

1. `R7.AC1` WHEN the catalog is acquired or updated, the system SHALL persist every artwork identifier together with the card it depicts.
   - Acceptance check: a card known to have three artworks stores three identifiers, all resolving to that one card.
2. `R7.AC2` WHEN the system is given an artwork identifier present in the catalog, the system SHALL return the card it depicts.
   - Acceptance check: an alternate-artwork identifier that differs from its card's primary identifier resolves to that card.
3. `R7.AC3` IF the system is given an identifier absent from the catalog, THEN the system SHALL report it as unresolved rather than returning a card.
   - Acceptance check: an identifier that exists in no record yields an explicit unresolved outcome, never an arbitrary or nearest card.

### R8 Schema migration and data safety

**User Story:** As the sole owner of my deck and collection data, I want schema upgrades to be recoverable, so that an application update can never leave me with an unusable or half-migrated database.

#### Acceptance Criteria

1. `R8.AC1` WHEN the application starts and the stored schema version precedes the current one, the system SHALL copy the database file to a backup location before applying any migration.
   - Acceptance check: after a start that migrates, a backup file exists whose contents match the pre-migration database.
2. `R8.AC2` WHEN all pending migrations apply successfully, the system SHALL record the current schema version.
   - Acceptance check: a subsequent start with no new migrations applies none and creates no further backup.
3. `R8.AC3` IF a migration fails, THEN the system SHALL restore the backup and report the failure rather than starting against a partially migrated database.
   - Acceptance check: with a deliberately failing migration, the database after the attempt is byte-identical to the backup and the failure is surfaced.

## Non-Functional Requirements

- `NFR1` Search responsiveness: a search or filter query over the full catalog returns its first page of results within 100 ms on the target machine. Bridged by `R5.AC1`, `R5.AC3` and `R5.AC6`, whose acceptance checks are measured under this budget.
- `NFR2` Browsing smoothness: scrolling the card grid over the full catalog sustains the display's refresh rate without dropped frames. Bridged by `R4.AC1` and `R4.AC4`, which require artwork to come from local storage and retrieval to stay off the interaction path.
- `NFR3` Storage budget: the thumbnail store stays at or below 500 MB for the full artwork set, and the catalog database stays at or below 250 MB. Bridged by `R4.AC2` and `R4.AC9`.
- `NFR4` Offline operation: every behaviour in `R3` through `R8`, excluding retrieval itself, functions with no network connection. Bridged by the blocked-traffic acceptance checks on `R2.AC5`, `R3.AC5`, `R4.AC1` and `R5.AC6`.
- `NFR5` Upstream courtesy: outbound request pacing stays below the upstream limit at all times, including during concurrent catalog and artwork retrieval. Bridged by `R4.AC8`.
- `NFR6` Accessibility: the search field, filter controls and card grid are reachable and operable by keyboard alone, and every card element exposes its name and card type to assistive technology. Bridged by `R4.AC7`, which requires a named element even with no artwork.
- `NFR7` Concurrency safety: the application builds and runs under Swift 6 strict concurrency checking with no data-race diagnostics suppressed.

## Constraints And Dependencies

- `C1` The upstream API forbids serving its images directly and blacklists offending clients; artwork must be downloaded and served locally.
- `C2` The upstream API permits 20 requests per second and bans a client for one hour on violation. The application targets at most 10 per second to keep margin.
- `C3` The upstream API provides ban data for TCG, OCG and GOAT only. Edison and Master Duel expose format membership but no ban list, so those two formats depend on user-recorded data (`R6.AC4`).
- `C4` The Italian dataset covers 11,599 of 14,566 cards. English fallback is mandatory, not optional (`R3.AC3`).
- `C5` No official Konami API exists. YGOPRODeck is the sole practical source and a single point of dependency.
- `C6` Target platform is macOS 27 on arm64, built with Swift 6.4 and Swift Package Manager. Xcode is being installed and is not yet available on this machine.
- `C7` All card names, text and artwork are copyright Konami Digital Entertainment and are stored for personal local use only.
- `C8` The application serves one local user. There is no account system, no server component and no telemetry.

## Out Of Scope

- Deck creation, editing, validation and the `.ydk` / YDKe interchange formats — covered by the `deck-builder` specification, which consumes `R6` and `R7`.
- Tracking which physical cards the user owns, per printing — covered by the `collection-tracker` specification.
- Deck statistics, draw probability and opening-hand simulation — covered by the `deck-analytics` specification.
- Presenting prices and computing collection or deck value — covered by the `pricing` specification. This feature only persists the price rows that arrive with the card dataset (`R1.AC5`).
- Languages other than Italian and English, although the upstream source also offers French, German and Portuguese.
- Cloud synchronisation, multi-device use, multi-user accounts and any iOS or iPadOS target.
- Deck sharing, publication or any outbound distribution of catalog data.
