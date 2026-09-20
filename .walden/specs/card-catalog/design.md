---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-19T17:26:49Z
last_modified: 2026-09-19T17:26:49Z
approved_fingerprint: sha256:3c24832766ac1b1caf5482255872c86cde9c060f39d2ff48633687eda5dd5128
source_requirements_approved_at: 2026-09-19T17:16:14Z
source_requirements_fingerprint: sha256:22b95dd0c20c807a8e0ca98575d5e47b179fd4aa45b93c5b44cab5af0300f54c
---

# Feature Design

## Architecture

The catalog is a local SQLite database plus a local artwork directory, both owned by this feature and read by every later feature through protocols declared in `YGOCore`.

### Module graph

```
App (composition root, @MainActor)
 └─ YGOFeatureBrowser ──┐
                        ├─▶ YGOCore   (domain types + protocols, no dependencies)
 YGOSync ───────────────┤
 YGOPersistence ────────┤
 YGONetworking ─────────┤
 YGOImageStore ─────────┘
 YGODesignSystem ─▶ (no domain dependency)
```

`YGOCore` declares `CardRepository`, `CatalogSyncing`, `ArtworkProviding` and `BanListEditing`. `YGOFeatureBrowser` depends only on those protocols, so it compiles and tests without SQLite or URLSession. The composition root is the only place that binds protocols to `YGOPersistence` / `YGOSync` / `YGOImageStore` implementations.

<!-- assumed: one database file rather than separate catalog and user-data files (source: requirements R8.AC1, which speaks of "the database file" singular, and the need for a real foreign key from the later deck_slot table to card) -->

### Startup flow

1. `DatabaseBootstrapper` (in `YGOPersistence`) opens the store, backs up and migrates if the stored schema version precedes the current one (`R8`), and yields a `DatabasePool`.
2. `CatalogSynchronizer` (an `actor` in `YGOSync`) reads `sync_state`. Empty catalog goes to the seed path (`R1`); a populated catalog goes to the version-check path (`R2`).
3. Every outbound request, from both the JSON client and the image fetcher, passes through one shared `RateLimiter` actor (`R4.AC8`, `C2`).
4. `ArtworkPrefetcher` (an `actor` in `YGOImageStore`) starts after a successful seed, enumerates artwork identifiers absent from the store, and fills them as background work (`R4.AC2`–`R4.AC5`).
5. `YGOFeatureBrowser` reads through `CardRepository` only, and never observes sync state except as a progress banner.

### Concurrency

`DatabasePool` in WAL mode: reads proceed concurrently with the seed or update write, which is what keeps the browser responsive during retrieval (`R4.AC4`, `NFR2`). Synchronisation, rate limiting and the artwork store are actors; view models are `@Observable` and `@MainActor`. Strict concurrency stays on (`NFR7`).

## Data Model

Schema version `v001_initial_catalog`. SQLite table and column names are `snake_case`.

```sql
card(id INTEGER PRIMARY KEY, name_en, desc_en, name_it, desc_it,
     type, frame_type, race, attribute, level, atk, def,
     link_value, link_markers, pendulum_scale, archetype,
     has_effect, tcg_date, ocg_date, konami_id, md_rarity)

card_artwork(artwork_id INTEGER PRIMARY KEY,
             card_id INTEGER NOT NULL REFERENCES card(id) ON DELETE CASCADE,
             ordinal INTEGER NOT NULL)

card_fts  -- FTS5, content='card', content_rowid='id',
          -- columns (name_en, desc_en, name_it, desc_it),
          -- tokenize = "unicode61 remove_diacritics 2"

card_format(card_id REFERENCES card(id) ON DELETE CASCADE,
            format_code TEXT, PRIMARY KEY(card_id, format_code))

ban_status(card_id REFERENCES card(id) ON DELETE CASCADE,
           format_code TEXT,
           status TEXT CHECK(status IN ('forbidden','limited','semi_limited')),
           source TEXT CHECK(source IN ('upstream','user')),
           PRIMARY KEY(card_id, format_code))

card_print(id INTEGER PRIMARY KEY, card_id REFERENCES card(id) ON DELETE CASCADE,
           set_code, set_name, rarity, rarity_code, set_price)

card_price(card_id REFERENCES card(id) ON DELETE CASCADE,
           source TEXT, value REAL, observed_at TEXT,
           PRIMARY KEY(card_id, source))

artwork_cache(artwork_id INTEGER, variant TEXT CHECK(variant IN ('thumb','full')),
              byte_size INTEGER, stored_at TEXT, PRIMARY KEY(artwork_id, variant))

sync_state(id INTEGER PRIMARY KEY CHECK(id = 1),
           catalog_version, upstream_updated_at, last_sync_at)
```

Three columns carry design weight:

- **`card_artwork`** is what makes `R7` a lookup rather than a heuristic. Confirmed against live data: `Blue-Eyes Ultimate Dragon` publishes three artwork identifiers for one card.
- **`ban_status.source`** is what makes `R6.AC5` a one-line operation: an update deletes only `WHERE source = 'upstream'`, so hand-entered Edison and Master Duel statuses survive untouched (`C3`).
- **`artwork_cache`** turns the resume in `R4.AC5` into an anti-join against `card_artwork` instead of fourteen thousand filesystem probes.

