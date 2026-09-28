---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-27T12:21:34Z
last_modified: 2026-09-27T12:21:34Z
approved_fingerprint: sha256:9a0da7567fe59ee1d73b1908f03ffd1697d952120413711bee6c9cfabf3729bd
source_requirements_approved_at: 2026-09-27T12:18:13Z
source_requirements_fingerprint: sha256:40302586f1d60a3d63f549e2fe182b48c6bebdf1329e9d4ab569a1318dbfb2a2
---

# Feature Design

## Architecture

Three pieces, each on an existing seam.

**A port for card names, in `YGOCore`.** `CardNaming` declares `cardNames(for: Set<CardIdentifier>) async throws -> [CardIdentifier: String]`. `SQLiteCollectionRepository` already has exactly this method — Italian where the catalog has a translation, English otherwise — so conformance is one line in `YGOPersistence`. The feature module keeps depending on `YGOCore` alone.

**The panel's subject, in `CollectionViewModel`.** Two optional dependencies join the initializer, both defaulted to `nil` so every existing caller and test compiles unchanged: `library: (any DeckRepository)?` for the decks and `naming: (any CardNaming)?` for the names. The model gains:

- `decks: [Deck]`, the library as `allDecks()` orders it, and `chosenShortfallDeck: Deck?`.
- `shortfallReport: ShortfallReport`, the one value the panel draws:

```swift
public enum ShortfallReport: Hashable, Sendable {
    case noDecks                                   // R2.AC2
    case chooseADeck                               // R2.AC1
    case unavailable(deckName: String?)            // R2.AC3
    case satisfied(deckName: String)               // R2.AC4
    case missing(deckName: String, entries: [ShortfallEntry])  // R1.AC2, R1.AC4
}
```

  Each case carries a `headline` sentence in Italian, so the panel and a screen reader say the same thing and a proof can read it without rendering. "Nothing to buy" exists only in `.satisfied`, which is only produced by a successful computation that found nothing missing — honesty is a property of the type, not of the view.

- `startShortfall(on deckID: Int64?)` reads the library, then chooses `deckID` if the library holds it, or settles on `.noDecks` / `.chooseADeck`.
- `chooseShortfallDeck(_ deckID: Int64)` reads the deck, the names of its cards and the owned copies, and hands them to `ShortfallCalculator` through the existing `computeShortfall(for:names:)`. Any read that throws ends in `.unavailable`.
- `computeShortfall(for:names:)` keeps its signature. Its owned-copies read changes from `try?` — which turned a failure into "owns nothing" — to a caught error that sets `.unavailable`.
- `reload()`, which every write on the screen already ends with, recomputes the report for the chosen deck from the deck and names it already holds, so recording a copy updates the list (R3.AC1) without re-reading the deck.

`shortfall` and `isShortfallSatisfied`, which `collection-tracker`'s proofs read, become computed from `shortfallReport`: the entries of `.missing`, and "the report is `.satisfied`". For every successful computation they return what they returned before.

**The panel, in `CollectionView`.** A `Menu` listing the decks (name · format), labelled with the chosen deck's name or "Scegli un mazzo", above a `switch` over `shortfallReport`. The screen's `.task` calls `startShortfall(on:)` with a `startingDeck` the view now takes, then `reload()`. The composition root passes `library: environment.deckRepository`, `naming: environment.collection` and `startingDeck: selectedDeck`.

Data flow: window selection → `startShortfall` → `allDecks` → `chooseShortfallDeck` → `deck(with:)` + `cardNames(for:)` + `ownedCopiesByCard()` → `ShortfallCalculator.shortfall` → `ShortfallReport` → panel. Nothing on the path writes.

## Options Considered

- **Chosen: extend `CollectionViewModel`.** The writes that must refresh the report (R3.AC1) already end in its `reload()`, and the certified `computeShortfall` already lives there. One model, one refresh path.
- **A separate `ShortfallViewModel` owned by the panel.** Cleaner in isolation, but the collection model's writes would have to notify it, and `computeShortfall` would exist twice — the stale-second-copy shape this project has already paid for in the deck list. Rejected.
- **Names from `DeckRepository.cardIndex(for:)`.** Already on the deck port, so no new port. But it reads `name_en` only, and `C2` asks for the Italian names the collection screen shows. Rejected.
- **Adding `cardNames` to `CollectionReading`.** No new protocol, but every existing conformer — including the certified proofs' test doubles — would have to implement it, or a default implementation would silently return no names. Rejected in favour of a separate port.
- **A `Picker` bound to the chosen deck instead of a `Menu`.** Equivalent for the keyboard; the `Menu` matches `analytics-controls`, so the two screens that choose a deck choose it the same way.

## Simplicity And Elegance Review

