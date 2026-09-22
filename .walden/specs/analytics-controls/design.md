---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-22T14:45:19Z
last_modified: 2026-09-22T14:45:19Z
approved_fingerprint: sha256:5bcdf52a908fa6b030051370666cd9c58ff2b0fee4009098ecf163e82c652c9e
source_requirements_approved_at: 2026-09-22T14:43:54Z
source_requirements_fingerprint: sha256:d6672ecc8eaf465a1c5fe87c63a11d2a924bb68518778f96d6cfa3fbb3757fca
---

# Feature Design

## Architecture

Three choosers over ports the application already has, and one copy of a deck that is never stored.

```
YGOFeatureAnalytics ──▶ YGOCore (DeckRepository, DeckListJudging,
   AnalyticsViewModel            BanlistHistoryReading, CardFormat)
   AnalyticsControls
                        SQLiteDeckRepository   (decks and their indexes)
                        SQLiteBanlistHistory   (lists and verdicts)
```

No table, no column, no migration, and no new arithmetic: every figure still comes from `YGOAnalytics`, and the verdict is the one `deck-legality` already computes.

### The assumed format is a copy, not a setting

`recompute()` reads `deck.format` — through `Hypergeometric.odds`, `HandSimulator` and `OpeningHand` — so the format reaches the arithmetic by travelling inside the deck value. Assuming another one therefore needs no change to the engine at all:

```swift
/// The deck as the figures read it: the chosen deck, with the assumed format
/// substituted. It is a value, and nothing writes it back.
private var readingDeck: Deck? {
    guard var deck = chosenDeck else { return nil }
    if let assumedFormat { deck.format = assumedFormat }
    return deck
}
```

`R2.AC4` is then structural rather than a promise: the model holds no writing port, and the only mutated `Deck` is a local copy that dies with the computation. The stored deck is read, never written.

<!-- assumed: the assumed format substitutes into a copy rather than being threaded through every analytics call (source: YGOAnalytics already takes a Deck and reads its format; widening five certified signatures to carry a format beside the deck would be the same information in two places) -->

### What the model gains

```swift
@MainActor @Observable public final class AnalyticsViewModel {
    // What to read
    public private(set) var decks: [Deck] = []
    public private(set) var chosenDeck: Deck?
    /// Nil means the deck's own format. Set means "read it as if".
    public private(set) var assumedFormat: CardFormat?
    /// The format every figure on screen was computed under.
    public var readingFormat: CardFormat? { assumedFormat ?? chosenDeck?.format }
    public var isReadingAnotherFormat: Bool { assumedFormat != nil && assumedFormat != chosenDeck?.format }

    // What to measure against
    public private(set) var availableLists: [BanlistRevision] = []
    public private(set) var chosenList: BanlistRevision?
    public private(set) var verdict: DeckListVerdict?
    public private(set) var formatHasNoList = false

    public func loadDecks() async
    public func choose(deckID: Int64) async
    public func assume(format: CardFormat?) async
    public func measure(against list: BanlistRevision) async
}
```

`load(deck:index:)` stays exactly as it is: `deck-analytics` is certified through it, and `choose(deckID:)` reads the deck and its index and calls it with the reading copy.

### Choosing anything clears the hand

`R4.AC2` exists because a hand left on screen after the format changed would be six cards shown under a five-card rule — a picture that contradicts every number beside it. So `chosenDeck`, `assumedFormat` and the play order all clear `dealtHand` before recomputing, and the hand comes back only when the user asks for one.

The existing `setPlayingFirst` already recomputes; it now clears the hand too, which is the same rule applied to the choice that was already there.

### The verdict is borrowed, not rebuilt

`DeckListJudging.judge(_:against:effectiveDate:)` and `DeckListVerdict` come from `deck-legality`. This screen reads the verdict and shows one line of it: how many cards are over, and the list it came from. The per-card panel stays in the editor, which is where a card is something you can act on.

Resolving which list a format implies is the same rule in two screens now, so it moves out of `DeckEditorViewModel` into a function over the stored revisions:

```swift
public extension BanlistRevision {
    /// The list a format is played under, chosen from what is stored.
    static func implied(for format: CardFormat, in stored: [BanlistRevision]) -> BanlistRevision?
}
```

The editor keeps its `impliedList(for:)` method, delegating, so `deck-legality`'s proofs keep describing the behaviour they were written for.

### Nothing here is a presentation

Three `Menu`s and a `Picker`, like the rest of this application's recent additions. The statistics screen holds no alert and no sheet, and this adds none.

### No deck at all is a state, not an empty menu

`R1.AC4`: with nothing stored, the screen says there is nothing to analyse. An empty chooser beside empty figures would leave the user looking for the deck they never made.

## Options Considered

**Threading the assumed format through the analytics calls.** `Hypergeometric.odds(for:in:index:playingFirst:)` and its neighbours could take a format beside the deck. Rejected: five certified signatures would carry the same information twice, and the deck value already holds it. A copy expresses "read this deck as if it were Edison" exactly, and cannot leak into storage.

**Showing the per-card legality panel here.** The editor's panel is built and would drop in. Rejected: it is the same screen in two places, and a card list is useful where cards can be changed. One line here, the panel there.

