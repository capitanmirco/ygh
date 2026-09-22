---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-22T12:36:32Z
last_modified: 2026-09-22T12:36:32Z
approved_fingerprint: sha256:e31a525d4bf020a0b2143cd0ff647fe5fbdb0ec4266339e91ce7a1dfd89ce294
source_requirements_approved_at: 2026-09-22T12:34:04Z
source_requirements_fingerprint: sha256:635ecd967b2b569596eff9edf4f2a9976618991dde28cb8d50485dc0793ac2b4
---

# Feature Design

## Architecture

One field on `Deck`, one port, three methods finishing a half-built store, and controls that are menus rather than presentations.

```
YGOFeatureDeckBuilder ──▶ YGOCore (DeckLabelling, Deck.tags)
   DeckEditorViewModel          ▲
   DeckLibraryViewModel         │
                       SQLiteDeckRepository
                       (changeFormat + the tag half of
                        SQLiteDeckOrganisation.swift)
```

No table, no column, no migration. `tag` and `deck_tag` are there and cascade; `changeFormat` is written and certified. What is missing is a way to read a deck's tags, a way to remove one, a way to list those in use, and somewhere to press.

### A deck carries its labels

```swift
public struct Deck: Hashable, Sendable, Identifiable {
    // … unchanged …
    /// What the user calls this deck, in their own words.
    public let tags: [String]
}
```

Defaulted to `[]` in the initialiser, so every existing caller — including `deck-builder`'s certified tests — keeps compiling and describing what it already described.

The alternative was for the list to read tags separately, and `NFR4` rules out the shape that invites: one query per deck. `allDecks()` already loads each deck's slots by identifier, so a second per-deck query would double an N+1 rather than introduce one.

Instead the tags for a whole list arrive in **one** query:

```sql
SELECT deck_tag.deck_id, tag.name FROM deck_tag
JOIN tag ON tag.id = deck_tag.tag_id
WHERE deck_tag.deck_id IN (…)
ORDER BY tag.name COLLATE NOCASE
```

`loadDeck` keeps its single-deck read for the one-deck case; `allDecks` groups the result and hands each deck its own.

### The port

```swift
public protocol DeckLabelling: Sendable {
    func changeFormat(_ deckID: Int64, to format: CardFormat) async throws
    func addTag(_ name: String, to deckID: Int64) async throws
    func removeTag(_ name: String, from deckID: Int64) async throws
    /// Every tag in use, for offering rather than retyping.
    func allTags() async throws -> [String]
}
```

`changeFormat` is already on `SQLiteDeckRepository` and already certified; it joins the protocol rather than being written again.

### One tag, however it is typed

`tag.name` is `TEXT NOT NULL UNIQUE`, and SQLite's default comparison is case-sensitive, so *Goat* and *goat* would be two rows. `C1` forbids a migration, so the rule lives in the query rather than in the schema:

```sql
SELECT id FROM tag WHERE name = ? COLLATE NOCASE
```

A tag is trimmed before it is used, matched without regard to case, and the **first spelling wins**: tagging one deck *Goat* and another *goat* leaves one tag reading *Goat*, because a label the user typed should not be rewritten under them. An empty name after trimming is refused before any write, which is `R2.AC5`.

