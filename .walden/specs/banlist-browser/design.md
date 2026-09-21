---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T19:45:15Z
last_modified: 2026-09-21T19:45:15Z
approved_fingerprint: sha256:474774205f5ddd37fc4efae00cabf31d4457b905ed93a3a331a2551e495fec92
source_requirements_approved_at: 2026-09-21T19:45:15Z
source_requirements_fingerprint: sha256:ec5d4123432b049de877f9a2fddf2f855cf1aacfc1a84f92d42f4db002fc0605
---

# Feature Design

## Architecture

A sixth section, a view model, and one column added to a query that already exists.

```
YGOFeatureBanlist ──▶ YGOCore (BanlistHistoryReading, CardFrame)
        │                      ▲
        └──▶ CardDetailViewModel (card-detail's panel, reused)
                               │
                   SQLiteBanlistHistory
```

Nothing is fetched and nothing is stored. `banlist-history` holds the lists, `catalog-filters` wired the synchronisation, and this reads what they left.

### The stored entry needs one more field

`BanlistListEntry` carries the identifier, the card's names and the status. Grouping by kind needs the kind, and the kind lives on the card.

The query already joins `card` to fetch those names, so the addition is one column: `BanlistListEntry` gains `frame: CardFrame?`, nil when the catalog cannot match the entry — the same condition that already leaves `cardID` and `name` nil.

<!-- assumed: widening BanlistListEntry rather than adding a second read (source: the existing query already joins card for the names, so the kind costs one column rather than a second join) -->

That is an additive change to a type `banlist-history` certified. Every existing call site keeps compiling, and the new field is the one thing this feature needs from storage.

### Grouping is arithmetic, not a query

`ORDER BY` could do this in SQL. It should not: the ordering is *forbidden, limited, semi-limited*, then *monster, spell, trap*, then by name — three keys, two of them enumerations whose order is a rule about Yu-Gi-Oh! rather than about strings.

Expressed in SQL it becomes a `CASE` ladder that has to be read carefully to see what it means. Expressed in Swift it is three comparable keys, and it is provable against a list of entries with no database at all.

So `BanlistListing` takes the entries a list holds and produces its three groups, ordered. That is the whole of `R1`.

### Unmatched entries are counted, not dropped

A list names `konami_id`s; 203 of the catalog's cards carry none, and a list can name a card released since the last catalog sync. Those entries have no name and no kind.

They are counted rather than shown, because a row reading *konami_id 4007* in a list of card names is noise. `R1.AC6` reports the number, and `NFR2` requires the arithmetic to close: grouped + unmatched = the list's size. That equation is the check that this screen is not quietly losing rows.

### The panel is the catalog's, for the third time

`R3` reuses `CardDetailViewModel` exactly as the deck editor does. A card selected on a list is a `CardIdentifier`, so the screen resolves it through `CardRepository` and hands over a `Card` — the same shape, and the same supersession rule, as `deck-card-preview`.

## Data Model

No schema change. One field on an existing type:

```swift
public struct BanlistListEntry: Hashable, Sendable {
    public let konamiID: Int
    public let cardID: Int?
    public let name: String?
    public let italianName: String?
    public let status: BanlistStatus
    /// What the card is, for grouping. Nil when the catalog cannot match the
    /// entry — the same condition that leaves `cardID` and `name` nil.
    public let frame: CardFrame?
}
```

And the grouping, in a new `YGOFeatureBanlist`:

```swift
public struct BanlistGroup: Hashable, Sendable {
    public let status: BanlistStatus
    public let cards: [BanlistListEntry]   // ordered: kind, then name
    public var count: Int { cards.count }
}

public enum BanlistListing {
    /// Three groups, most restrictive first, each ordered monsters → spells
    /// → traps → name.
    public static func groups(from entries: [BanlistListEntry]) -> [BanlistGroup]

    /// Entries the catalog cannot name. Counted rather than shown.
    public static func unmatched(in entries: [BanlistListEntry]) -> Int
}
```

The ordering keys:

| Key | Order |
| --- | --- |
| Status | forbidden, limited, semi-limited |
| Kind | monster, spell, trap, other |
| Name | alphabetical, by the displayed name |

`CardType` already exists from `catalog-filters` and already groups the seventeen frames into four, so the second key is a property lookup rather than a new classification.

## Options Considered

