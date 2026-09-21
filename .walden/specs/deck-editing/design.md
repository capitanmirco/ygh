---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T09:24:43Z
last_modified: 2026-09-21T09:24:43Z
approved_fingerprint: sha256:9a3c82f124dd779e1424537fe92b865ea06ababdb8599b6fbc28f675e8325025
source_requirements_approved_at: 2026-09-21T09:21:36Z
source_requirements_fingerprint: sha256:758cd1cbd85ee1ffe29276a1078cbc262cde833d9a1c53d92dc6e71e937ba208
---

# Feature Design

## Architecture

Two new write operations, an undo stack that needs no third one, and an editor that stops swallowing errors. No new module: the editor already exists and this gives it the operations it is missing.

```
YGOFeatureDeckBuilder ──▶ YGOCore (DeckEditing, DeckEdit)
        │                    ▲
        └── DeckEditHistory  │
                             │
            YGOPersistence ──┘  (SQLiteDeckRepository)
```

### `DeckEditing` is a new port, not a wider `DeckBuilding`

`DeckBuilding` is `deck-builder`'s certified contract and every stub in its offline proofs conforms to it. Adding two methods would break each of them for operations they do not use.

So the two new operations live in `DeckEditing`, which `SQLiteDeckRepository` also conforms to. The editor takes both, and a caller that only builds is untouched.

<!-- assumed: a separate DeckEditing protocol rather than widening DeckBuilding (source: the same decision taken for CardSearchCounting in card-detail, for the same reason) -->

### A move is one transaction, not a remove and an add

The obvious implementation is `removeCard` then `addCard`. It is wrong in two ways that only show up when something goes wrong: between the two calls the deck holds fewer cards than it should, and if the second fails the copies are gone.

`move` is therefore one write block: decrement or delete in the source, insert or increment in the destination, touch the deck once. `R3.AC4` (no empty entry left behind) is the same `DELETE ... WHERE quantity <= 1` before `UPDATE` that `removeCard` already uses — a check constraint refuses a zero quantity before any tidying could run, which is a bug this project has already paid for once.

### Undo is inverse edits, not snapshots

Every edit here has an inverse that is another edit of the same kind:

| Edit | Inverse |
| --- | --- |
| add one copy | set that section's count back to what it was |
| set count from *m* to *n* | set count from *n* back to *m* |
| move *k* copies A→B | move *k* copies B→A |

So undo needs no new write path and no way of restoring a deck that the ordinary operations cannot already reach. A snapshot stack would also work — a deck is 74 slots — but it would need a "replace the whole deck" write that exists for no other reason, and that write would be the only code able to put a deck into a state the editor cannot otherwise produce.

`DeckEditHistory` holds the applied edits and the undone ones. A new edit clears the undone ones (`R4.AC4`), because a redo of something that no longer follows from the current deck would apply a change to a deck it was never about. Opening another deck discards both (`R4.AC6`), for the same reason: a ⌘Z meant for one deck must not reach another.

<!-- assumed: the history lives in the editor rather than in storage (source: C5, which states it does not survive closing the application) -->

### Failures stop being silent

The editor calls the repository with `try?` today, so an add that throws leaves the deck unchanged and says nothing. Every operation becomes a `do`/`catch` that records what failed, and the editor reloads the deck from storage afterwards — so what is shown is what is stored, which is `NFR3` by construction rather than by care.

### Dragging sits on top of moving

`R5.AC1` to `R5.AC3` are SwiftUI's `draggable` and `dropDestination` over the same `move` the keyboard path calls. The gesture is not covered by an automated proof and `C6` says so; what is proven is that the operation under it is correct and that `R5.AC4` offers the same thing without a pointer.

## Data Model

**No schema change.** `deck_slot` already carries `(deck_id, section, artwork_id, card_id, quantity)` with a uniqueness on the first three, which is exactly what a move changes and a count sets.

