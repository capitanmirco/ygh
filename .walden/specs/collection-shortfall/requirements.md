---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-27T12:18:13Z
last_modified: 2026-09-27T12:18:13Z
approved_fingerprint: sha256:40302586f1d60a3d63f549e2fe182b48c6bebdf1329e9d4ab569a1318dbfb2a2
---

# Requirements Document

## Introduction

The collection screen has a panel headed "Cosa manca". It is meant to answer what a deck still needs before it can be built from the cards on hand, and `collection-tracker` certified the arithmetic behind it. The panel has never been given a deck. It draws an empty answer, and an empty answer reads "Niente da comprare per questo mazzo" — nothing to buy — whichever deck the user has in mind.

Facts measured on 2026-09-27:

- **`computeShortfall(for:names:)` has no caller outside the tests.** The collection screen is built from a collection reader, a writer and the catalog search, and no deck reaches it, so the report it draws is always empty.
- **An empty report is drawn as a verdict.** "Niente da comprare per questo mazzo" appears with no deck chosen and no deck named.
- **The statement is the opposite of the truth for every stored deck.** The collection holds one lot. LR-Chaos Turbo misses 69 copies of 49 cards, Lockdown Burn 40 copies of 22, Vayu Turbo 67 copies of 45, and the panel says each needs nothing.
- **A failed read has the opposite failure.** The owned copies are read with `try?`, so a read that fails becomes a collection that owns nothing, and every card of the deck would be reported missing.
- **The names are already available.** The collection repository answers card names for a set of cards, Italian where the catalog has a translation and English otherwise, and the view model does not receive them.
- **The panel has a heading, a focus region and sentences built for assistive technology.** What it lacks is a subject.

This feature gives the panel its subject: the user chooses the deck, the panel reports what that deck needs, and it says nothing it does not know.

## Requirements

### R1 Choosing the deck

**User Story:** As a duelist looking at my collection, I want to say which deck I am checking it against, so that the list of what to buy is about the deck I mean to build.

#### Acceptance Criteria

1. `R1.AC1` The system SHALL let the user choose, from the collection screen, which stored deck the shortfall report describes.
   - Acceptance check: with three decks stored, all three are offered and any of them can be chosen without leaving the collection screen.
2. `R1.AC2` WHEN the user chooses a deck, the system SHALL report each card that deck needs more copies of than the collection holds, with the number still needed.
   - Acceptance check: choosing a deck that asks for three copies of a card the collection holds once reports that card as needing two more.
3. `R1.AC3` WHEN the user chooses another deck, the system SHALL replace the report with the one for the deck now chosen.
   - Acceptance check: switching between two decks with different shortfalls changes the listed cards, and a card only the first deck needs is no longer listed.
4. `R1.AC4` The system SHALL name the deck the report describes.
   - Acceptance check: the report reads the chosen deck's name, not only its lines.
5. `R1.AC5` WHEN the collection screen opens while a deck is selected in the deck list, the system SHALL start the report from that deck.
   - Acceptance check: a deck selected in the deck list is the one the report opens on, without choosing it again. <!-- assumed: start from the window's selection (source: analytics-controls requirements, R1 "Choosing the deck") -->
6. `R1.AC6` The system SHALL leave every deck and the collection unchanged by choosing a deck and reporting its shortfall.
   - Acceptance check: deck slots and collection entries are identical before and after choosing each stored deck in turn.

### R2 Saying only what is known

**User Story:** As a duelist, I want the panel to tell me nothing is missing only when that is true, so that I never go to a tournament short of cards because a screen was empty.

#### Acceptance Criteria

1. `R2.AC1` WHILE no deck is chosen, the system SHALL invite the user to choose one instead of reporting that nothing is missing.
   - Acceptance check: with no deck chosen, the panel shows no "nothing to buy" statement, lists no card and asks for a deck.
2. `R2.AC2` WHERE no deck is stored, the system SHALL say that there is no deck to compare the collection against instead of offering an empty chooser.
   - Acceptance check: with an empty library the panel explains that there is no deck, and offers nothing to choose.
3. `R2.AC3` IF the chosen deck or the collection cannot be read, THEN the system SHALL report that the shortfall could not be computed instead of a list or its absence.
   - Acceptance check: with the read of owned copies failing, the panel lists no card, does not state that nothing is missing, and says the answer is unavailable.
4. `R2.AC4` WHEN the chosen deck needs no more copies of any card than the collection holds, the system SHALL state that nothing is missing for that deck, naming it.
   - Acceptance check: a deck built entirely from owned cards shows the "nothing to buy" statement together with the deck's name.

### R3 Following the collection

**User Story:** As a duelist recording the cards I own, I want the list of what is missing to shrink as I record them, so that I can tick a deck off while sorting a box of cards.

#### Acceptance Criteria

1. `R3.AC1` WHEN the user records, changes or removes copies on the collection screen, the system SHALL recompute the report for the deck still chosen.
   - Acceptance check: recording one copy of a card the chosen deck needs two of lowers the reported need to one, without choosing the deck again.

## Non-Functional Requirements

- `NFR1` Honesty. The panel states that nothing is missing only for a deck that is chosen, was read, and needs nothing, and every report names its deck — bridged by `R1.AC4`, `R2.AC1`, `R2.AC3`, `R2.AC4`.
- `NFR2` Nothing here is an edit. Choosing a deck and reading what it needs changes no stored deck and no collection entry — bridged by `R1.AC6`.
- `NFR3` Offline. Decks, collection and names are already stored; nothing here reaches the network — bridged by `R1.AC1`, `R1.AC2`.
- `NFR4` Accessibility. The deck chooser is reachable from the keyboard within the collection screen, announces the deck it selects, and each line of the report is read as one sentence naming the card and the copies needed — bridged by `R1.AC1`, `R1.AC4`.

## Constraints And Dependencies

- `C1` The arithmetic is `collection-tracker`'s, already certified: copies are counted per card rather than per limit name, across every printing and every section. This feature chooses the subject and reports the answer; it computes no second shortfall.
- `C2` Card names come from the catalog the way the collection screen already names cards: Italian where translated, English otherwise.
- `C3` No table, no column, no migration: decks, collection and names are already stored.
- `C4` This project has no automated harness for drawn views. Proofs assert the model the panel draws from and the composition root's wiring; the drawn panel is checked by hand.
- `C5` macOS 27 on arm64, Swift 6.4, SwiftUI. The collection screen is an existing certified screen and this extends it.

## Out Of Scope

- What the missing cards would cost. The value section prices the collection, not a deck's shortfall.
- Which printing or rarity to buy. The shortfall counts cards, not printings.
- Exporting, printing or sharing the list of missing cards.
- Checking several decks at once, or a deck that is not stored.
- The other parts of the collection the 2026-09-27 review found unreachable: condition, price, storage location and the CSV backup.
- Whether the deck is legal, which the deck editor and the statistics already report.
