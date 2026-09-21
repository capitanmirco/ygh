---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T08:49:38Z
last_modified: 2026-09-21T08:49:38Z
approved_fingerprint: sha256:4fe9d2911cc48cfcee5108c7c697defceb79339fec11c533ee941a85db16d9ee
source_requirements_approved_at: 2026-09-21T08:49:38Z
source_requirements_fingerprint: sha256:bf93d013d7466e4bd8e735ac812d3a33b176694ccfa6c6d4030856458722b742
---

# Feature Design

## Architecture

Two halves that meet only at a selected card: the grid learns to page and to narrow as you type, and a new panel assembles what five certified specifications already store.

```
YGOFeatureBrowser ──selection──▶ YGOFeatureCardDetail
        │                                │
        └──────────▶ YGOCore ◀───────────┘
                       ▲
   YGOPersistence ─────┴───── YGOBanlistHistory, YGOPricing
```

`YGOFeatureCardDetail` is new and depends on `YGOCore` protocols alone, so the whole panel is provable against stubs: no SQLite, no network, no view.

### The panel is an assembly, not a query

Seven pieces make a detail, and six of them already exist:

| Piece | Comes from |
| --- | --- |
| Name, type, effect, artworks | `Card`, already carrying both languages and `isFallbackToEnglish` |
| Current status | `CardRepository.banStatus(for:in:)` |
| Prices | `PriceLookup` |
| Restriction history | `BanlistHistoryReading` plus `BanlistTimelineBuilder` |
| Disagreement between sources | `BanlistProvenanceReporting` |
| Printings | **new** read |
| Copies owned, decks using it, release dates | **new** reads |

`CardDetailLoader` fans out to these and returns one `CardDetail`. The alternative — each section fetching itself when its view appears — would give seven independent loading states and no way to say what failed, and would make `R2.AC7` (selecting another card without disturbing the grid) a race between seven cancellations instead of one.

### Absence is a case, not a nil

Six of the twenty-nine criteria are about saying that something is missing, and the measurements say why: 2,981 cards untranslated, 85 with no release date, 552 with no printing, 289 with no price, an empty collection, 203 cards with no `konami_id`.

So each section of `CardDetail` is an enum with an explicit absent case carrying its reason, rather than an optional the view has to interpret. A view cannot render "no printing recorded" as an empty table by forgetting a branch, because there is no branch to forget.

Two absences that read alike and are not: a card never restricted, and a card whose history cannot be looked up at all. `R5.AC3` and `R5.AC4` are separate cases in the type for that reason.

### Release dates are read, not added to `Card`

The catalog stores `tcg_date` and `ocg_date`; the `Card` type exposes neither. Widening `Card` would touch a type five certified specifications construct, for two fields only this panel reads. The loader reads them alongside the printings instead.