```swift
public protocol DeckEditing: Sendable {
    /// Makes the section hold exactly `copies` of that artwork. Zero removes it.
    func setQuantity(
        artwork: ArtworkIdentifier, section: DeckSection,
        to copies: Int, in deckID: Int64) async throws

    /// Moves up to `copies` between sections, in one transaction.
    /// Returns how many actually moved, which may be fewer.
    @discardableResult
    func move(
        artwork: ArtworkIdentifier, from: DeckSection, to: DeckSection,
        copies: Int, in deckID: Int64) async throws -> Int
}

public enum DeckEdit: Hashable, Sendable {
    case quantity(artwork: ArtworkIdentifier, section: DeckSection, from: Int, to: Int)
    case move(artwork: ArtworkIdentifier, from: DeckSection, to: DeckSection, copies: Int)

    var inverse: DeckEdit { ... }
}
```

Adding and removing are expressed as `quantity` edits so that the history has two cases instead of four, and so `R4.AC3` is one implementation rather than four.

The SQL a move runs:

```sql
DELETE FROM deck_slot
 WHERE deck_id=? AND section=? AND artwork_id=? AND quantity <= ?;
UPDATE deck_slot SET quantity = quantity - ?
 WHERE deck_id=? AND section=? AND artwork_id=?;
INSERT INTO deck_slot (deck_id, section, artwork_id, card_id, quantity)
VALUES (?,?,?,?,?)
ON CONFLICT(deck_id, section, artwork_id) DO UPDATE SET quantity = quantity + ?;
```

The `ON CONFLICT` is what makes `R3.AC3` a sum rather than a duplicate row, and it is the same clause `addCard` already relies on.

## Options Considered

1. **A separate `DeckEditing` port over widening `DeckBuilding`.** Widening would be one fewer protocol and would break every stub in a certified specification's offline proofs.
2. **One transaction over remove-then-add.** Two calls are simpler to write and leave the deck briefly wrong, or permanently short if the second fails.
3. **Inverse edits over snapshots.** Snapshots are trivially correct and would need a whole-deck write that nothing else wants, and that write would be the only path able to produce a deck state the editor cannot.
4. **Two edit cases over four.** Add and remove are count changes. Keeping them as their own cases would triple the inverse table for no new behaviour.
5. **Reloading after each edit over patching the shown deck in place.** Patching is faster and lets the shown deck drift from the stored one. The deck is 74 slots; the reload is the honesty.
6. **Dragging over buttons alone.** Buttons are fully provable and slower to use. Both are built, and the keyboard path is what `R5.AC4` guarantees.

## Simplicity And Elegance Review

What keeps this small:

- No migration, no new table, no new module. Two SQL operations and a stack.
- Undo reuses the operations it is undoing, so there is no second way to change a deck.
- `setQuantity(to: 0)` is removal, so `R2.AC2` needs no code of its own.
- The candidate search is the browser's behaviour applied to an existing list: load on open, narrow on change, filter by the deck's format.

Challenged once: the undo history could have lived in the repository, giving every screen the same ⌘Z. Rejected because `C5` scopes it to an open editor, and a stored history would have to survive a deck being edited elsewhere, imported over, or deleted.

## Failure Modes And Tradeoffs

| Failure | Containment |
| --- | --- |
| A write fails | Reported, and the deck reloaded from storage, so what is shown is what is stored (`R2.AC4`, `NFR3`) |
| A move asks for more copies than are held | Moves what is there and reports how many moved (`R3.AC6`) |
| A move between a section and itself | Refused as a no-op before any SQL runs (`R3.AC5`) |
| Moving every copy | The source entry is deleted, not left at zero, which the schema would refuse anyway (`R3.AC4`) |
| An edit breaks a rule | Applied and reported, which is `deck-builder`'s established contract (`C1`, `R2.AC3`) |
| Undo with nothing to undo | Reported, deck untouched (`R4.AC5`) |
| A redo that no longer follows | Discarded when a new edit is made (`R4.AC4`) |
| ⌘Z after switching decks | The history is cleared on load, so it cannot reach the wrong deck (`R4.AC6`) |
| A drag onto nothing | No drop destination, no operation |

