---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T07:42:13Z
last_modified: 2026-09-21T07:42:13Z
approved_fingerprint: sha256:bf162521c06d8d63016f6c74e38b9a4ebd6baa8b49d24eeac6ac75fe0904d8fa
source_requirements_approved_at: 2026-09-21T07:42:13Z
source_requirements_fingerprint: sha256:fa8df22d60842528f7d4f9693f093f5921d7050dae2d9c1e1016e44f37e7c20d
---

# Feature Design

## Architecture

A second upstream, stored in the same database and queried as a timeline. Nothing about the card catalog changes, and neither source can break the other.

### Module graph

```
App ─▶ (card-detail, later) ─┐
                             ├─▶ YGOCore        (revision, entry, timeline)
YGOBanlistHistory (timeline) ┤
YGONetworking (the client) ──┤
YGOPersistence (the store) ──┘
```

`YGOBanlistHistory` builds a timeline from rows and depends on `YGOCore` alone, so every question in `R2` and `R3` is arithmetic over a list of dated statuses and is checkable without a database.

### Enumerating the lists costs a second host

The source documents only `current.vector.json` and `upcoming.vector.json`. The dated files exist and are served — `tcg/2005-03-01.vector.json` returns them — but nothing publishes an index of them.

So the dates are enumerated through the GitHub contents API and the bodies fetched from GitHub Pages. That is two hosts for one source, and it is worth naming rather than discovering later:

- `api.github.com` lists `data/<format>`, four calls, rate-limited to **60 an hour unauthenticated**. Four is comfortable; a retry loop would not be.
- `dawnbrandbots.github.io` serves the bodies, 2.5 KB each, no limit that matters at 177 files.

The dated paths are not part of the documented surface. If they stop being served, enumeration still succeeds and every body fails, which `R1.AC5` turns into keeping what is already stored.

<!-- assumed: enumeration through the GitHub contents API rather than a bundled list of dates (source: R1.AC1 requires every published list, which a list frozen at build time cannot promise) -->

### `current` is a symlink, not a list

Each directory holds `current.vector.json` pointing at the newest effective list, and the body carries its own `date`. It is therefore skipped during enumeration and the dated file it points at is fetched instead, so one list is not stored twice under two names.

`upcoming.vector.json` appears when a list has been announced but has not taken effect. None exists today. It is skipped for the same reason and because a list that is not yet in force is not history.

### Entries are keyed by `konami_id`, not by card

A list names cards the catalog may not hold: 203 of 14,566 cards carry no `konami_id`, and a list can name a card released since the last catalog sync.

Storing the identifier the source published, rather than resolving it to a card at write time, means a later catalog update makes previously unmatched entries answerable without re-fetching anything. `R1.AC6` reports how many could not be matched **at that moment**, which is a different and more useful statement than silently dropping them.

## Data Model

Migration `v005_banlist_history`.

```sql
banlist_revision(
    id INTEGER PRIMARY KEY,
    format_code TEXT NOT NULL,
    effective_date TEXT NOT NULL,
    source TEXT NOT NULL,
    fetched_at TEXT NOT NULL,
    UNIQUE(format_code, effective_date))

banlist_entry(
    revision_id INTEGER NOT NULL REFERENCES banlist_revision(id) ON DELETE CASCADE,
    konami_id INTEGER NOT NULL,
    status TEXT NOT NULL
        CHECK(status IN ('forbidden','limited','semi_limited')),
    PRIMARY KEY(revision_id, konami_id))

CREATE INDEX banlist_entry_konami_idx ON banlist_entry(konami_id)
CREATE INDEX banlist_revision_format_idx ON banlist_revision(format_code, effective_date)
```

Three choices carry weight:

- **`UNIQUE(format_code, effective_date)`** makes `R1.AC4` a matter of asking which dates are already held. A second synchronisation fetches nothing because there is nothing new to fetch, rather than fetching and discarding.
- **No `unlimited` status.** The source encodes 0, 1 and 2 and says nothing about the rest; a card absent from a list was unrestricted on it. Storing fourteen thousand explicit "unlimited" rows per list would be a quarter of a million rows carrying no information.
- **`source` on the revision**, not in a constant. `R4.AC1` requires a history to name where it came from, and a row that knows its own origin survives a second source being added later.

The existing `ban_status` table is untouched. It holds the catalog's current view, is already certified, and `R4.AC3` exists precisely to report when the two disagree rather than to reconcile them.

## Options Considered

1. **A second source at all, rather than none.** The catalog publishes three current statuses and no history; both a dedicated endpoint and a date parameter were tried and returned 404 and 400. Without a second source the feature is impossible, so the question was whether the cost is acceptable: 0.43 MB, 177 files, and a project whose current list agreed with the catalog on all 222 cards they both describe.
2. **Enumerating over bundling.** A list of dates compiled into the application would avoid the GitHub API entirely. It would also be wrong the first time a new list is published, and `R1.AC1` asks for every published list rather than every list known at build time.
3. **Keying entries by `konami_id` over resolving to a card.** Resolving at write time would make queries a plain join. It would also discard entries for cards the catalog has not yet caught up with, and re-fetching would be the only way to recover them.
4. **Leaving `ban_status` alone.** The newest historical list could replace it, removing a duplication. It would also change what a certified specification stores, on the strength of a source that has been agreeing for one day.
5. **Timeline built in memory over a SQL window function.** A window query would compute the changes in the database. The card's history is at most 73 rows; walking them in Swift is simpler to read, testable without a database, and indistinguishable in speed at that size.

