---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T15:33:54Z
last_modified: 2026-09-21T15:33:54Z
approved_fingerprint: sha256:a2adec427667397f9a9cc78318197fe0c5afefb80e9864614967579573712c30
source_requirements_approved_at: 2026-09-21T15:31:40Z
source_requirements_fingerprint: sha256:7c087149049c8127db0ba386e88816db8878bc1a98c3ef4dd4a7eca45dec768b
---

# Feature Design

## Architecture

The deck editor learns to say which card is selected. Everything else already exists.

```
DeckEditorViewModel ──previewCard──▶ CardDetailViewModel ──▶ CardDetailView
        │                                    │
        └──── CardRepository ────────────────┘   (both read YGOCore ports)
```

No new module, no new table, no new panel. `card-detail` built and certified the panel; this gives it a card and a column to sit in.

### The editor resolves the card, not the view

A `DeckEntryItem` carries a `CardIdentifier`, a title and a frame — enough to draw a row and not enough to describe a card. The panel needs a `Card`.

That resolution belongs in the editor rather than in the view, for the same reason every other resolution does here: a view that asks a repository for a card is a view with a policy in it, and the resulting behaviour could then only be checked by rendering something.

So `DeckEditorViewModel` gains an optional `reader: (any CardRepository)?` — the same shape as the `catalogue` it already takes, and satisfied by the same `SQLiteCardRepository` — and publishes `previewCard: Card?`.

<!-- assumed: the editor resolves the card rather than a separate coordinator (source: the editor already owns the selection and already takes an optional catalogue port for exactly this kind of read) -->

### A candidate is already a card

`R1.AC4` asks that a search result open its detail too, and that one costs nothing: `candidates` is `[Card]` already. Selecting a candidate sets `previewCard` directly, with no read at all.

So the panel has two sources — an entry, which needs resolving, and a candidate, which does not — and one output. Whichever was chosen last wins, because a selection in one list is a deselection in the other.

### Selections supersede, as everywhere else

Moving down a deck list with the arrow keys issues a read per row. A read that returns after the user has moved on must not land in the panel, which is the same rule the browser and the detail panel already follow.

The editor therefore tags each resolution with a generation and discards an answer that arrives for a superseded selection. This is the third place in the application with that rule, and the third time it is worth the six lines.

### Three columns need a budget

The editor is already two columns. `R2.AC1` caps the detail at a quarter of the window — the same rule the catalog now follows — and `R2.AC2` gives it a floor so a narrow window makes the deck narrower rather than making the panel unreadable.

`R2.AC3` makes it dismissible, because a session spent adjusting counts does not need a card's effect text on screen. Closing it returns the width to the deck and keeps the selected card, so reopening does not lose the place.

## Data Model

Nothing stored. On `DeckEditorViewModel`:

```swift
/// The card the panel is showing, resolved from the selected entry or taken
/// straight from a selected candidate.
public private(set) var previewCard: Card?
/// Set when the catalog could not supply the selected card, so the panel can
/// say so rather than going blank (R1.AC5).
public private(set) var previewFailure: String?

public func previewEntry(_ item: DeckEntryItem) async
public func previewCandidate(_ card: Card)
public func dismissPreview()
```

`previewFailure` is a separate property rather than an empty `previewCard`, because "no card selected" and "this card could not be read" are different things to put on screen — the first invites a selection, the second reports a problem.

## Options Considered

1. **Resolving in the editor over resolving in the view.** A view that reads a repository is a view holding policy, and its behaviour could then only be checked by rendering.
2. **Extending the editor over a separate coordinator.** A coordinator would have to observe the editor's selection, which means duplicating the selection's lifetime and its supersession rule.
3. **Reusing `CardDetailViewModel` over a lighter deck-specific panel.** A second panel would drift: the catalog's would gain a section and the deck's would not. `R1.AC2` exists to make that impossible.
4. **A dismissible panel over a permanent one.** Permanent is simpler and wrong on a laptop, where three columns leave three strips.
5. **Keeping the selected card when dismissed over clearing it.** Clearing makes reopening a second search for something the user had already found.
6. **A quarter of the window over a fixed width.** A fixed width is a quarter of one window size and a half of another.

## Simplicity And Elegance Review

What keeps this small:

- One new property, one new port, and a view that already exists.
- A candidate needs no read, so half of `R1` is a direct assignment.
- The supersession rule is the same one used twice already, so it reads as a pattern rather than as a special case.
- The width rule is the catalog's, applied again rather than invented again.

Challenged once: the deck editor could have navigated to the catalog with the card selected. Rejected because leaving the deck to read a card is the thing this feature exists to stop.

## Failure Modes And Tradeoffs

| Failure | Containment |
| --- | --- |
| The catalog cannot supply the card | `previewFailure` is set and the panel states it (`R1.AC5`) |
| A read returns after the selection moved on | Discarded by generation, as in the browser |
| The editor is built without a reader | Entries do not preview; candidates still do, because they need no read |
| Three columns on a small window | The detail is capped at a quarter with a readable floor (`R2.AC1`, `R2.AC2`) |
| The panel is in the way | Dismissible, and it keeps its card for when it comes back (`R2.AC3`) |
| Full artwork not stored | The thumbnail stands in, which is `card-catalog`'s behaviour (`C3`) |

Accepted tradeoffs:

- **One read per selection.** Holding the resolved cards would avoid it and would go stale the moment a deck is edited elsewhere. A single card read is a primary-key lookup.
- **The first view of any card still fetches its full image.** Unchanged from the catalog, and stated in `C3` rather than discovered.
- **The panel shows deck usage for the deck being edited.** It will say the card is in this deck, which is true and mildly redundant.

## Verification Plan

Proven against stubs with no database and no rendering: a repository that returns a card, one that fails, and one that holds a selection open so a superseded read can be shown to be discarded.

| Check | Observation that decides it |
| --- | --- |
| Selecting an entry previews it | The selected entry's card is the one the panel is given |
| The same card everywhere | A card previewed from a deck carries what the catalog's panel carries |
| Replacing the selection | A second selection changes the card and leaves the deck's entries, order and counts alone |
| A candidate previews | Selecting a search result sets the card with no catalog read |
| Unreadable card | A failing read sets a stated failure rather than leaving the panel blank |
| Nothing selected | A freshly loaded deck has no preview card and no failure |
| Superseded read | A read answered after the selection moved on never reaches the panel |
| Dismissing | Dismissing clears the panel and keeps the card for its return |
| Width cap | The detail is at most a quarter of the window at every width tested |
| Width floor | At the narrowest window the detail is still wide enough to read |
| Keyboard | Selecting, dismissing and restoring are reachable without a pointer |
| Latency | A preview follows a selection within 100 ms |
| Offline | Every section but the full artwork resolves with no network |
| Concurrency | The feature builds under Swift 6 strict concurrency with no diagnostics |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `previewCard`, `previewCandidate`, `previewFailure` and the generation guard on `DeckEditorViewModel`; the first seven checks |
| `R2` | The quarter-width cap with a floor, the dismiss control and the keyboard path; the four layout checks |
| `NFR1` | One primary-key read per selection; measured latency |
| `NFR2` | `CardDetailViewModel` reused unchanged; the same-card check |
| `NFR3` | Every port reading stored rows; the offline check |
| `NFR4` | Keyboard selection and dismissal, and `card-detail`'s own narration |
| `NFR5` | Value types and an actor-isolated editor; the strict-concurrency build check |
