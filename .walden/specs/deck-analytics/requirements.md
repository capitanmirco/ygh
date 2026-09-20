---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-20T14:06:56Z
last_modified: 2026-09-20T14:06:56Z
approved_fingerprint: sha256:ef53229927fc3f0b0899a7a162e30dd1c8e0f1af5edb21854e480647b6a95a5e
---

# Requirements Document

## Introduction

Deck analytics answers the question a duelist asks while tuning a list: how often will this actually happen. It computes the probability of opening a card or a combination, breaks a deck down by its own numbers, and deals real opening hands so that a figure on screen can be felt rather than only read.

This feature covers single-card and combination draw probability, the hand size a format and a play order actually produce, deck composition breakdowns, opening-hand simulation, and the copy-count table that turns a probability into a decision. It does not cover what the user owns, prices, or anything that changes a deck.

Facts established on 2026-09-20, which shape several requirements:

- **The opening hand is not always five cards.** In GOAT, OCG GOAT and Edison the player going first draws on their first turn and acts on six; under the modern rules they do not and act on five. The player going second always draws. Computing five cards for a GOAT deck understates every probability in it.
- **That one card is worth 5.7 percentage points.** Three copies in a forty-card deck open in 33.8% of five-card hands and 39.4% of six-card hands.
- **Deck size matters more than most duelists expect.** The same three copies open in 33.8% of hands at forty cards and 23.3% at sixty — a difference of 10.4 points that a deck builder should be able to see before adding the forty-first card.
- **Combinations are much rarer than their parts.** Three copies of each of two cards open together in only 9.8% of five-card hands, against 33.8% for either alone. A duelist reasoning from the single-card figure will overestimate their deck badly.
- **Only the main deck is drawn from.** The extra and side sections are not part of the population, so a sixty-card list with fifteen extra cards is a forty-five-card population if forty-five is what its main section holds.

## Requirements

### R1 The odds of opening one card

**User Story:** As a duelist tuning a list, I want to know how often a card shows up in my opening hand, so that the number of copies I run is a decision rather than a habit.

#### Acceptance Criteria

1. `R1.AC1` WHEN the user asks for a card's opening odds, the system SHALL report the probability of drawing at least one copy of it.
   - Acceptance check: three copies in a forty-card main deck with a five-card hand reports 0.338 to three decimal places, which is the figure the hypergeometric distribution gives for those inputs.
2. `R1.AC2` WHEN the user asks for a card's opening odds, the system SHALL report the probability of drawing at least each number of copies the deck holds.
   - Acceptance check: a card held three times reports a probability for at least one, at least two and at least three, each no greater than the one before it.
3. `R1.AC3` The system SHALL compute probabilities against the main section alone.
   - Acceptance check: adding fifteen cards to the extra section leaves every reported probability unchanged, and adding one to the main section changes them.
4. `R1.AC4` IF a deck holds no copies of a card, THEN the system SHALL report its probability as zero rather than refusing the question.
   - Acceptance check: a card absent from the deck reports zero for at least one copy, and no error is raised.
5. `R1.AC5` IF the main section holds fewer cards than the hand would draw, THEN the system SHALL report every card it holds as certain.
   - Acceptance check: a three-card main deck with a five-card hand reports 1.0 for a card it holds.

### R2 The odds of opening a combination

**User Story:** As a duelist, I want to know how often two or three specific cards arrive together, so that I stop judging a combo by the odds of its easiest piece.

#### Acceptance Criteria

1. `R2.AC1` WHEN the user asks for the odds of a combination, the system SHALL report the probability of drawing at least one copy of every card named.
   - Acceptance check: three copies each of two cards in a forty-card deck with a five-card hand reports 0.098 to three decimal places.
2. `R2.AC2` The system SHALL report a combination's probability as no greater than the probability of its least likely member.
   - Acceptance check: for any combination the reported figure is at most the smallest single-card figure among its members.
