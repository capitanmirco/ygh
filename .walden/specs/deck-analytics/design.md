---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-20T14:09:51Z
last_modified: 2026-09-20T14:09:51Z
approved_fingerprint: sha256:784280ab087167cfd9d4431441fb0d7322ca25dc15d0fc78d2c6c9196626264d
source_requirements_approved_at: 2026-09-20T14:06:56Z
source_requirements_fingerprint: sha256:ef53229927fc3f0b0899a7a162e30dd1c8e0f1af5edb21854e480647b6a95a5e
---

# Feature Design

## Architecture

Every calculation is a pure function over a deck and a snapshot of its cards. Nothing here touches a database, a network or a view, which is what lets each probability be checked against a figure computed by hand.

### Module graph

```
App ─▶ YGOFeatureAnalytics ─┐
                            ├─▶ YGOCore   (deck, index, hand size rule)
YGOAnalytics (the maths) ───┘
```

`YGOAnalytics` depends on `YGOCore` alone. The feature module renders what it returns.

### The hand never exceeds six cards, and that decides the arithmetic

Every binomial coefficient this feature needs has `k ≤ 6`, because the opening hand is five or six cards. The largest one a sixty-card deck can produce is `C(60, 6) = 50,063,860` — eleven orders of magnitude below `Int64`'s ceiling.

So the coefficients are computed in **exact integer arithmetic**, and the probability is one division at the end. There is no overflow to guard against, no logarithms, no floating-point error accumulating through a sum, and `NFR2` is satisfied by the shape of the problem rather than by a numerical technique.

A general hypergeometric library would have had to reach for log-gamma, because `C(60, 30)` is 1.18 × 10¹⁷ and a general `k` can be half the population. This one never needs that, and saying so is what keeps a later reader from "improving" it into floating point.

### Where the hand size comes from

```swift
extension CardFormat {
    var firstPlayerDraws: Bool   // GOAT, OCG GOAT, Edison
}
```

The catalog does not publish this. That the pre-2017 formats have the first player draw, and the modern ones do not, is knowledge this application encodes from those formats' own rule documents, and it is worth one line in a type rather than a constant buried in a calculation.

A GOAT deck opens on six cards and a TCG deck on five. That one card is 5.7 percentage points on three copies in forty, so getting it wrong would make every figure in this feature quietly wrong for the user's own decks.

## Data Model

No schema change. Analytics reads what `deck-builder` already stores.

`DeckCardIndex.Entry` gains the fields the breakdowns need, which it does not carry today:

```swift
// Added to the existing entry.
let type: String          // "Effect Monster", "Spell Card", …
let level: Int?           // absent for spells, traps and links
let attribute: CardAttribute?
let race: String
```

This is additive: the entry gains stored fields and no existing behaviour changes. It does invalidate `deck-builder`'s and `collection-tracker`'s evidence, so both are re-verified as part of this work rather than left claiming a code identity they no longer have.

<!-- assumed: the breakdowns read DeckCardIndex rather than a new query (source: C1, which requires reusing the snapshot rather than querying per card) -->

## Options Considered

1. **Exact integers over log-gamma.** The usual way to compute a hypergeometric probability is in log space, because the coefficients overflow. Here they cannot: the hand caps `k` at six. Integers give an exact answer, a test can assert a figure to any number of decimals, and there is no tolerance to argue about.
2. **Direct enumeration over inclusion-exclusion for combinations.** Inclusion-exclusion is shorter for "at least one of each", but it does not extend to `R2.AC5`, where the user asks for two copies of one piece. Enumerating the draw counts handles both, and with a hand of six the sum has a few dozen terms.
3. **Extending `DeckCardIndex` over a second snapshot.** A separate query for level and attribute would avoid touching a type two other specifications depend on. It would also mean two snapshots that can disagree about the same deck, and a second round trip on every edit. The entry is loaded once either way.
4. **A seeded generator of our own over `SystemRandomNumberGenerator`.** The system generator cannot be seeded, so a simulated figure could never be reproduced or tested. SplitMix64 is sixty lines, is specified exactly, and gives the same sequence on every machine, which is what `NFR3` asks for.
5. **Simulation as a complement to the exact figure, not a replacement.** Every question this feature answers exactly is answered exactly. Simulation exists for `R5`, where a duelist wants to see hands, and for conditions the closed form does not cover. Its results carry their sample count so the two are never confused.

## Simplicity And Elegance Review

What keeps this small:

- One function computes the hypergeometric probability, and the single-card, combination and copy-count questions are all callers of it. `R2.AC3` — that a one-card combination equals the single-card answer — is true by construction rather than by a test that keeps two code paths honest.
- The breakdowns are one pass over the deck's slots, accumulating into dictionaries keyed by what is being counted. There is no chart model, no series type and no aggregation framework; the view groups what it is given.
- The simulator holds a shuffled array and an index. Drawing is reading the next element. There is no deck object to keep in sync with itself.
- Hand size is a property of the format, so no calculation takes it as a parameter the caller might get wrong.

Challenged once: the maths could live in `YGOValidation`, which already holds pure functions over a `DeckCardIndex`, saving a module. Rejected because validation answers whether a deck is legal and this answers how it behaves; a reader looking for one should not have to read the other.

## Failure Modes And Tradeoffs