**Putting the deck chooser in the sidebar for the statistics section.** The sidebar already lists decks for the deck section, so showing it here too would need no new control. Rejected: the sidebar's list is a navigation list that sets the window's selection, and the statistics would then still be describing "the selection" rather than a subject of their own — which is the complaint. A chooser on the screen says what the figures are about.

**Excluding forbidden cards from the figures.** Tempting, and out of scope by decision: the odds describe the deck as built, and a deck that cannot be played is told so rather than quietly altered.

## Simplicity And Elegance Review

One computed property carries the whole of the assumed format, because the engine already reads the format from the deck. No signature changes, no new arithmetic, no second verdict.

The first draft had `chosenDeckID` beside `chosenDeck`, and `readingFormat` stored and refreshed. Both were a second copy of something already held: the identifier is on the deck, and the reading format is a function of two values. They went.

Coupling stays where the constitution puts it: the feature module sees four `YGOCore` protocols and types, and the composition root binds them to objects it already builds.

## Failure Modes And Tradeoffs

**A deck deleted while the statistics show it.** The chooser is re-read when the screen opens; a deck that has gone leaves the figures as they were until another is chosen, and choosing a missing deck reports rather than emptying the screen.

**An assumed format this application does not model.** Speed Duel and Duel Links have deck sizes and opening hands `deck-analytics` already records as unmodelled. Assuming one inherits that, and the screen names the format it assumed so the reader can tell.

**A format with no published list.** Reported as no verdict, never measured against a list that does not govern it — the same stance `deck-legality` takes.

**The hand and the figures disagreeing.** Prevented by clearing rather than by recomputing: a stale hand is worse than no hand, because it looks like evidence.

**The verdict describes the stored deck, the odds describe the assumed one.** A deck read as TCG is still stored as GOAT, and the list it is measured against is chosen separately. Both are named on screen, which is `NFR1`, and the two questions stay distinct rather than being merged into one misleading answer.

## Verification Plan

New suite `AnalyticsControlsTests` in `YGOSyncTests`, beside the other screen-level proofs. Both the name and the path were checked unused. Everything runs against a temporary database seeded from the deck fixtures.

| What | Where | How it is observed |
| --- | --- | --- |
| Every stored deck is offered | `AnalyticsControlsTests` | with two decks stored, both appear in the chooser, ordered as the library orders them |
| Choosing a deck reports its figures | `AnalyticsControlsTests` | choosing a deck of a different size changes the reported deck size and the odds |
| The figures name their deck | `AnalyticsControlsTests` | the model reports the chosen deck's name |
| No decks at all | `AnalyticsControlsTests` | with an empty library the model reports that there is nothing to analyse, and offers no deck |
| Opening on a deck chosen elsewhere | `AnalyticsControlsTests` | a model told to start on a deck starts on it |
| Reading a deck as another format | `AnalyticsControlsTests` | a GOAT deck read as TCG reports a five-card opening hand for the player going first, and six as GOAT |
| Every figure follows the assumed format | `AnalyticsControlsTests` | the odds for one card differ between the two readings of the same deck, and match the hand size reported |
| The assumption is named | `AnalyticsControlsTests` | reading a GOAT deck as TCG reports that the figures assume TCG and that it is not the deck's own |
| The deck is never written | `AnalyticsControlsTests` | after four assumed formats the deck read from storage still reports GOAT, with identical slots |
| A verdict against a list | `AnalyticsControlsTests` | a deck holding a forbidden card reports how many cards are over, and the list's name and date |
| Changing the list changes the verdict | `AnalyticsControlsTests` | the same deck measured against the March 2005 and March 2010 lists reports different counts |
| A format with no list | `AnalyticsControlsTests` | a Speed Duel deck reports no verdict and says so |
| Measuring never writes | `AnalyticsControlsTests` | the deck's slots and format are identical after several measurements |
| The hand comes from the chosen deck | `AnalyticsControlsTests` | a hand dealt after switching decks holds only names the new deck contains |
| The hand clears on every choice | `AnalyticsControlsTests` | a dealt hand is empty again after changing the deck, the assumed format, and the play order |
| The hand's size follows the assumption | `AnalyticsControlsTests` | six cards read as GOAT going first, five read as TCG going first, six going second in both |
| The controls exist | `AnalyticsControlsTests` | source assertion that the choosers are declared in the analytics view, plus the app target building |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `decks`, `chosenDeck`, `loadDecks`, `choose(deckID:)`, and the empty-library state |
| `R2` | `assumedFormat`, the `readingDeck` copy, `readingFormat` and `isReadingAnotherFormat`, and the absence of any writing port |
| `R3` | `DeckListJudging` bound to `SQLiteBanlistHistory`, `BanlistRevision.implied(for:in:)`, `verdict` and `formatHasNoList` |
| `R4` | Clearing `dealtHand` on every choice, and `HandSimulator` driven by the reading copy |
| `NFR1` | The deck's name, the reading format, the play order and the verdict's list all reported |
| `NFR2` | Only a local copy is mutated; the model holds no writing port |
| `NFR3` | Decks and lists are read from the local database; no client and no transport is involved |
| `NFR4` | Menus and a picker, keyboard reachable, each announcing what it selects |
