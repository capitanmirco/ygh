---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-22T14:43:54Z
last_modified: 2026-09-22T14:43:54Z
approved_fingerprint: sha256:d6672ecc8eaf465a1c5fe87c63a11d2a924bb68518778f96d6cfa3fbb3757fca
---

# Requirements Document

## Introduction

The statistics screen computes a deck's odds, but never asks which deck. It reads the selection made in the deck list, and the sidebar only lists decks while that section is open — so from inside the statistics there is no way to change the subject. A user who has not been to the deck list sees whichever deck was last chosen, which reads as a default nobody picked.

Facts measured on 2026-09-22:

- **The statistics take `selectedDeck` from the window** and nothing in `deck-analytics` says how a deck is chosen: its six requirements are about the figures, not about the subject.
- **The sidebar's deck list appears only in the decks section**, so the statistics screen offers no way back to it.
- **The format changes every figure.** `OpeningHand` gives the player going first six cards in the formats that predate the modern rule — GOAT, OCG GOAT and Edison — and five in TCG, OCG, Master Duel, Duel Links, Speed Duel and Common Charity. The same forty-card deck therefore has different odds depending on which format it is read in.
- **Both of the user's decks are GOAT with a forty-card main deck**, so every probability on that screen is currently computed against a six-card opening hand.
- **A verdict against a published list already exists**: `deck-legality` produces one, and the statistics screen has no way to show it.

This feature is the three choices the screen was missing: which deck, which format to read it in, and which list to measure it against.

Two of them are questions rather than edits. Reading a GOAT deck as though it were Edison must not make it an Edison deck, and measuring it against a list must not change anything at all.

## Requirements

### R1 Choosing the deck

**User Story:** As a duelist looking at statistics, I want to say which deck they describe, so that I am not reading about whichever deck I last opened.

#### Acceptance Criteria

1. `R1.AC1` The system SHALL let the user choose which deck the statistics describe, from within the statistics screen.
   - Acceptance check: with two decks stored, both are offered and either can be chosen without leaving the screen.
2. `R1.AC2` WHEN the user chooses another deck, the system SHALL report that deck's figures.
   - Acceptance check: choosing a deck of a different size changes the reported deck size and the odds with it.
3. `R1.AC3` The system SHALL name the deck its figures describe.
   - Acceptance check: the screen reads the deck's name rather than only its numbers.
4. `R1.AC4` WHERE no deck is stored, the system SHALL say so rather than offering an empty chooser.
   - Acceptance check: with an empty library the screen explains that there is nothing to analyse.
5. `R1.AC5` WHEN the statistics are opened with a deck already chosen elsewhere, the system SHALL start from that deck.
   - Acceptance check: a deck selected in the deck list is the one the statistics open on.

### R2 Reading a deck in another format

**User Story:** As a duelist who plays the same list in more than one format, I want to see what its odds would be elsewhere, so that I can tell whether it travels.

#### Acceptance Criteria

1. `R2.AC1` The system SHALL let the user compute the chosen deck's figures as though it were played in another format.
   - Acceptance check: a GOAT deck can be read as Edison or as TCG from the statistics screen.
2. `R2.AC2` WHEN the assumed format changes the opening hand's size, the system SHALL recompute every reported figure against the new size.
   - Acceptance check: the same forty-card deck read as GOAT reports a six-card opening hand for the player going first, and five when read as TCG, with the drawing odds changing accordingly.
3. `R2.AC3` The system SHALL name the format its figures assume, and say when that is not the deck's own.
   - Acceptance check: a GOAT deck read as TCG states that the figures assume TCG rather than the deck's format.
4. `R2.AC4` The system SHALL leave the deck's stored format unchanged whichever format is assumed.
   - Acceptance check: after reading a GOAT deck as three other formats, the deck still reads GOAT in the deck list and in storage.

### R3 Measuring it against a list

**User Story:** As a duelist deciding whether to take this deck somewhere, I want to know whether it is playable there, beside the odds that tell me whether it works.