| Failure | Containment |
| --- | --- |
| A deck smaller than the hand | Every card it holds is certain, reported as 1.0 rather than as a division by a negative count (`R1.AC5`) |
| A card the deck does not hold | Zero, not an error: asking is how a duelist explores adding it (`R1.AC4`) |
| A combination naming an absent card | Zero, whatever its other members do (`R2.AC4`) |
| An empty main section | Every probability is zero and no division by zero occurs |
| A format this feature does not model | Computed against the modern rule and stated as such; Speed Duel and Duel Links are wrong here and `C4` says so |
| A simulated figure read as exact | The sample count travels with it (`R5.AC5`), and the two are rendered differently |

Accepted tradeoffs:

- **The model stops at the opening hand.** No searcher, no mulligan, no effect. A deck built on searchers will read as less consistent than it plays, and `C3` says so rather than letting the user infer otherwise.
- **Simulation carries sampling error.** It converges but never equals, which is why nothing that can be computed exactly is simulated.
- **Extending `DeckCardIndex` costs a re-verification** of two sealed specifications. The alternative, a second snapshot, would have cost a source of disagreement for as long as the application lives.
- **Speed Duel and Duel Links are computed wrongly.** Modelling them means different deck sizes and hand sizes for formats the user does not play, so they are declared unmodelled rather than approximated silently.

## Verification Plan

The maths is tested against figures computed independently, not against its own output. Four of them are stated in the requirements and were calculated before any code existed: 0.338, 0.394, 0.233 and 0.098.

| Check | Observation that decides it |
| --- | --- |
| Single card, known figure | Three copies in forty with a five-card hand gives 0.338 to three decimals |
| Larger hand | The same deck on six cards gives 0.394, and the difference is the 5.7 points the requirements state |
| Larger deck | The same three copies in sixty gives 0.233 |
| At least *k* copies | The figures for at least one, two and three are non-increasing, and at least one equals one minus the chance of none |
| Main section only | Adding fifteen extra-deck cards changes nothing; adding one main-deck card changes every figure |
| Absent card | Zero, with no error raised |
| Deck smaller than the hand | Every held card reports 1.0 |
| Combination, known figure | Three and three in forty on five cards gives 0.098 |
| Combination bound | For a hundred random decks and combinations, the combination never exceeds its least likely member |
| One-card combination | Identical to the single-card figure, for the same inputs |
| Combination with an absent member | Zero regardless of the others |
| Requiring two copies | Lower than requiring one of the same card in the same deck |
| Hand size by format | GOAT, OCG GOAT and Edison report six on the play; TCG, OCG and Master Duel report five; all report six on the draw |
| Play order changes figures | Switching to going second changes every reported figure for a modern-format deck |
| Hand size is stated | A reported figure carries the hand size it assumed |
| Type breakdown | Monster, spell and trap counts sum to the main section's size |
| Level breakdown | Per-level counts sum to the monsters that have a level, and none of the others appear |
| Attribute and race breakdowns | Each sums to the cards carrying that property |
| Copies, not distinct cards | Three copies of one monster contribute three to its level |
| Sections separated | Extra-deck cards appear only in the extra breakdown |
| Dealt hand shape | A hand holds the format's size, no card more often than the deck does, and repeated deals differ |
| Seeded reproducibility | Two simulators with one seed deal identical sequences |
| Drawing further | Never exceeds the copies held; the remaining count falls by one each draw |
| Simulation agrees with the closed form | Over many hands, the simulated share of a single card's presence lands within a small margin of the exact figure |
| Sample count reported | A simulated result carries how many hands it measured |
| Copy-count table | Figures for one, two and three copies rise, and each equals the single-card calculation at that count |
| Deck-size comparison | Forty against sixty differ by what the distribution gives |
| Range | No figure falls outside zero to one, over a sweep of decks, hands and counts |
| Exact-calculation latency | Every exact figure for a sixty-card deck is computed within 10 ms |
| Integer exactness | The largest coefficient a sixty-card deck produces is computed without loss, and equals the value computed independently |
| Offline | Every calculation answers with no network available |
| Accessibility | Each figure reads as a sentence naming the card, the probability and the hand size; tables are keyboard reachable |
| Concurrency | The new modules build under Swift 6 strict concurrency with no data-race diagnostics |
| Other specifications still sound | `deck-builder` and `collection-tracker` proofs pass after `DeckCardIndex` gains its fields |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `Hypergeometric.probabilityOfAtLeast` over the main section; the known-figure, at-least-*k*, main-only, absent-card and small-deck checks |
| `R2` | `Hypergeometric.probabilityOfCombination` by direct enumeration of draw counts; the known-figure, bound, one-card, absent-member and two-copy checks |
| `R3` | `CardFormat.firstPlayerDraws` and `OpeningHand.size(format:playingFirst:)`; the hand-size, play-order and stated-size checks |
| `R4` | `DeckBreakdown` in one pass over the slots, reading the extended `DeckCardIndex`; the five breakdown checks |
| `R5` | `HandSimulator` over a seeded SplitMix64 generator; the shape, reproducibility, drawing, agreement and sample-count checks |
| `R6` | The same hypergeometric function called across copy counts and deck sizes; the table, comparison and range checks |
| `NFR1` | Integer arithmetic with `k ≤ 6`; measured latency on a sixty-card deck |
| `NFR2` | Exact integers rather than log-gamma, which the hand size makes possible; the range and integer-exactness checks |
| `NFR3` | SplitMix64 with an explicit seed; the reproducibility check |
| `NFR4` | Sample counts on simulated results and hand sizes on exact ones; those two checks |
| `NFR5` | Pure functions over a loaded deck; the offline check |
| `NFR6` | Figures carrying card, probability and hand size; the accessibility check |
| `NFR7` | Value types and pure functions throughout; the strict-concurrency build check |