3. `R2.AC3` WHEN a combination names one card only, the system SHALL report the same probability as the single-card calculation.
   - Acceptance check: a one-card combination and the single-card question return identical figures for the same deck and hand.
4. `R2.AC4` IF a combination names a card the deck does not hold, THEN the system SHALL report the combination's probability as zero.
   - Acceptance check: a combination containing one absent card reports zero regardless of its other members.
5. `R2.AC5` WHERE the user requires more than one copy of a card in a combination, the system SHALL account for that requirement.
   - Acceptance check: requiring two copies of a card reports a lower probability than requiring one of the same card in the same deck.

### R3 How many cards the opening hand holds

**User Story:** As a duelist who plays retro formats, I want the maths to use the hand my format actually deals, so that the numbers describe my games rather than someone else's.

#### Acceptance Criteria

1. `R3.AC1` WHERE a deck's format has the first player draw on their first turn, the system SHALL use six cards for the player going first.
   - Acceptance check: a GOAT deck reports six cards on the play, and an identical TCG deck reports five.
2. `R3.AC2` WHERE a deck's format does not have the first player draw, the system SHALL use five cards for the player going first.
   - Acceptance check: a TCG, OCG or Master Duel deck reports five cards on the play.
3. `R3.AC3` The system SHALL use six cards for the player going second in every format.
   - Acceptance check: every supported format reports six cards on the draw.
4. `R3.AC4` WHEN the user changes between going first and going second, the system SHALL recompute every probability it is showing.
   - Acceptance check: switching play order changes the reported figures for a deck whose format draws differently on the two, and changes them for every format when moving from first to second.
5. `R3.AC5` The system SHALL state which hand size a reported probability was computed against.
   - Acceptance check: a reported figure is accompanied by the number of cards it assumes, without the user having to know their format's rule.

### R4 What a deck is made of

**User Story:** As a duelist, I want to see the shape of my deck at a glance, so that a gap in it is visible before a game shows me.

#### Acceptance Criteria

1. `R4.AC1` The system SHALL report how many cards of each type a deck's main section holds.
   - Acceptance check: the reported monster, spell and trap counts sum to the main section's card count.
2. `R4.AC2` The system SHALL report how many monsters of each level a deck's main section holds.
   - Acceptance check: the reported per-level counts sum to the number of monsters that have a level, and monsters without one are not counted among them.
3. `R4.AC3` The system SHALL report how many cards of each attribute and of each race a deck's main section holds.
   - Acceptance check: the per-attribute counts sum to the number of cards carrying an attribute, and the same holds for race.
4. `R4.AC4` The system SHALL count copies rather than distinct cards in every breakdown.
   - Acceptance check: a deck holding three copies of one monster reports three in that monster's level, not one.
5. `R4.AC5` The system SHALL report the breakdown of the extra section separately from the main section.
   - Acceptance check: extra-deck cards appear in the extra breakdown and in none of the main-section figures.

### R5 Dealing real hands

**User Story:** As a duelist, I want to see hands my deck would actually produce, so that a percentage becomes something I can judge.

#### Acceptance Criteria

1. `R5.AC1` WHEN the user asks for an opening hand, the system SHALL deal cards drawn at random from the main section without replacement.
   - Acceptance check: a dealt hand holds the format's hand size, holds no card more times than the deck does, and repeated deals produce different hands.
2. `R5.AC2` WHEN the user deals a hand from a seeded simulation, the system SHALL produce the same hand for the same seed.
   - Acceptance check: two simulations created with one seed deal identical sequences of hands.
3. `R5.AC3` WHEN the user draws a further card, the system SHALL take it from the cards the deck has left.
   - Acceptance check: drawing repeatedly never repeats a copy beyond the number the deck holds, and the remaining count falls by one each time.
4. `R5.AC4` WHEN the user asks how often a condition is met, the system SHALL deal many hands and report the share that met it.
   - Acceptance check: simulating a single card's presence over many hands lands within a small margin of the figure the hypergeometric calculation gives for the same inputs.
