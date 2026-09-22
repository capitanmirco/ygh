---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-22T13:32:13Z
last_modified: 2026-09-22T13:32:13Z
approved_fingerprint: sha256:3a67359e4fcd941c925b0a2728ac165362da6c7a9a00cce7cff6f9c0db2a69bb
source_requirements_approved_at: 2026-09-22T13:31:09Z
source_requirements_fingerprint: sha256:384f1d2e1fed41402c3c64d466effb81db6e298ca59bad31eb85dc5fe15d7cef
---

# Feature Design

## Architecture

One read, one pure judgement, one panel.

```
YGOFeatureDeckBuilder ──▶ YGOCore (DeckListJudgement, ListedDeckCard)
   DeckEditorViewModel        ▲   BanlistHistoryReading (existing)
   DeckLegalityPanel          │
                     SQLiteBanlistHistory
                     (banlist_revision + banlist_entry, already stored)
```

No table, no column, no migration, and no fetch. The 177 lists are stored and this reads them.

### The deck's cards have to become identifiers a list knows

`banlist_entry` is keyed by `konami_id`; `DeckCardIndex.Entry` does not carry one. So the read that answers this feature takes a deck's cards and a chosen list, and returns what the list says about each:

```swift
/// One of a deck's cards, as a published list sees it.
public struct ListedDeckCard: Hashable, Sendable, Identifiable {
    public let card: CardIdentifier
    public let name: String
    public let held: Int
    public let status: BanlistStatus?     // nil: the list does not name it
    public let isMatched: Bool            // false: the card carries no konami_id
    public var permitted: Int { … }
    public var isOverAllowance: Bool { held > permitted }
}

public protocol DeckListJudging: Sendable {
    /// Every card of a deck, judged against one stored list, in one read.
    func judge(
        _ deckID: Int64, against format: BanlistFormat, effectiveDate: String
    ) async throws -> [ListedDeckCard]
}
```

One statement joins `deck_slot`, `card` and `banlist_entry` for the chosen revision, sums the copies per card, and returns a row per distinct card. A deck holds at most ninety of them, which is `NFR1` satisfied by the shape rather than by a cache.

`permitted` comes from the status: forbidden 0, limited 1, semi-limited 2, and unnamed 3 — the absolute ceiling that holds regardless of any list, which `DeckValidator` already calls `absoluteCopyLimit`.

### Unmatched is its own answer

A card with no `konami_id` cannot be found on a list. Reporting it as unrestricted would be a lie that reads exactly like the truth, so `isMatched` is false and the panel says *non abbinabile*. 203 of the catalog's 14,566 cards are in that position, though none of the user's current deck cards are.

That distinction is the whole of `NFR4`: this screen reports what a named list said on a named date, never its own opinion.

### The era mapping is a default, and it is visible

```swift
public extension CardFormat {
    /// The published list a format is played under, when one defines it.
    ///
    /// GOAT and Edison are community formats named after the list that was in
    /// force: March 2005 and March 2010. That is a judgement about how people
    /// play, not something upstream publishes, which is why it is a default
    /// the user can override rather than a rule.
    var impliedList: (format: BanlistFormat, effectiveDate: String)? { … }
}
```

- `tcg`, `ocg`, `masterDuel` → the newest stored list of that format
- `goat` → tcg 2005-03-01, `edison` → tcg 2010-03-01, `ocgGoat` → ocg's nearest list of the era
- `duelLinks`, `speedDuel`, `commonCharity` → none, and `R1.AC3` says so out loud

<!-- assumed: OCG GOAT maps to the OCG list of the same era rather than to no list (source: it is an OCG format of the GOAT period; the alternative is to report nothing for a format the catalog does have a pool for) -->

### Judging is arithmetic, not a query

The read returns held counts and statuses. Everything after that — the totals per status, whether the deck is within the list, which cards are over — is a function of that array:

```swift
public struct DeckListVerdict: Hashable, Sendable {
    public let list: BanlistRevision
    public let cards: [ListedDeckCard]
    public var forbidden: Int { … }
    public var limited: Int { … }
    public var semiLimited: Int { … }
    public var unmatched: Int { … }
    public var isWithinList: Bool { cards.allSatisfy { !$0.isOverAllowance } }
}
```

Provable with an array and no database, which is how `R3` is checked.

### Copies, not entries

`R3.AC3` is why `held` is a sum: three copies of a limited card are one card over its allowance, reported as 3 held against 1 permitted. Counting entries would report the same card three times and make a deck look three times as illegal as it is.

### The panel is the third thing the side can show

`deck-card-preview` put a panel beside the deck and `deck-history` taught it to show two things. This is the third: preview, history, legality, one at a time, each with its own shortcut. No sheet, no alert — the editor is already holding a confirmation dialog and a restore alert, and this project's recorded failures are all presentations competing on one view.

The list chooser is a `Menu` grouped by format, newest first, each entry naming its date.

### Judging never edits

`R1.AC6` is structural rather than asserted by discipline: nothing in this feature holds a writing port. `DeckListJudging` reads, `DeckListVerdict` computes, and the panel displays. There is no path from here to `changeFormat`.

## Options Considered

**Extending `DeckValidator` to take a list.** The validator already produces violations and the editor already shows them, so the verdict would arrive where the user is looking. Rejected: the validator is certified by `deck-builder` and `deck-editing`, its violations are about a deck's *own* format, and a chosen list is a different question asked of the same deck. Mixing them would make *legale* ambiguous — legal under what? A separate verdict that names its list keeps both honest, and `R3.AC4` requires the naming.