Absence of a `ban_status` row for a card in a format it belongs to means Unlimited (`R6.AC3`); the upstream source only publishes the three restricting statuses, so storing Unlimited explicitly would add ~14,300 rows carrying no information.

Artwork files live outside the database at `Application Support/YGODeckManager/Artwork/{thumb|full}/{low byte of id, two hex digits}/{artwork_id}.jpg`. The shard keeps directory sizes near sixty entries.

The Italian dataset is joined on the card identifier, which it carries, rather than on `name_en`; verified against the live endpoint.

## Options Considered

1. **GRDB over SwiftData.** SwiftData has no full-text search, so `R5.AC1` would become a hand-rolled index, and its bulk-insert throughput would make the single-transaction seed of `R1.AC2` slow. GRDB gives FTS5, explicit versioned migrations for `R8`, and in-memory databases for tests. Cost: one external dependency. Verified compatible — GRDB 7.11.1 requires Swift 6.1+ and macOS 10.15+.
2. **One database file over a split catalog/library pair.** A split would let a corrupt catalog be discarded without touching irreplaceable deck and collection data. It would also forfeit a real foreign key from the future `deck_slot` to `card`, and force `ATTACH` for ordinary joins. `R8`'s backup-and-restore already contains the risk the split was meant to address. Revisit only if catalog rebuild time becomes a user-visible problem.
3. **Artwork as files over SQLite blobs.** 350 MB of thumbnails inside the database would breach the 250 MB database budget in `NFR3`, make the `R8.AC1` backup copy enormous, and make `R4.AC9` a vacuum instead of a directory removal. Files also let the image decoder memory-map.
4. **Download at first launch over a bundled prebuilt database.** A bundled database would make first launch instant, but `R1.AC1` requires retrieval, a bundled snapshot would be stale on the day it ships, and `R2`'s update path would still be needed in full. It only adds a build-time generator.
5. **bm25 column weights over a two-pass query.** `R5.AC2` needs name matches ahead of effect-text matches. Weighting the two name columns far above the two description columns in `bm25` gets that ordering from the single `MATCH` query already required by `R5.AC1`, instead of running one query per field and merging.

## Simplicity And Elegance Review

What keeps this small:

- One `RateLimiter` actor is the single place that can violate `C2`. Pacing logic does not appear in the JSON client or the image fetcher.
- An FTS5 external-content table stores no duplicate text and is maintained by triggers, so `R5.AC1` is one `MATCH` and there is no index to keep in sync by hand.
- Seed and update are the same code path with a different starting condition, so `R1.AC2` and `R2.AC7` are satisfied by one transaction boundary rather than two rollback strategies.
- The browser feature's only seam is `CardRepository`. There is deliberately no service layer between repository and view model; it would add a file per query and no decision.

Challenged once: a single module holding everything would mean fewer files. Rejected because the module boundary is what makes `NFR7` tractable — networking and persistence can be actor-isolated without dragging UI types into the same isolation domain — and because `deck-builder`, `collection-tracker` and `deck-analytics` need `YGOCore` without inheriting URLSession and SQLite.

## Failure Modes And Tradeoffs

| Failure | Containment |
| --- | --- |
| Upstream unreachable on first launch | Catalog stays empty; retryable error surfaced (`R1.AC4`) |
| Upstream unreachable later | Version check fails, application runs on the stored catalog (`R2.AC5`) |
| Process dies mid-seed | Single transaction rolls back; no partial catalog (`R1.AC2`) |
| Upsert fails mid-update | Same transaction boundary restores the prior catalog (`R2.AC7`) |
| Rate-limit ban, one hour | Shared limiter runs at half the published ceiling; an HTTP 429 halts the limiter, and sync reports a blocked state rather than retrying into a longer ban |
| Artwork files removed out of band | A read miss re-fetches and repairs `artwork_cache`, rather than a startup scan |
| Migration fails partway | File-level backup restored, since a migrator chain cannot roll back migrations already committed (`R8.AC3`) |
| Upstream renames or drops a field | Decoding ignores unknown fields and tolerates missing optional ones; a missing required field aborts the transaction, leaving the prior catalog intact |
| Italian dataset out of step with English | Join on card identifier; Italian rows for unknown cards are discarded and English remains authoritative for a card's existence |

Accepted tradeoffs:

- **Full re-download on any version change.** The upstream source publishes no delta endpoint, so a version bump costs 41 MB across both languages. Diffing logic would cost more than the bandwidth saves.
- **`artwork_cache` may drift from disk.** Repaired lazily on read miss. A startup reconciliation would cost roughly fourteen thousand filesystem probes for a condition that only arises when files are deleted behind the application's back.
- **Edison and Master Duel ban data cannot be guaranteed current.** It is user-entered because upstream does not publish it (`C3`). The interface must show when such a list was last edited rather than implying authority.
- **Prices are stored per card, not per printing.** Upstream publishes them that way. Per-printing valuation in the later `pricing` specification will therefore be an approximation, and must be presented as one.
- **Single upstream dependency.** `C5` has no mitigation available; the containment is that the application is fully functional offline once seeded (`NFR4`), so an upstream outage degrades freshness, never usability.