1. **Grouping in Swift over `ORDER BY`.** The ordering is two enumerations and a string; in SQL that is a `CASE` ladder nobody can read, and it cannot be proven without a database.
2. **Widening `BanlistListEntry` over a second read.** The query already joins `card` for the names. One more column against a second join and a second type.
3. **Counting unmatched entries over showing them.** A row reading `konami_id 4007` among card names is noise, and dropping them silently is worse than both.
4. **A sixth section over a tab inside the catalog.** The catalog is about finding cards; a list is a document. Putting it inside the filter panel is what this feature exists to stop.
5. **Reusing the detail panel over a summary.** Third reuse, and the alternative is a fourth place where a card is described.
6. **Newest list first over oldest.** The catalog's chooser lists oldest first, because it is a history. This screen opens on what is current, because a list is read to know the rules now.

## Simplicity And Elegance Review

What keeps this small:

- One column, one enum-ordering function, one screen.
- `CardType` already collapses seventeen frames into the four this needs.
- The three groups are the three stored statuses; there is no fourth to handle, because unrestricted is the absence of an entry.
- The panel, the synchronisation and the storage are all somebody else's, already proven.

Challenged once: this could have been a mode of the catalog grid, toggled by the published-list filter. Rejected because the grid's shape — one flat, name-ordered run of tiles — is the shape this feature exists to replace.

## Failure Modes And Tradeoffs

| Failure | Containment |
| --- | --- |
| A list names a card the catalog lacks | Counted as unmatched; the arithmetic closes (`R1.AC6`, `NFR2`) |
| No list is stored for a format | Stated, with the synchronisation reachable from there (`R2.AC4`) |
| An entry has no kind | Sorted last within its group rather than dropped |
| A card cannot be opened | The panel states it rather than blanking (`R3.AC3`) |
| A selection is superseded | Discarded by generation, as in the deck editor |
| A format has no list of its own | GOAT and Edison read the TCG set, as `catalog-filters` settled |

Accepted tradeoffs:

- **Unmatched entries are a number, not rows.** A count is honest and a list of bare identifiers is not useful. The number is the door to investigating if it ever grows.
- **`BanlistListEntry` grows a field.** Additive, on a type whose only readers are this feature and `banlist-history`'s own tests.
- **The screen shows one list at a time.** Comparison is a different screen and `banlist-history` already answers the question underneath it.
- **Ordering within a kind is by displayed name.** In Italian that differs from the English order, which is correct for the reader and means two languages sort differently.

## Verification Plan

The grouping is proven as arithmetic over entries, with no database. The screen is proven against the stored lists the application actually holds, and against the GOAT list's measured shape.

| Check | Observation that decides it |
| --- | --- |
| Three groups | The GOAT list yields groups of 18, 44 and 15 |
| Groups ordered | Forbidden precedes limited precedes semi-limited |
| Kinds ordered | In the forbidden group, its 6 monsters precede its 10 spells precede its 2 traps |
| Names ordered | Within a kind, the cards read alphabetically |
| Counts reported | Each group states its count and the three sum to the list's size |
| Unmatched counted | Grouped plus unmatched equals the list's size |
| Entries without a kind | Sorted last within their group rather than lost |
| Lists offered newest first | TCG offers its 73 lists with the most recent at the top |
| Choosing a list | A different date replaces the groups with that list's |
| A frozen format's list named | The GOAT-defining list is labelled among the TCG lists |
| Nothing stored | The screen states it and the synchronisation is reachable |
| What is shown is named | The format and the effective date are stated |
| Selecting a card | The card's detail appears beside the list |
| The same detail | A card opened here carries what the catalog gives it |
| An unopenable card | Stated rather than a blank panel |
| Latency | Grouping and showing any stored list stays within 150 ms |
| Offline | A stored list reads with no network |
| Accessibility | Each card reads as a sentence naming it, its kind and its status |
| Concurrency | The feature builds under Swift 6 strict concurrency with no diagnostics |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `BanlistListing.groups(from:)` over the three ordering keys, and `.unmatched(in:)`; the first seven checks |
| `R2` | `BanlistBrowserViewModel` over `BanlistHistoryReading.revisions(for:)`, with `CardFormat.definingListDate` for the label; the five choosing checks |
| `R3` | `CardDetailViewModel` reused, resolved through `CardRepository` with the deck editor's supersession rule; the three card checks |
| `NFR1` | One read and an in-memory sort; measured latency |
| `NFR2` | The closing arithmetic between groups, unmatched and the list's size |
| `NFR3` | Every read from stored rows; the offline check |
| `NFR4` | Sentence-forming labels and a keyboard path |
| `NFR5` | Value types and a pure grouping function; the strict-concurrency build check |