#### Acceptance Criteria

1. `R3.AC1` The system SHALL report whether the chosen deck is within a chosen published Forbidden & Limited List.
   - Acceptance check: a deck holding a card that list forbids is reported as not within it, with how many cards are over.
2. `R3.AC2` The system SHALL name the list a verdict came from, with its date.
   - Acceptance check: the verdict reads the format and the effective date rather than only a count.
3. `R3.AC3` WHEN the deck or the list changes, the system SHALL report the verdict for the pair now chosen.
   - Acceptance check: switching the list from the TCG list of March 2005 to the one of March 2010 changes the reported count for the same deck.
4. `R3.AC4` WHERE no list is chosen and the deck's format implies none, the system SHALL report no verdict rather than a misleading one.
   - Acceptance check: a Speed Duel deck shows no verdict and says why, instead of being measured against the current TCG list.
5. `R3.AC5` The system SHALL leave the deck unchanged whichever list is chosen.
   - Acceptance check: the deck's cards and format are identical after measuring it against several lists.

### R4 The dealt hand follows the choices

**User Story:** As a duelist trying out opening hands, I want the hand I am dealt to come from the deck and the rules I chose, so that what I see is what I would sit down with.

#### Acceptance Criteria

1. `R4.AC1` WHEN the chosen deck changes, the system SHALL deal from the deck now chosen.
   - Acceptance check: a hand dealt after switching decks holds only cards the new deck contains.
2. `R4.AC2` WHEN the chosen deck or the assumed format changes, the system SHALL clear a hand dealt under the previous choice.
   - Acceptance check: a hand on screen disappears when the deck or the format changes, rather than remaining as though it still applied.
3. `R4.AC3` The system SHALL deal a hand of the size the assumed format and the play order imply.
   - Acceptance check: a deck read as GOAT deals six cards to the player going first and six going second; read as TCG it deals five and six.

## Non-Functional Requirements

- `NFR1` Honesty. Every figure states the deck, the format assumed and the play order it was computed under, and a verdict states the list it came from — bridged by `R1.AC3`, `R2.AC3`, `R3.AC2`.
- `NFR2` Nothing here is an edit. Choosing a deck, a format or a list changes no stored deck — bridged by `R2.AC4`, `R3.AC5`.
- `NFR3` Offline. The decks and the lists are already stored; nothing here reaches the network — bridged by `R1.AC1`, `R3.AC1`.
- `NFR4` Accessibility. The three choosers and the dealt hand are reachable and operable from the keyboard, and each chooser announces what it selects — bridged by `R1.AC1`, `R2.AC1`, `R3.AC1`.

## Constraints And Dependencies

- `C1` The statistics engine takes a deck value and reads its format from it. Assuming another format therefore means computing against a copy, never against stored state.
- `C2` `OpeningHand` is where the format reaches the arithmetic: six cards for the player going first in GOAT, OCG GOAT and Edison, five in the rest. `R2.AC2` is that rule made visible rather than a new one.
- `C3` The verdict against a list is `deck-legality`'s, already certified. `R3` reports it here and does not compute a second one.
- `C4` Speed Duel and Duel Links use deck sizes and opening hands this application does not model, as `deck-analytics` already records. Assuming one of those formats inherits that limitation.
- `C5` No table, no column, no migration: decks and lists are already stored.
- `C6` macOS 27 on arm64, Swift 6.4, SwiftUI. The statistics screen is an existing certified screen and this extends it.

## Out Of Scope

- Changing a deck's format, which `deck-labels` covers from the deck list and the editor.
- The per-card legality panel, which `deck-legality` shows in the editor; only the deck's verdict appears here.
- Excluding forbidden cards from the odds. The figures describe the deck as built; a deck that cannot be played is reported as such rather than silently altered.
- Modelling Speed Duel or Duel Links rules.
- Comparing two decks, or two formats, side by side.
- Analysing a deck that is not stored.