## Verification Plan

Tests live in a test target per package. Database tests run against an in-memory GRDB database. Network tests run against recorded JSON fixtures captured from the live endpoints and stored under `fixtures/`; no test contacts a live host, per the project constitution.

| Check | Observation that decides it |
| --- | --- |
| Seed atomicity | A persistence error injected after part of the dataset is written leaves a stored card count of zero |
| Seed completeness | Stored card count equals the count in the fixture dataset, and a second run issues no dataset request |
| Version skip | With a stubbed version response equal to the stored version, the dataset endpoint records zero requests |
| Version change | With an older stored version, a changed field in the fixture is reflected and unrelated cards keep their stored values |
| Update rollback | An error injected during upsert leaves card count, card values and stored version byte-identical to the pre-update state |
| Offline start | A client stubbed to throw yields a ready application state and a non-empty search result from the stored catalog |
| Bilingual display | A fixture with one translated and one untranslated card yields Italian text for the first and complete English text plus an untranslated marker for the second |
| Language switch | Changing language with a throwing client changes displayed text and records zero requests |
| Diacritic-insensitive search | The query `avidita` returns the card whose Italian name is `Anfora dell'Avidità`; the tokenizer behaviour was confirmed on system SQLite 3.45.3 |
| Cross-language search | An Italian-only substring and an English-only substring each return the same card |
| Result ranking | A query that is an exact card name and also a common phrase in other cards' effect text places the exactly named card first |
| Filter conjunction | Every card in a combined filter result independently satisfies each applied filter, and a jointly unsatisfiable pair returns none |
| Filter removal | Removing one filter yields exactly the set the remaining filters produce alone |
| Local-only queries | With the client stubbed to throw on every call, every search and filter case returns its full expected set |
| Rate limiting | One hundred requests driven through a virtual clock contain no one-second window exceeding ten |
| Artwork locality | With the image fetcher stubbed to throw, stored artwork still resolves and absent artwork yields a named placeholder |
| Prefetch resume | After an interruption at a known partial count, the next run requests exactly the missing identifiers |
| Artwork purge | After the purge operation the artwork directory is empty and stored card count is unchanged |
| Alias resolution | The three artwork identifiers of a multi-artwork fixture card all resolve to one card, and an absent identifier yields an unresolved outcome |
| Ban status mapping | Cards of each stored status report copy allowances of zero, one and two, and a card with no row reports three |
| Ban preservation | A user-entered Edison status survives an update that replaces every upstream status |
| Migration backup | After a migrating start, a backup file exists whose hash matches the pre-migration database |
| Migration failure | With a deliberately failing migration, the post-attempt database hash equals the backup hash and the failure is reported |
| Search latency | Measured p95 over a full-size catalog stays under 100 ms |
| Storage budget | Database size after a full seed stays at or below 250 MB, and the thumbnail directory at or below 500 MB |
| Concurrency | The package builds under Swift 6 strict concurrency with no data-race diagnostics |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `CatalogSynchronizer` seed path and `CatalogWriter`'s single transaction; seed atomicity, seed completeness and offline-start checks |
| `R2` | `CatalogSynchronizer` version-check path against `sync_state`; version skip, version change, update rollback and offline-start checks |
| `R3` | Dual-language columns on `card` joined by identifier, plus `CardPresentation` fallback; bilingual display and language switch checks |
| `R4` | `ArtworkStore` directory layout, `artwork_cache` presence table, `ArtworkPrefetcher` and the shared `RateLimiter`; artwork locality, prefetch resume, artwork purge and rate-limiting checks |
| `R5` | `card_fts` external-content table with weighted `bm25`, plus the filter query builder in `CardRepository`; diacritic, cross-language, ranking, filter conjunction, filter removal and local-only checks |
| `R6` | `card_format` and `ban_status` with its `source` column; ban status mapping and ban preservation checks |
| `R7` | `card_artwork` table and `resolveArtwork`; alias resolution check |
| `R8` | `DatabaseBootstrapper` backup-then-migrate sequence over `DatabaseMigrator`; migration backup and migration failure checks |
| `NFR1` | Indexed filter columns and a single FTS query per search; measured p95 search latency |
| `NFR2` | `DatabasePool` WAL reads concurrent with sync writes, artwork served from disk; responsiveness observed during the prefetch-resume check |
| `NFR3` | Artwork stored outside the database as files; measured database and thumbnail directory sizes |
| `NFR4` | Every repository query resolved locally; the throwing-client variants of the offline-start, language-switch and local-only checks |
| `NFR5` | Single shared `RateLimiter` actor ahead of both clients; virtual-clock rate-limiting check |
| `NFR6` | Keyboard-reachable search field, filter controls and grid, plus named placeholders from `R4.AC7`; accessibility-label assertions on the browser view |
| `NFR7` | Actor isolation for synchronisation, rate limiting and artwork; strict-concurrency build check |
