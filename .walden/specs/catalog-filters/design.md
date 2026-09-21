---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T13:31:44Z
last_modified: 2026-09-21T13:31:44Z
approved_fingerprint: sha256:89758c4540797ca55fa30c1d4842767f918f974b0766660958240c65bdf12d2a
source_requirements_approved_at: 2026-09-21T13:29:30Z
source_requirements_fingerprint: sha256:ab86a249c22d82525876ed5b7ada5366c940c0001cd2a085a2e2a12b980f7b8b
---

# Feature Design

## Architecture

Three pieces: widen `CardFilters`, teach the query builder the three narrowings it does not know, and give the browser somewhere to put them. Plus the wiring that was never done — nothing in the application constructs the banlist synchroniser, so `R3` has nothing to filter on until `R4` runs.

```
YGOFeatureBrowser ── FilterPanel ──┐
                                   ├─▶ YGOCore (CardFilters, CardType)
YGOComposition ── BanlistSync ─────┤
                                   └─▶ YGOPersistence (CardQueryBuilder)
```

No new module and no new table. The lists already have `banlist_revision` and `banlist_entry` from `banlist-history`, and both indexes they need exist.

### The filters live in a panel that is not always there

Ten filters do not fit in a toolbar, and a permanent third column beside the grid and the detail panel leaves the grid a strip. So the filters are a panel that slides in beside the grid when asked for, and the catalog opens without it.

<!-- assumed: a collapsible leading panel rather than a permanent column or a popover (source: the user asked for the interface to stay clean and ordered; a popover cannot show which filters are applied while the grid updates, which R5.AC2 requires) -->

A popover was the other candidate and fails `R5.AC2`: the applied filters have to stay visible while the results change, and a popover that stays open to show them covers the results it is changing.

### Card type is derived, not stored

The catalog holds seventeen frames. Monster, spell and trap are groupings of them, so `CardType` is a computed property on `CardFrame` rather than a column:

```swift
public enum CardType: String, CaseIterable, Sendable {
    case monster, spell, trap, other
}
```

The filter therefore expands to a set of frames before it reaches SQL, which reuses the frame condition the builder already has. One fewer clause to get wrong.

### "?" is not a number

Attack and defence store `-1` where the card prints "?", on cards whose value is genuinely unknown. A range of 0 to 3000 that admitted `-1` would answer "weak monsters" with monsters nobody can measure.

So every numeric range condition gains `AND column >= 0`, and "?" becomes its own filter rather than a value inside the range. Two questions, two answers: *how strong is it* and *is it knowable*.

### A year range is a string comparison

Release dates are ISO strings, so 2004 to 2005 is `tcg_date >= '2004-01-01' AND tcg_date <= '2005-12-31'`. No new column, no date parsing, and the existing index on the column still applies.

The 523 cards with no date are excluded by the `NULL` comparison, and `R2.AC2` requires saying how many — which is a second count with the year clause dropped, not a guess.

### The published-list filter replaces the status, not just the rows

`R3.AC1` narrows to the cards a list named. `R3.AC2` is the harder half: while that list is chosen, a card's status must be **its status on that list**, not today's.

So the filter adds a join and a projection:

```sql
JOIN banlist_revision r
  ON r.format_code = ? AND r.effective_date = ?
JOIN banlist_entry e
  ON e.revision_id = r.id AND e.konami_id = card.konami_id
```

and the status shown comes from `e.status` rather than from `ban_status`. The two never mix: with a list chosen the grid shows history, and without one it shows the catalog's current view. A screen that blended them would be stating something neither source said.

### Synchronising the lists is wiring, not new behaviour

`banlist-history` proved the synchroniser against recorded lists. What is missing is a caller. `BanlistSyncCoordinator` sits in the composition root beside the catalog's own synchroniser, reports how many lists it has stored, and leaves the catalog answering while it runs — 177 lists at 2.5 KB is under a second of transfer, but the progress is reported rather than assumed instant.

## Data Model

**No schema change.** `CardFilters` gains four fields:

```swift
public struct CardFilters {
    // existing: frames, attributes, races, archetypes, levels,
    //           attack, defense, linkRatings, pendulumScales,
    //           format, banStatuses
    public var cardTypes: Set<CardType> = []
    public var releaseYears: ClosedRange<Int>?
    /// A published list, by format and effective date. Narrows to the cards
    /// it named and shows their status on it.
    public var publishedList: PublishedListSelection?
    /// Cards whose attack or defence prints "?" rather than a number.
    public var unknownStatsOnly = false
    public var ownedOnly = false
}

public struct PublishedListSelection: Hashable, Sendable {
    public let format: BanlistFormat
    public let effectiveDate: String
}
```

And a report of what a narrowing cost:

```swift
public struct FilterOutcome: Sendable {
    let matching: Int          // R5.AC1
    let shown: Int
    let excludedUndated: Int   // R2.AC2
    let unmatchedOnList: Int   // R3.AC5
    let appliedFilters: [String]   // R5.AC2, R5.AC4
}
```

`appliedFilters` holds sentences rather than flags, so `R5.AC4` names what emptied the grid and `NFR4` has something to read aloud.

## Options Considered

1. **A collapsible panel over a permanent column.** A third permanent column leaves the grid a strip at laptop width. A panel that is not there by default keeps the catalog as it is now.
2. **A panel over a popover.** A popover cannot show the applied filters while the grid changes without covering it, and `R5.AC2` needs exactly that.
3. **Card type derived over stored.** A column would be faster by a hair and would be a second source of truth for something the frame already says.
4. **`>= 0` on ranges over filtering `-1` in Swift.** Filtering afterwards means the reported count and the shown rows disagree, which is the failure `R5.AC1` is written against.
5. **String comparison over parsed dates for the year range.** Parsing needs a new column or a function call per row; ISO strings sort correctly as text.
6. **Status from the chosen list over always from `ban_status`.** Showing today's status beside a 2005 list would answer a question nobody asked.
7. **Synchronising on demand over at launch.** 177 files at launch would slow every start for data most sessions do not need; a stated action that reports progress is honest about the cost.

