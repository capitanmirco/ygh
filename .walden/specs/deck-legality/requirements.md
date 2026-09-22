---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-22T13:31:09Z
last_modified: 2026-09-22T13:31:09Z
approved_fingerprint: sha256:384f1d2e1fed41402c3c64d466effb81db6e298ca59bad31eb85dc5fe15d7cef
---

# Requirements Document

## Introduction

*In GOAT you can play Pot of Greed; in Edison it is banned.* The application cannot say that. It judges a deck against `ban_status`, which holds the current restrictions for TCG, OCG and GOAT and nothing else, so an Edison deck is judged against no list at all and reports `restrictionsAreUserMaintained`.

Everything needed to say it is already stored. Measured on the user's own database on 2026-09-22:

- **177 published lists are held**, 73 of them TCG, going back to 1999-08-01.
- **The list that defines the GOAT era is TCG 2005-03-01; the one that defines Edison is TCG 2010-03-01.** Both are stored, with their entries.
- **Pot of Greed — *Anfora dell'Avidità*, konami_id 4844 — is `limited` on the first and `forbidden` on the second.** That is the user's sentence, already in the database, never read.
- **Their own decks say it louder.** `LR-Chaos Turbo` holds **0 forbidden cards under the 2005 list and 12 under the 2010 one**; `Lockdown Burn` holds 0 and 4. Today neither number is reported anywhere.
- **`banlist_entry` is keyed by `konami_id`**, and 203 of the catalog's 14,566 cards carry none — though every card in the user's two decks does.
- **`DeckCardIndex.Entry` does not carry `konami_id`**, so nothing the validator holds can be matched against a list.
- **A retro format is a pool and a list.** The pool check exists: `appendFormatPoolViolations` already refuses a card released after the era. What is missing is the list.

This feature is the missing half: the deck, judged card by card against a published list the user names.

It does not change what a deck *is*. Choosing a list to judge against is a question, not an edit.

## Requirements

### R1 Choosing what to judge against

**User Story:** As a duelist who plays more than one format, I want to judge a deck against the list of that format, so that the verdict is about the game I am going to play.

#### Acceptance Criteria

1. `R1.AC1` The system SHALL judge the open deck against a published Forbidden & Limited List chosen by the user.
   - Acceptance check: with the TCG list of March 2010 chosen, the deck's report describes that list's restrictions.
2. `R1.AC2` WHEN a deck is opened, the system SHALL choose the list its format implies.
   - Acceptance check: a GOAT deck opens judged against the TCG list of March 2005; an Edison deck against the TCG list of March 2010.
3. `R1.AC3` WHERE a deck's format implies no published list, the system SHALL say so and name no list.
   - Acceptance check: a Speed Duel deck reports that no published list covers its format, rather than being judged against the current TCG one.
4. `R1.AC4` The system SHALL offer every stored list, named by its format and its date.
   - Acceptance check: the chooser holds all 177, grouped by format, each showing the date it took effect.
5. `R1.AC5` WHEN the user chooses a different list, the system SHALL judge the deck against it without the deck being reopened.
   - Acceptance check: moving `LR-Chaos Turbo` from the March 2005 list to the March 2010 one moves its forbidden count from 0 to 12.
6. `R1.AC6` The system SHALL leave the deck's stored format unchanged whichever list is chosen.
   - Acceptance check: after judging a GOAT deck against six different lists, the deck still reads GOAT.

### R2 What each card is allowed

**User Story:** As a duelist, I want to see which of my cards the list names and how many copies it allows, so that I know what to cut before I sit down.

#### Acceptance Criteria

1. `R2.AC1` The system SHALL report, for every distinct card in the deck, its status on the chosen list.
   - Acceptance check: against the March 2010 list, `LR-Chaos Turbo` reports 12 forbidden, 14 limited and 1 semi-limited card.
2. `R2.AC2` WHERE the chosen list does not name a card, the system SHALL report that card as unrestricted.
   - Acceptance check: a card absent from the list is reported as unrestricted rather than as missing.