- No new calculation: the arithmetic stays `ShortfallCalculator`'s (`C1`).
- No table, column or migration (`C3`); one protocol with one method, satisfied by a method that already exists.
- One enum decides every sentence the panel can say. The view has a `switch` and no conditions of its own, so a state that is not modelled cannot be drawn.
- No presentation: a `Menu` and inline text. The collection screen's one confirmation dialog is untouched, and this adds nothing that could compete with it — the trap this project fell into five times.
- Optional dependencies defaulted to `nil`: `collection-tracker`'s proofs build the model exactly as before.

## Failure Modes And Tradeoffs

- **A read fails** (library, deck, names or owned copies): `.unavailable`, drawn as "the answer is not available", never as a list or as nothing missing (R2.AC3). Names failing is treated like the rest rather than falling back to "Carta 1234" lines, because a list of numbers is not an answer the user can act on.
- **Two choices in quick succession**: a generation counter, as the deck editor's search uses. A result that arrives after a later choice is discarded, so the last deck chosen is the one reported.
- **The chosen deck is deleted or edited in the deck section** while the collection screen holds it: accepted. Changing section rebuilds the collection screen, which starts again from the library, so the stale value lives only until the user comes back. Reported here rather than solved with a notification path nobody else needs.
- **A deck the library no longer holds is the window's selection**: `startShortfall` does not find it among `decks` and settles on `.chooseADeck` instead of reporting on it.
- **Tradeoff**: `CollectionViewModel` grows by the chooser's state. Accepted for the single refresh path; the enum keeps the new branches out of the view.

## Verification Plan

New suite `CollectionShortfallTests` in `YGOSyncTests`, beside `collection-tracker`'s own screen proofs. The file path and the suite name are to be checked unused before writing. Everything runs against a temporary database seeded by `CollectionFixture`, which holds real cards, a deck repository and a collection repository.

| What | How it is observed |
| --- | --- |
| Every stored deck is offered (R1.AC1) | with three decks stored, `decks` holds all three in library order |
| Choosing reports what is missing (R1.AC2) | a deck asking for three copies of a card held once reports that card needing two, under the name `cardNames` gives it |
| Choosing another deck replaces the report (R1.AC3) | a card only the first deck needs is gone after choosing the second |
| The report names its deck (R1.AC4) | `.missing` and `.satisfied` carry the chosen deck's name, and the headline reads it |
| Starting from the window's deck (R1.AC5) | `startShortfall(on:)` with a deck's identifier reports on that deck |
| Nothing is written (R1.AC6) | `deck_slot` and `collection_entry` are identical before and after choosing each deck |
| No deck chosen (R2.AC1) | after `startShortfall(on: nil)` the report is `.chooseADeck`, `isShortfallSatisfied` is false and the headline does not say nothing is missing |
| Empty library (R2.AC2) | with no deck stored the report is `.noDecks` and `decks` is empty |
| A failed read (R2.AC3) | with a collection reader whose owned-copies read throws, the report is `.unavailable`, `shortfall` is empty and `isShortfallSatisfied` is false |
| Nothing missing, said with the name (R2.AC4) | after recording every copy a deck asks for, the report is `.satisfied` with that deck's name |
| The report follows the collection (R3.AC1) | recording one copy of a card the chosen deck needs two of lowers the need to one without choosing again |
| The port answers Italian names (C2) | `SQLiteCollectionRepository` used as `any CardNaming` returns the Italian name of a translated card |
| The panel and its wiring exist (NFR3, NFR4) | source assertions that `CollectionView` declares the deck chooser with an accessibility label and calls `startShortfall(on:`, and that the composition root passes `naming: environment.collection`; plus `swift build` of the app target |
| `collection-tracker` is unchanged | its existing shortfall proofs, re-run by `walden verify collection-tracker` |

The drawn panel — the menu opening, the headline changing — is checked by hand in the running application (`C4`).

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `CollectionViewModel.startShortfall` / `chooseShortfallDeck` over `DeckRepository` and `CardNaming`, the deck `Menu` in `CollectionView`; checked by the R1 rows of `CollectionShortfallTests` |
| `R2` | `ShortfallReport` cases `.chooseADeck`, `.noDecks`, `.unavailable`, `.satisfied` and their headlines; checked by the R2 rows |
| `R3` | `reload()` recomputing from the held deck and names; checked by the R3 row |
| `NFR1` | `.satisfied` produced only by a successful computation, every non-empty case carrying the deck's name; checked by the R1.AC4, R2.AC1, R2.AC3 and R2.AC4 rows |
| `NFR2` | no writing port on the shortfall path; checked by the R1.AC6 row |
| `NFR3` | local reads only (`DeckRepository`, `CardNaming`, `CollectionReading`); checked by the wiring assertion and the fixture-only suite |
| `NFR4` | the `Menu`'s accessibility label, and each entry's existing `sentence`; checked by the source assertion and by hand |