5. `R5.AC5` The system SHALL report how many hands a simulated figure was measured over.
   - Acceptance check: a simulated result carries its sample count, so a reader can tell a precise figure from a rough one.

### R6 Turning a probability into a decision

**User Story:** As a duelist deciding between two and three copies, I want to see what each choice would do, so that the trade is visible instead of guessed.

#### Acceptance Criteria

1. `R6.AC1` WHEN the user asks about a card, the system SHALL report the opening probability the deck would have at each copy count from one to three.
   - Acceptance check: the reported figures rise with each additional copy and match the single-card calculation for each count.
2. `R6.AC2` The system SHALL report how the opening probability would change if the main section grew or shrank by cards the user names.
   - Acceptance check: a forty-card deck and the same deck reported at sixty give figures that differ by the amount the hypergeometric distribution gives.
3. `R6.AC3` The system SHALL report every probability as a proportion between zero and one inclusive.
   - Acceptance check: no reported figure falls outside that range for any deck, hand size or copy count.

## Non-Functional Requirements

- `NFR1` Responsiveness: every exact probability in `R1`, `R2` and `R6` is computed within 10 ms for a sixty-card deck, so the figures can follow an edit rather than a button. Bridged by `R1.AC1`, `R2.AC1` and `R6.AC1`.
- `NFR2` Numerical soundness: probabilities are computed without overflowing or losing precision on the binomial coefficients a sixty-card deck produces, and every reported figure lies between zero and one. Bridged by `R6.AC3` and `R2.AC2`.
- `NFR3` Determinism: a simulation given a seed produces the same hands on every run and on every machine, so a reported figure can be reproduced. Bridged by `R5.AC2`.
- `NFR4` Honesty: a simulated figure is never presented as an exact one, and an exact figure always states the hand size it assumed. Bridged by `R5.AC5` and `R3.AC5`.
- `NFR5` Offline operation: every calculation reads the stored deck and catalog, so nothing here needs a network. Bridged by the stored-deck acceptance checks on `R1.AC1` and `R4.AC1`.
- `NFR6` Accessibility: the breakdowns and probability tables are reachable by keyboard alone, and each figure is readable by assistive technology as a sentence naming the card, the probability and the hand size. Bridged by `R3.AC5` and `R6.AC1`.
- `NFR7` Concurrency safety: the feature builds and runs under Swift 6 strict concurrency checking with no data-race diagnostics suppressed.

## Constraints And Dependencies

- `C1` This feature reads the decks produced by `deck-builder` and the card data produced by `card-catalog`. It reuses the `DeckCardIndex` snapshot rather than querying per card.
- `C2` The first-turn draw rule is not published by the catalog. That GOAT, OCG GOAT and Edison have the first player draw, and that the modern formats do not, is knowledge this application encodes, taken from those formats' own rule documents.
- `C3` The calculation models the opening hand only. It accounts for no card effect, no search, no mulligan and no deck thinning, so a figure describes what is drawn rather than what is played. Decks built around searchers will see their real consistency understated.
- `C4` Speed Duel and Duel Links use different deck sizes and opening hands and are not modelled. A deck in one of those formats is computed against the modern rule, which will be wrong for it.
- `C5` A simulated figure carries sampling error. It converges on the exact figure as hands are dealt but is never equal to it, which is why `R5.AC5` requires the sample count to travel with the number.
- `C6` Target platform is macOS 27 on arm64, built with Swift 6.4 and Swift Package Manager.

## Out Of Scope

- Whether the user owns the cards, covered by `collection-tracker`.
- Prices and deck value, covered by `pricing`.
- Suggesting changes to a deck, or ranking decks against each other.
- Modelling card effects, searchers, mulligans or anything after the opening hand.
- Probability across a whole game, or across multiple turns.
- Comparing a deck against a metagame, which would need data the catalog does not publish.