**Judging from `DeckCardIndex` by adding `konami_id` to its entries.** The index is already loaded, so the match would need no read. Rejected: the index is built for the validator and is certified with it, and a list judgement also needs the held counts summed per card, which the index does not carry. One purpose-built read is smaller than widening a certified type for a second consumer.

**One row per copy instead of per card.** Simpler query, no grouping. Rejected by `R3.AC3`: it reports the same card three times and inflates the verdict.

## Simplicity And Elegance Review

One protocol, one read, two value types, one panel. Everything it judges was already stored and already fetched.

The first draft had the view model hold `forbiddenCount`, `limitedCount`, `semiLimitedCount` and `isWithinList` as stored properties refreshed after every read. Four values derived from one array, each able to disagree with it. `DeckListVerdict` computes them, so there is one source and nothing to keep in step.

Coupling stays where the constitution puts it: the feature module sees `DeckListJudging` and `BanlistHistoryReading`, the conformance sits on `SQLiteBanlistHistory` which already owns those tables, and the composition root binds one more protocol to an object it already builds.

## Failure Modes And Tradeoffs

**A format with no list.** Reported, not guessed. Judging a Speed Duel deck against the current TCG list would be worse than saying nothing, because it would look authoritative.

**A card the lists cannot name.** Counted separately and never folded into the unrestricted. The alternative reads identically to a correct answer, which is the one thing `NFR4` forbids.

**A list stored with no entries.** A revision whose entries failed to store would report every card unrestricted. The verdict names the list and its entry count, so an empty list is visible rather than silently permissive.

**The era mapping is opinion.** GOAT and Edison are community formats; the dates chosen are the ones the formats are named for. The mapping is a default the user overrides in one menu, and `C2` records that it is a judgement.

**The pool is a separate verdict.** A card outside a retro format's pool is illegal there whatever the list says, and the validator already reports that. This panel does not repeat it; the two verdicts sit side by side, each naming what it is about.

**A deck judged while being edited.** The verdict is read again after every edit the editor already reloads for, so it cannot describe a deck that no longer exists.

## Verification Plan

New suite `DeckLegalityTests` in `YGOSyncTests` for the judgement and the panel's state, and `DeckListJudgementTests` in `YGOPersistenceTests` for the read. Both names and both paths were checked unused. Everything runs against a temporary database seeded from the recorded fixtures.

| What | Where | How it is observed |
| --- | --- | --- |
| A deck is judged against a chosen list | `DeckListJudgementTests` | a deck holding a card the list forbids reports that card forbidden, with its held count |
| Cards the list does not name | `DeckListJudgementTests` | a card absent from the list reads unrestricted with three permitted |
| A card with no identifier | `DeckListJudgementTests` | a card whose `konami_id` is null reads unmatched, and is not among the unrestricted |
| Copies are summed per card | `DeckListJudgementTests` | three copies of one card produce one row reading 3 held |
| One read for a whole deck | `DeckListJudgementTests` | judging a deck of ninety distinct cards issues one statement against `banlist_entry`, counted through the database's trace |
| The implied list | `DeckLegalityTests` | GOAT implies TCG 2005-03-01, Edison implies TCG 2010-03-01, TCG implies the newest stored TCG list |
| A format with no list | `DeckLegalityTests` | Speed Duel implies none, and the model reports that rather than choosing one |
| Opening a deck judges it | `DeckLegalityTests` | a GOAT deck opened reports a verdict naming the March 2005 list |
| Choosing another list re-judges | `DeckLegalityTests` | the same deck moved to the March 2010 list reports a different forbidden count, with no reopening |
| Judging leaves the deck alone | `DeckLegalityTests` | after judging against six lists the deck's format and slots are identical |
| Totals per status | `DeckLegalityTests` | a verdict over a known array reports its forbidden, limited, semi-limited and unmatched counts |
| Within or not | `DeckLegalityTests` | a deck holding a forbidden card is not within the list; removing it makes it within |
| Entries versus copies | `DeckLegalityTests` | three copies of a limited card are one card over its allowance, not three |
| The verdict names its list | `DeckLegalityTests` | the verdict carries the format and the effective date it was produced from |
| Every stored list is offered | `DeckLegalityTests` | the chooser holds one entry per stored revision, grouped by format, newest first |
| Announcements | `DeckLegalityTests` | each judged card announces its name, its status, the copies held and the copies permitted |
| The panel is in the editor | `DeckLegalityTests` | source assertions that the panel and its shortcut are declared, plus the app target building |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `DeckListJudging` bound to `SQLiteBanlistHistory`, `CardFormat.impliedList`, the chooser over `revisions(for:)`, and the absence of any writing port |
| `R2` | `ListedDeckCard` with its status, held count, permitted count and `isMatched` |
| `R3` | `DeckListVerdict`'s computed totals, `isWithinList`, per-card sums and the named revision |
| `R4` | The panel's keyboard shortcut and selection, and `ListedDeckCard`'s announcement |
| `NFR1` | One grouped read per judgement, asserted by counting statements |
| `NFR2` | Every list judged against is already stored; no client and no transport is involved |
| `NFR3` | One sentence per judged card, and standard SwiftUI controls in a keyboard-reachable panel |
| `NFR4` | `isMatched`, the named revision on every verdict, and the explicit *no list* answer for formats that have none |