## Simplicity And Elegance Review

What keeps this small:

- A timeline is a list of dated statuses, and the changes are the places where consecutive entries differ. `R2.AC4` is one pass over what `R2.AC1` already produced, not a second query.
- Absence carries the meaning the source gives it. Nothing writes an "unlimited" row, so nothing has to keep a quarter of a million of them in step with the catalog.
- One synchroniser fetches whatever the enumeration returned minus what is already stored. There is no incremental cursor, because the set of dates is the cursor.
- The release date `R2.AC3` needs is already on the card. No new column, no second fetch.

Challenged once: this could have been folded into `card-catalog`, which already synchronises an upstream. Rejected because that specification's synchroniser has one source, one version stamp and one transaction, and a second source with its own availability would make every failure mode in it conditional.

## Failure Modes And Tradeoffs

| Failure | Containment |
| --- | --- |
| The banlist source is unreachable | Stored history still answers everything; the catalog is untouched (`R1.AC5`, `NFR2`) |
| The GitHub API rate limit is reached | Four calls against sixty an hour; on refusal the synchronisation stops and keeps what is stored |
| The undocumented dated paths stop being served | Enumeration succeeds and bodies fail, which is the same containment as unreachable |
| A list names a card the catalog lacks | Stored under its `konami_id` and counted as unmatched; answerable once the catalog catches up (`R1.AC6`) |
| A card has no `konami_id` | It has no history, and 203 cards are in this position (`C2`) |
| The two sources disagree | Reported, never reconciled (`R4.AC3`) |
| A list is republished with corrected contents | The date is the key, so a re-fetch replaces that revision's entries rather than adding a second revision |

Accepted tradeoffs:

- **A third host to depend on.** Enumeration and bodies come from different services of the same project. Both are named in `C1` rather than discovered from a failure.
- **Dated paths are undocumented.** They are served today and the project's own data directory is their source of truth. The containment is that losing them degrades to no new history rather than to broken history.
- **TCG dates are European.** The source takes the EMEA effective date, so the April 2024 list is dated 2024-04-22 rather than the American 2024-04-15. For a user in Italy that is the correct date, and it is recorded so nobody later "fixes" it.
- **History does not affect legality.** A deck is judged against the current list for its format. Changing that would alter a contract `deck-builder` holds and is out of scope by decision, not oversight.

## Verification Plan

The timeline is tested as arithmetic over dated statuses with no database. Acquisition is tested against recorded copies of real lists, never a live host. The figures below come from the published data and were checked before any code existed.

| Check | Observation that decides it |
| --- | --- |
| Every list acquired | Stored revision count per format matches what the enumeration returned |
| Date and format recorded | A stored revision reports both; two formats sharing a date stay distinct |
| Entries stored | The 2005-03-01 TCG list stores 77 entries: 18 forbidden, 44 limited, 15 semi-limited |
| `current` not stored twice | Enumeration skips the symlink; the newest dated list appears once |
| Second synchronisation | With nothing new published, no body is fetched and stored entries are unchanged |
| Source unreachable | Stored history answers every question; the catalog's own tests still pass |
| Unmatched entries | A list holding one identifier the catalog lacks stores the rest and reports one unmatched |
| Card history in order | A card restricted since 2005 reports one entry per list from that date, oldest first |
| Absence means unrestricted | A card absent from a list reports unrestricted for it rather than being omitted |
| Absence before release | A card released in 2015 reports nothing for lists published before it |
| Changes reported | Forbidden in 2005 and unrestricted in 2015 reports exactly two changes, with dates |
| Never restricted | A card on no list reports no changes and an explicit never-restricted answer |
| A whole list | The 2005-03-01 TCG list reports its 77 cards with statuses and names |
| Lists in order | TCG revisions run from 1999-08-01 to the newest with no gaps against the enumeration |
| Difference between lists | Two consecutive lists report exactly the cards whose status differs, added and dropped included |
| Source named | A reported history names its source, which is not the catalog's |
| Freshness reported | A history carries its own last synchronisation, independent of the catalog's |
| Disagreement reported | A card whose newest historical status differs from the catalog's is reported, naming both |
| History latency | A card's full history in one format is produced within 20 ms |
| Independence | The catalog's proofs pass with the banlist source unreachable, and vice versa |
| Offline | Every question in R2 and R3 answers with no network |
| Concurrency | The new module builds under Swift 6 strict concurrency with no data-race diagnostics |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `YAMLYugiBanlistClient` enumerating through the contents API and fetching bodies from Pages, into `banlist_revision` and `banlist_entry`; the seven acquisition checks |
| `R2` | `BanlistTimeline` walking a card's dated statuses in `YGOBanlistHistory`; the five history checks |
| `R3` | Revision and entry queries in `SQLiteBanlistHistory`; the whole-list, ordering and difference checks |
| `R4` | `source` and `fetched_at` on the revision, and a comparison against `ban_status`; the three honesty checks |
| `NFR1` | An index on `konami_id` and at most 73 rows per card; measured latency |
| `NFR2` | Separate client, separate tables, separate synchronisation; the independence check |
| `NFR3` | Every query resolved from stored rows; the offline check |
| `NFR4` | Source and freshness carried by the revision; the three `R4` checks |
| `NFR5` | Value types and a pure timeline builder; the strict-concurrency build check |