## Simplicity And Elegance Review

What keeps this small:

- No table, no migration, no new module. Three clauses and a panel.
- Card type expands to frames, so it reuses a condition that already works.
- The year range is two string comparisons against a column that is already indexed.
- `FilterOutcome` carries the three numbers the honesty criteria need, so no screen has to compute them a second way.

Challenged once: the published-list filter could have lived in its own screen showing a whole list, which `banlist-history` already answers. Rejected because the user's request was to narrow *the catalog* by a list — the point is finding cards, with the era's rules applied, not reading the list.

## Failure Modes And Tradeoffs

| Failure | Containment |
| --- | --- |
| A range admits "?" | Every numeric range carries `>= 0`; "?" is its own filter (`R1.AC7`, `C2`) |
| A year range silently hides 523 cards | The count is reported beside the results (`R2.AC2`) |
| A list names cards the catalog lacks | The difference is reported rather than showing fewer (`R3.AC5`, `C6`) |
| No list has been downloaded | The chooser says so instead of being empty (`R3.AC4`) |
| Synchronisation fails midway | What was stored stays; the failure is stated (`R4.AC3`) |
| Filters match nothing | The grid says so and names what is applied (`R5.AC4`) |
| Owned-only against an empty collection | Reports that nothing is owned, not an unexplained blank (`R5.AC5`, `C7`) |
| The arguments bind out of order | Each new clause keeps its arguments with it, as `card-catalog`'s lesson requires |

Accepted tradeoffs:

- **Filters are not remembered between sessions.** Out of scope by decision; a saved filter set is a feature with its own questions about naming and sharing.
- **The list filter needs a synchronisation first.** 0.43 MB, once. `R3.AC4` makes the state before it legible rather than broken.
- **A year range and a published list can disagree.** Narrowing to 2004–2005 and to the 2015 list gives nothing, and `R5.AC4` names both rather than leaving the user guessing.
- **Owned-only is useless today.** The collection holds nothing, and the filter says so rather than pretending.

## Verification Plan

The filters are proven against an in-memory database seeded to the shape of the real catalog, including the traps: a card printing "?" for attack, a card with no release date, and a card with no `konami_id`. The synchroniser is proven against the recorded lists `banlist-history` already holds, never a live host.

| Check | Observation that decides it |
| --- | --- |
| Card type | Spells alone admit only spells, and the count matches the type's share |
| Attribute | DARK admits only DARK monsters, and no spell or trap |
| Level range | 4 to 4 admits only Level 4; cards with no level are absent, not zero |
| Monster type and archetype | Each admits only its members |
| Typing narrows a long list | The archetype field narrows 662 values and the type field 87 |
| Attack and defence ranges | A 2000–3000 band admits only monsters inside it |
| "?" excluded from ranges | A range from 0 does not admit a `-1` card, and the "?" filter finds it |
| Year range | 2004–2005 admits only cards released in those years |
| Undated cards counted | With a year range applied, the excluded count is reported |
| Format | GOAT admits only the GOAT pool, and the count matches |
| Status in that format | A card forbidden in the chosen format shows as forbidden |
| A published list narrows | The 2005-03-01 TCG list admits its 77 cards and no others |
| Historical status shown | A card forbidden in 2005 and free today shows forbidden while that list is chosen |
| Lists offered in order | The chooser lists the stored TCG lists oldest first |
| No lists stored | The chooser states that none has been downloaded |
| Unmatched entries counted | A list naming an unknown identifier reports the difference |
| Synchronisation stores | After a run, the stored lists match what the source published |
| Progress reported | The count rises during a run and search still answers |
| Failure contained | With the source unreachable, stored lists are unchanged and the failure is stated |
| Offline afterwards | With the source unreachable, the chooser and the filter still work |
| Filters combine | Two filters admit only cards satisfying both, and the count matches |
| Applied filters listed | Each applied filter is named; an unset one is not |
| Clearing | The count returns to the whole catalog |
| Empty result explained | A combination matching nothing names what is applied |
| Owned-only | With an empty collection, it reports that nothing is owned |
| Keyboard | Every filter is set and cleared without a pointer |
| Filter latency | Applying a filter updates the results within 150 ms against the full catalog |
| Concurrency | The feature builds under Swift 6 strict concurrency with no diagnostics |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `CardFilters.cardTypes` expanding to frames, the existing attribute, level, race, archetype and range conditions given a panel, and `>= 0` on every numeric range; the first seven checks |
| `R2` | The ISO string year range with its excluded count, and the existing format condition; the four when-and-where checks |
| `R3` | The `banlist_revision`/`banlist_entry` join with the status projected from the entry; the five list checks |
| `R4` | `BanlistSyncCoordinator` in the composition root over `banlist-history`'s synchroniser; the four synchronisation checks |
| `R5` | `FilterOutcome` and the filter panel; the six working-with-filters checks |
| `NFR1` | Indexed columns and one statement per query; measured filter latency |
| `NFR2` | The three counts in `FilterOutcome`; the excluded, unmatched and empty-result checks |
| `NFR3` | Every filter resolved from stored rows after one synchronisation; the offline check |
| `NFR4` | Sentence-forming filter descriptions and a keyboard path through the panel |
| `NFR5` | Value types throughout; the strict-concurrency build check |