<!-- assumed: release dates read by the detail loader rather than added to Card (source: card-catalog's approved design, where Card carries what search and deck building need) -->

### Counting is a second statement, not a second builder

`R1.AC4` needs how many cards match, and the search returns at most 200. The same `CardQueryBuilder` emits a counting statement: the same joins and the same conditions, `SELECT COUNT(*)`, and **no ordering and no paging**.

Dropping the ordering matters. Ordering carries bound arguments in this builder, and the lesson recorded against `card-catalog` was exactly this: arguments appended in construction order rather than placeholder order bind silently to the wrong slots and return a plausible wrong answer instead of an error. The counting statement must drop the ordering arguments with the ordering clause.

### Narrowing as you type is latest-wins, not a timer

An unnarrowed query costs 3.9 ms and the count 0.1 ms, so there is nothing to protect the database from. What costs is presenting 200 tiles, each resolving an artwork path.

So each change to the query text starts a load that supersedes the one before it: the previous is cancelled, and a result that arrives for superseded text is discarded rather than shown. A debounce timer would add latency to every keystroke to solve a problem the measurements do not show.

## Data Model

**No new tables and no migration.** Three new read shapes over tables that already exist:

```sql
-- Printings (R3.AC1), 44,491 rows across 14,014 cards
SELECT set_name, set_code, rarity, set_price FROM card_print
WHERE card_id = ? ORDER BY set_name

-- Release dates (R2.AC4), read with the printings
SELECT tcg_date, ocg_date FROM card WHERE id = ?

-- Decks using a card, by section (R4.AC3, R4.AC4)
SELECT d.id, d.name, s.section, s.quantity
FROM deck_slot s JOIN deck d ON d.id = s.deck_id
WHERE s.card_id = ? ORDER BY d.name, s.section

-- Copies owned and where (R4.AC1)
SELECT e.quantity, e.condition, l.name
FROM collection_entry e
LEFT JOIN storage_location l ON l.id = e.location_id
WHERE e.card_id = ? ORDER BY l.name
```

The existing `CollectionWriting.entries(forCard:)` returns a location identifier and not its name, which is why holdings are read here rather than reused.

The aggregate:

```swift
public struct CardDetail: Sendable {
    let card: Card
    let language: CardLanguage
    let release: ReleaseDates          // .known(tcg:ocg:) | .unknown
    let printings: Section<[Printing]> // .none carries "no printing recorded"
    let prices: [PriceSource: Money?]  // nil is unpriced, never zero
    let holdings: Section<[Holding]>
    let deckUsage: Section<[DeckUse]>
    let history: History               // .timeline | .neverRestricted | .unavailable
    let disagreement: Disagreement?
}
```

`Section<T>` is `.loaded(T)`, `.empty(reason:)` or `.failed(reason:)`. A section that could not be read says so; it does not take the whole panel down with it.

## Options Considered

1. **Inspector column over a sheet or a full page.** Chosen by the user. It keeps the grid visible, so selecting a second card is one click rather than close-and-click, which is what `R2.AC7` is protecting. A sheet would give more room for the 78 printings of Blue-Eyes White Dragon; a scrollable column gives enough.
2. **200 at a time over the whole catalog.** Chosen by the user. Showing 14,566 live tiles to satisfy "show me all the cards" would hold 417 MB of thumbnails in reach of the layout; 200 with a stated total answers the same question honestly.
3. **One aggregate load over seven section loads.** Seven would let each section appear as it arrives. It would also produce seven loading states, seven cancellations on `R2.AC7`, and no single answer to "what is missing". The panel loads once and reports per section.
4. **Reading release dates over widening `Card`.** Widening would be tidier at the call site and would touch a type five certified specifications construct, for two fields one panel reads.
5. **A new counting port over extending `CardSearching`.** Extending the certified protocol would break every existing conformance, including the stubs the offline proofs are built on. A separate `CardSearchCounting` leaves them untouched.
6. **Latest-wins cancellation over a debounce timer.** A timer delays every keystroke by its interval. Cancellation costs nothing when the user stops typing and discards what is already stale.

## Simplicity And Elegance Review

What keeps this small:

- Nothing is stored. No table, no migration, no cache to invalidate, no second copy of a price to keep in step.
- The counting statement is the search statement with two clauses removed, so a filter can never narrow the results and not the count.
- The history section is `BanlistTimelineBuilder` called with the card's release date, which is a parameter it already takes. The panel adds no arithmetic.
- `Section<T>` is one generic instead of four bespoke "or empty" types, and it makes the absent case unignorable in every one of them.

Challenged once: the panel could have read from the database directly and skipped the loader. Rejected because that would put SQL behind a view and make `NFR3` — every section offline — provable only by turning off the network rather than by construction.

## Failure Modes And Tradeoffs

| Failure | Containment |
| --- | --- |
| Full artwork absent and unreachable | The thumbnail stays and a placeholder names the card, which `card-catalog` already requires (`C1`) |
| One section's read fails | That section reports itself unavailable; the rest of the panel renders |
| A card has no `konami_id` | History reports unavailable, worded apart from never-restricted (`R5.AC4`, `C3`) |
| The two sources disagree on a status | Both are shown, named; neither is preferred (`R5.AC5`) |
| A page arrives for a query the user has moved past | Discarded; the batch is tagged with the query that asked for it |
| Paging past the end | The advance is refused rather than showing an empty tail |
| A card is in the collection but its location was deleted | The holding reports unfiled, which is what the schema's `ON DELETE SET NULL` already means |
| Prices differ by a hundredfold between sources | Every figure names its source; `pricing` already refuses to average them |

Accepted tradeoffs:

- **The first opening of any card touches the network**, for roughly 138 KB, because no full image is stored. Everything else in the panel is already local.
- **Prices describe a card, not a printing** (`C2`). Blue-Eyes White Dragon's 78 printings all carry one figure, and `R3.AC6` requires the panel to say so rather than let the layout imply otherwise.
- **The collection is empty**, so `R4.AC1` is proven against seeded data and only `R4.AC2` is exercised by the live database (`C4`).
- **Two currencies, no conversion** (`C5`). Cardmarket in euro beside four in dollars is harder to scan than one column of numbers, and inventing a rate would be worse.

## Verification Plan

The panel is tested against stub ports, with no database and no network. The grid's paging and narrowing are tested against a repository stub that counts the queries it is asked for. The figures asserted are the ones measured on 2026-09-21.

| Check | Observation that decides it |
| --- | --- |
| Opens showing cards | A freshly opened browser holds results rather than an idle prompt |
| Clearing returns to all | Typing then clearing restores the unnarrowed count |
| Narrows without submitting | Successive text changes produce successive result sets with no submit |
| Counts reported | An unnarrowed browser reports 14,566 matching and 200 shown |
| Next batch | One advance holds 400 cards, same order, no card twice |
| Filters alone | A format filter with empty text lowers the count and every card admitted |
| No matches settled | A query matching nothing reports no matches, distinct from searching |
| Superseded loads | A result arriving for abandoned text never reaches the grid |
| Detail opens beside | Selecting shows the card's detail while the grid keeps its cards |
| Text in language | A translated card reads Italian; switching changes name, type and effect |
| Untranslated marked | An untranslated card reads English and is flagged, not blank |
| Release dates named | Both regions reported when present, each named |
| Release unknown | A card with neither date reports unknown |
| Several artworks | A multi-artwork card offers each; a single-artwork card offers no chooser |
| Selection replaced | A second selection changes the detail, not the grid's order or position |
| Printings listed | Blue-Eyes White Dragon reports 78, each with set, code and rarity |
| No printing | A card with none says so rather than showing an empty table |
| Five figures | A fully priced card reports five, each naming source and currency |
| Unpriced not zero | A partly priced card marks the missing sources unpriced |
| Observation time | The prices carry when they were observed, not when the panel opened |
| Per card not printing | The price section states the limit where printings differ in rarity |
| Copies and locations | A card held in two locations reports both with counts |
| Nothing owned | An empty collection reports no copy held |
| Decks using it | A card in two decks reports both with their counts |
| By section | A card in main and side is reported once per section |
| Current status | A restricted card reports its status; an unrestricted one says so |
| Changes with dates | A card forbidden then freed reports both dates and the statuses either side |
| Never restricted | A card on no list says never restricted |
| History unavailable | A card with no `konami_id` says unavailable, worded apart from never |
| Disagreement shown | A card the sources describe differently shows both, named |
| A section failing | A failing read reports that section unavailable; the others still render |
| Typing latency | Results follow a text change within 150 ms |
| Opening latency | Every stored-data section is ready within 100 ms of selecting |
| Offline | Every section but the full artwork is produced with no network |
| Accessibility | Each figure reads as a sentence naming it and its source; grid, panel and sections are keyboard reachable |
| Concurrency | The new module builds under Swift 6 strict concurrency with no diagnostics |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `BrowserViewModel` opening with a query, latest-wins narrowing, batch advance, and `CardSearchCounting` over the counting statement; the first eight checks |
| `R2` | `CardDetailLoader` and `CardDetailViewModel`, `Card.text(in:)` for the fallback, the release-date read, the artwork chooser; the six opening checks |
| `R3` | The printings read and `PriceLookup`, presented through `Section<T>`; the six printing and price checks |
| `R4` | The holdings and deck-usage reads; the four copy checks |
| `R5` | `BanlistHistoryReading` with `BanlistTimelineBuilder`, and `BanlistProvenanceReporting` for the disagreement; the five history checks |
| `NFR1` | Latest-wins cancellation and a 3.9 ms query; measured typing latency |
| `NFR2` | One aggregate load over local reads; measured opening latency |
| `NFR3` | Every port reading stored rows; the offline check |
| `NFR4` | `Section<T>` and the explicit history cases; the six absence checks |
| `NFR5` | Sentence-forming labels and a keyboard path through grid, panel and sections |
| `NFR6` | Value types and an actor-isolated view model; the strict-concurrency build check |