<!-- assumed: the first spelling is kept rather than the newest or a lowercased form (source: R2.AC4 requires one tag, not a particular spelling; rewriting a user's label is the surprising option) -->

### Removal is per deck, and asks nothing

`removeTag(_:from:)` deletes one row from `deck_tag`. The tag itself stays, so the other decks carrying it are untouched — which is `R2.AC3` — and it remains available to add again.

No confirmation. Hard Rule 4 exists for what cannot be recovered; a label is two seconds of typing, and a confirmation on every removal would make labelling tedious enough that nobody labels anything. Recorded as a tradeoff rather than left implicit.

### Nothing here is a presentation

The deck list already hosts a sheet, two alerts and an exporter, and this project's recorded failures are all presentations competing on one view. So the controls added here are menus and inline fields, which present nothing:

- **Format**: a `Picker` inside the deck's context menu, and a `Picker` in the editor's header. Both list the nine formats with the deck's own marked.
- **Tags**: in the editor's header, the deck's tags as removable chips and a field to add one, with a `Menu` offering the tags already in use.
- **Filter**: a `Menu` in the sidebar naming the tag in force.

No new sheet, no new alert, nothing to compete for the one presentation SwiftUI will show.

### Editing in the editor, refreshing everywhere

The editor gains `labels: (any DeckLabelling)?`, the same optional-port shape as `editing`, `catalogue` and `history`. After a change it reloads its own deck, and the deck list refreshes through the `onDeckChanged` hook the editor already calls on every edit — the plumbing added for the card total carries this with nothing new.

The deck list gets the format `Picker` too, because the user pointed at the word *GOAT* in that row. It goes through the same port on `DeckLibraryViewModel`, which already has `changeFormat` and already reloads.

### Filtering reads no storage

`decks(withTag:)` exists in the repository and this feature does not call it. Once a deck carries its tags, filtering is a predicate over the list already in memory:

```swift
public var visibleDecks: [Deck] {
    guard let tagFilter else { return decks }
    return decks.filter { $0.tags.contains { $0.caseInsensitiveCompare(tagFilter) == .orderedSame } }
}
```

One source for the list, no second read that can disagree with the first, and `R3` is provable without a database.

## Options Considered

**Reading tags with `decks(withTag:)` and a per-deck lookup.** The methods exist, so it looks like the cheap route. Rejected: `allDecks` already issues a query per deck for its slots, and a second one per deck to learn two words would make the list's cost grow with the library for no reason. One grouped query serves the whole list.

**Storing tags lowercased to make them unique.** The schema's `UNIQUE` would then do the work with no `COLLATE` anywhere. Rejected because it rewrites what the user typed: a duelist who tags a deck *Edison* should not find *edison* on it afterwards.

**A sheet for editing tags.** Room for a proper editor with rename and delete. Rejected for this iteration: the sidebar already holds four presentations, renaming and deleting a tag everywhere are explicitly out of scope, and adding and removing one tag fits in a field and a menu.

## Simplicity And Elegance Review

The feature adds one field, one protocol, two repository methods and no new screen. Two of the four port methods already existed and were unreachable.

The first draft gave `DeckLibraryViewModel` its own `tagFilter` **and** a `filteredDecks` array kept in step with `decks`. That is a second copy of the list, and this project has already been bitten by one: the sidebar's stale copy that missed a rename. It is a computed predicate now, so there is one list and one truth.

Coupling stays where the constitution puts it: the feature module sees `DeckLabelling` and `Deck`, the conformance sits on the repository that already holds `changeFormat`, and the composition root binds one more protocol to an object it already builds.

## Failure Modes And Tradeoffs

**A format whose pool the catalog does not publish.** `Common Charity`, `Duel Links` and `Speed Duel` have pools; `Edison` has 3,662 cards and `GOAT` 1,684. A format with no upstream ban list already reports `restrictionsAreUserMaintained`, and `R1.AC2` re-judges through that existing path rather than inventing a verdict.

**Changing format makes a legal deck illegal.** That is the point, and it is why `R1.AC2` requires the re-judgement to be immediate: a deck set to Edison that still holds GOAT-only cards must say so before the user believes otherwise. Nothing is removed from the deck.

**A tag added twice in different spellings.** One tag, first spelling kept. The second attempt is not an error and is not reported as one.

**A tag removed while a filter is using it.** The filtered list empties, and `R3.AC4` requires that to read as a sentence rather than as a blank area.

**Two decks, one tag, one removal.** `deck_tag` is per pair, so removing one row cannot reach another deck. `R2.AC3` asserts it rather than trusting the schema.

**Tags travel with a deck copy.** `duplicate` copies `deck_slot` and not `deck_tag`, so a duplicated deck starts unlabelled. Accepted and left as it is: the duplicate is a new deck the user is about to change, and inheriting labels silently is the more surprising of the two.

## Verification Plan

New suite `DeckLabelTests` in `YGOSyncTests`, where the deck library's other affordances are proven, plus additions to `YGOPersistenceTests` for the storage half. Everything runs against a temporary database.

| What | Where | How it is observed |
| --- | --- | --- |
| A format change is stored and read back | `DeckLabelTests` | a GOAT deck set to Edison reads Edison from a second read of storage |
| The change re-judges the deck | `DeckLabelTests` | a deck legal in GOAT reports violations once set to a format whose pool excludes its cards |
| Every format is offered | `DeckLabelTests` | the chooser's options are `CardFormat.allCases`, with the deck's own marked |
| A failed format change keeps the old one | `DeckLabelTests` | with a stub throwing, the deck still reads its previous format and a failure is reported |
| A tag is stored and carried by the deck | `DeckLabelTests` | after tagging, the deck read from storage carries it |
| Tags arrive with the list | `YGOPersistenceTests` | three decks with tags are read with their tags in one grouped query, asserted by count of statements or by reading the whole list in one call |
| Spelling and spaces make one tag | `YGOPersistenceTests` | *Goat*, *goat* and * goat * on one deck leave one tag, spelled as first typed |
| An empty tag is refused | `DeckLabelTests` | adding `"   "` leaves the deck's tags unchanged |
| Removal is per deck | `YGOPersistenceTests` | two decks share a tag; removing it from one leaves the other carrying it and the tag still listed |
| Tags in use are offered | `DeckLabelTests` | `allTags` returns every tag on any deck, once each, ordered |
| Filtering narrows the list | `DeckLabelTests` | with three decks and a tag on two, `visibleDecks` holds those two |
| Clearing restores it | `DeckLabelTests` | `visibleDecks` returns to the full list in its usual order |
| The filter names itself | `DeckLabelTests` | the chosen tag is readable on the model while the filter is applied |
| An empty result says so | `DeckLabelTests` | filtering by a tag no deck carries reports that it matched nothing, distinct from an unfiltered empty library |
| Labels never reach the cards | `DeckLabelTests` | a deck's slots are identical before and after a format change and a round of tagging |
| The controls exist | `DeckLabelTests` | source assertions that the format picker and the tag controls are declared, plus the app target building |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `DeckLabelling.changeFormat` bound to `SQLiteDeckRepository`, format `Picker` in the deck's context menu and the editor header, re-judgement through the existing reload |
| `R2` | `Deck.tags`, `addTag`/`removeTag`/`allTags`, `COLLATE NOCASE` matching with the first spelling kept, trimming before any write |
| `R3` | `tagFilter` and the computed `visibleDecks` on `DeckLibraryViewModel`, the sidebar's filter menu, and the empty-result state |
| `NFR1` | Slots compared before and after both kinds of edit |
| `NFR2` | Every call is a local database read or write; no client and no transport is involved |
| `NFR3` | Pickers and menus are standard SwiftUI controls; a deck row announces its name, format and tags as one label |
| `NFR4` | One grouped query for the whole list's tags; filtering is a predicate over the list already held |