3. `R2.AC3` The system SHALL report how many copies the deck holds of a card beside how many the list permits.
   - Acceptance check: two copies of a limited card read *2 in mazzo, 1 consentita*.
4. `R2.AC4` WHEN the copies held exceed what the chosen list permits, the system SHALL mark that card as over its allowance.
   - Acceptance check: one copy of a forbidden card is marked; one copy of a limited card is not.
5. `R2.AC5` IF a card carries no identifier the lists use, THEN the system SHALL report it as unmatched rather than as unrestricted.
   - Acceptance check: a card with no `konami_id` is reported as unmatched, and is not counted among the unrestricted.

### R3 The deck's verdict

**User Story:** As a duelist, I want one answer about the whole deck, so that I know whether I am finished.

#### Acceptance Criteria

1. `R3.AC1` The system SHALL report how many of the deck's cards the chosen list forbids, limits and semi-limits.
   - Acceptance check: against the March 2005 list, `LR-Chaos Turbo` reports 0 forbidden, 16 limited and 3 semi-limited.
2. `R3.AC2` The system SHALL report whether the deck is within the chosen list.
   - Acceptance check: a deck holding a forbidden card is reported as not within it; removing that card makes it within.
3. `R3.AC3` The system SHALL judge copies held rather than entries.
   - Acceptance check: three copies of a limited card are one card over its allowance, reported as 3 held against 1 permitted, not as three separate findings.
4. `R3.AC4` The system SHALL name the list a verdict came from, with its date.
   - Acceptance check: the report names the format and the effective date rather than saying only *legale*.

### R4 Reading it without a pointer

**User Story:** As someone who builds decks from the keyboard, I want the verdict reachable like everything else in the editor.

#### Acceptance Criteria

1. `R4.AC1` The system SHALL let the user choose a list and move through the judged cards without a pointer.
   - Acceptance check: the chooser and the list of judged cards are both reachable from the keyboard.
2. `R4.AC2` The system SHALL announce each judged card as its name, its status, the copies held and the copies permitted.
   - Acceptance check: a screen reader reads one sentence per card carrying all four.

## Non-Functional Requirements

- `NFR1` One read. A deck holds at most ninety distinct cards, and judging it reads the chosen list once rather than once per card — bridged by `R2.AC1`, `R1.AC5`.
- `NFR2` Offline. Every list judged against is already stored; nothing here reaches the network — bridged by `R1.AC1`, `R2.AC1`.
- `NFR3` Accessibility. Every judged card reads as a sentence, and every control is keyboard reachable — bridged by `R4.AC1`, `R4.AC2`.
- `NFR4` Honesty. A status is reported as what a named published list said on a named date, never as the application's own verdict; a card the list cannot be matched to is reported as such — bridged by `R2.AC5`, `R3.AC4`, `R1.AC3`.

## Constraints And Dependencies

- `C1` `banlist_entry` is keyed by `konami_id`. 203 of the catalog's cards carry none, so matching is partial by construction and `R2.AC5` is how that is told rather than hidden.
- `C2` The era mapping — GOAT to the TCG list of March 2005, Edison to the one of March 2010 — is a judgement about community formats, not published data. `R1.AC2` makes it a default, and `R1.AC1` keeps it overridable.
- `C3` Legality in a retro format is a pool and a list. The pool half exists and is certified; this feature adds the list half and does not re-implement the pool.
- `C4` Four formats' lists are stored — TCG, OCG, Master Duel, Rush — and no others will be fetched here. Genesys is a points system rather than a list, and Speed Duel publishes only per-event lists.
- `C5` No table, no column, no migration: `banlist_revision` and `banlist_entry` hold everything this reads.
- `C6` macOS 27 on arm64, Swift 6.4, SwiftUI. The deck editor is an existing certified screen and this extends it.

## Out Of Scope

- Changing a deck's format, which `deck-labels` covers.
- Fetching lists the application does not already store.
- Editing or authoring a list.
- Genesys, whose format is a point total rather than a set of restrictions.
- Suggesting what to cut, or building a legal deck automatically.
- Judging a deck against two lists side by side.
- The card pool half of a retro format, which is already certified.