Accepted tradeoffs:

- **The gesture is unproven.** `C6` states it, and the operation beneath it is proven. A UI test target would cover it and would be a new, slow, layout-fragile impianto for three criteria.
- **The history does not survive closing.** Undo is for the mistake you just made, not for yesterday's.
- **Every edit reloads the deck.** Two queries for 74 slots, against a shown deck that can never disagree with the stored one.
- **Writing stays permissive.** A deck can be made illegal and is told so. Refusing edits would make the editor argue with the builder instead of describing it.

## Verification Plan

Model and history are proven against stubs with no database. The two write operations are proven against an in-memory SQLite database seeded to the shape of the user's own decks: 40 main, 15 extra, 15 side, with cards held one, two and three times, and two cards present in two sections at once.

| Check | Observation that decides it |
| --- | --- |
| Editor opens with candidates | A freshly opened editor offers cards with no text typed |
| Candidates narrow while typing | Successive text changes produce successive candidate sets |
| Format pool respected | A GOAT deck's editor offers no card outside the GOAT pool |
| Default section | A Fusion Monster lands in the extra deck, a Spell in the main |
| Count set exactly | A card held once and set to three is held three times there and nowhere else |
| Count set to zero | The card is gone from that section and the other sections are untouched |
| Illegal count applied and reported | Four copies are held and a copy-limit violation is reported |
| Failed write reported | With writes refused, the deck is unchanged and the failure is stated |
| Legality after an edit | Reported violations are those of the edited deck |
| Move transfers | Two copies moved leave the source two lighter, the destination two heavier, the total unchanged |
| Artwork preserved | The moved copies keep the artwork the deck held |
| Move into an occupied section | One moved into a section holding two leaves three, in one entry |
| Move everything | No entry is left in the source section |
| Move to the same section | Nothing changes and nothing is reported as failed |
| Move more than held | Only the copies held move, and the deck stays consistent |
| Undo an add | The deck matches what it held before, section by section |
| Redo | The deck matches what it held after the original edit |
| All four kinds undone | Add, removal, count change and move each undo to their prior state |
| New edit clears the redo | After an undo and a different edit, there is nothing to redo |
| Nothing to undo | Undo on a freshly opened deck changes nothing and says so |
| Switching decks | Opening a second deck leaves nothing to undo |
| Keyboard path | Moving a card and changing a count are both reachable without a pointer |
| Edit latency | An edit is reflected within 100 ms against a full-sized deck |
| Written before reported | The stored deck already holds the edit when the editor reports it done |
| Offline | Every edit is applied with no network |
| Accessibility | Each deck entry reads as a sentence naming card, section and count |
| Concurrency | The feature builds under Swift 6 strict concurrency with no diagnostics |
| **Dragging (by hand)** | **Not covered by an automated proof (`C6`): dragging a card between sections, dragging a candidate in, and the drop target being distinguished are checked in the running application** |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `DeckEditorViewModel` loading candidates on open and narrowing on change, filtered by the deck's format; the first four checks |
| `R2` | `DeckEditing.setQuantity` in `SQLiteDeckRepository`, with failures caught and the deck reloaded; the five count checks |
| `R3` | `DeckEditing.move` as one transaction; the six move checks |
| `R4` | `DeckEditHistory` over `DeckEdit.inverse`; the six undo checks |
| `R5` | `draggable`/`dropDestination` over `move`, and the keyboard path; `R5.AC4` is proven, `R5.AC1` to `R5.AC3` are verified by hand as `C6` states |
| `NFR1` | One transaction and a two-query reload; measured edit latency |
| `NFR2` | The write completes before the editor reports it; the written-before-reported check |
| `NFR3` | Failures caught and reported, and the deck reloaded from storage after every edit |
| `NFR4` | Keyboard-reachable edits and sentence-forming entry labels |
| `NFR5` | Every operation is local SQL; the offline check |
| `NFR6` | Value types and an actor-isolated editor; the strict-concurrency build check |
