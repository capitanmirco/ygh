---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T09:21:36Z
last_modified: 2026-09-21T09:21:36Z
approved_fingerprint: sha256:758cd1cbd85ee1ffe29276a1078cbc262cde833d9a1c53d92dc6e71e937ba208
---

# Requirements Document

## Introduction

A deck today can be opened, read and added to. What it cannot be is rearranged: a card sits in whichever section it landed in, its count moves one copy at a time, and the card search inside the editor shows nothing until something is typed. Building a deck is mostly moving things around, and that is the part that is missing.

This feature makes a deck freely editable: search and insert, set a count outright, move a card from one section to another by dragging it or by asking, and undo any of it.

Facts measured against the user's own database and code on 2026-09-21:

- **Two decks, 74 slots, 65 distinct cards.** LR-Chaos Turbo holds 40 main, 15 extra and 15 side; Lockdown Burn holds 40 main.
- **28 slots hold more than one copy** and 8 hold the maximum of three, so counts are not an edge case.
- **Two cards already sit in two sections of the same deck**, which is ordinary: a card in the main deck and again in the side.
- **The editor's card search returns nothing for an empty query.** Its results are capped at 40.
- **Adding is permissive by design.** The repository inserts the copy and the validator reports the violation afterwards; `deck-builder` settled that and this feature does not reopen it.
- **Nothing can move.** `DeckBuilding` offers `addCard` and `removeCard` keyed by artwork and section, and no operation that changes a card's section or sets its count.
- **Failures are swallowed.** The editor calls the repository with `try?`, so an add that fails leaves the deck unchanged and says nothing.

## Requirements

### R1 Finding a card to put in

**User Story:** As a deck builder, I want the editor's card search to behave like the browser, so that I can look for something to add without having to know its name first.

#### Acceptance Criteria

1. `R1.AC1` WHEN the deck editor opens, the system SHALL offer cards to add without the user having typed anything.
   - Acceptance check: on opening an editor, the candidate list holds cards rather than being empty.
2. `R1.AC2` WHEN the search text changes, the system SHALL update the candidates without the user submitting them.
   - Acceptance check: successive text changes produce successive candidate sets with no submit.
3. `R1.AC3` WHILE a deck has a format, the system SHALL offer only cards legal in that format.
   - Acceptance check: the editor of a GOAT deck offers no card outside the GOAT pool.
4. `R1.AC4` WHEN the user adds a candidate without choosing a section, the system SHALL place it in the section its card type belongs to.
   - Acceptance check: adding a Fusion Monster places it in the extra deck and adding a Spell places it in the main deck.

### R2 Changing what is in the deck

**User Story:** As a deck builder, I want to set how many copies of a card the deck holds, so that I can go from one to three without pressing a button three times.

#### Acceptance Criteria

1. `R2.AC1` WHEN the user sets a card's count in a section, the system SHALL make the deck hold exactly that many copies of it there.
   - Acceptance check: setting a card held once to three leaves three copies in that section and nothing elsewhere.
2. `R2.AC2` WHEN the user sets a card's count to zero, the system SHALL remove it from that section.
   - Acceptance check: a card set to zero no longer appears in that section, and the deck's other sections are unchanged.
3. `R2.AC3` IF the user sets a count that would break a rule, THEN the system SHALL apply it and report the violation.
   - Acceptance check: setting four copies of an unrestricted card leaves four copies held and reports a copy-limit violation, in keeping with the permissive writing `deck-builder` established.
4. `R2.AC4` IF an edit cannot be written, THEN the system SHALL report the failure and leave the deck as it was.
   - Acceptance check: with the repository refusing writes, the deck is unchanged and the editor states that the edit failed rather than appearing to succeed.
5. `R2.AC5` WHEN an edit succeeds, the system SHALL report the deck's legality as it now stands.
   - Acceptance check: after an edit the reported violations are those of the edited deck, not of the deck before it.

### R3 Moving a card between sections

**User Story:** As a deck builder, I want to move a card from the main deck to the side deck, so that I can rearrange a deck instead of deleting and re-adding cards.

#### Acceptance Criteria

1. `R3.AC1` WHEN the user moves a card from one section to another, the system SHALL remove the moved copies from the first and add them to the second.
   - Acceptance check: moving two copies from the main deck to the side leaves the main deck two lighter and the side two heavier, with the deck's total unchanged.
2. `R3.AC2` WHEN a card is moved, the system SHALL preserve which artwork of it the deck held.
   - Acceptance check: a card held under a particular artwork keeps that artwork after the move.
3. `R3.AC3` WHERE the destination section already holds that card, the system SHALL add the moved copies to those already there.
   - Acceptance check: moving one copy into a section already holding two leaves three there, as one entry rather than two.
4. `R3.AC4` IF a move would leave a section holding nothing of that card, THEN the system SHALL remove it from the source section rather than leaving an empty entry.
   - Acceptance check: moving every copy leaves no trace of the card in the source section.
5. `R3.AC5` IF a move is asked for between a section and itself, THEN the system SHALL leave the deck unchanged.
   - Acceptance check: a move whose source and destination are the same changes nothing and reports no failure.
6. `R3.AC6` IF a move asks for more copies than the source holds, THEN the system SHALL move only the copies held.
   - Acceptance check: asking to move five copies of a card held twice moves two and leaves the deck consistent.

### R4 Undoing an edit

**User Story:** As a deck builder, I want to undo a change I did not mean to make, so that a mistaken drag does not cost me a card I then have to find again.

#### Acceptance Criteria

1. `R4.AC1` WHEN the user undoes the last edit, the system SHALL restore the deck to what it held before that edit.
   - Acceptance check: after an add, an undo leaves the deck holding exactly what it held beforehand, section by section.
2. `R4.AC2` WHEN the user redoes an undone edit, the system SHALL apply it again.
   - Acceptance check: undo followed by redo leaves the deck as it was after the original edit.
3. `R4.AC3` The system SHALL undo adds, removals, count changes and moves alike.
   - Acceptance check: each of the four kinds of edit is undone to the state before it.
4. `R4.AC4` WHEN a new edit is made after an undo, the system SHALL discard the edits that were undone.
   - Acceptance check: after undoing an edit and making a different one, there is nothing left to redo.
5. `R4.AC5` IF there is nothing to undo or redo, THEN the system SHALL report that rather than changing the deck.
   - Acceptance check: undo on a freshly opened deck changes nothing and the editor reports that there is nothing to undo.
6. `R4.AC6` WHEN a different deck is opened, the system SHALL discard the undo history of the previous one.
   - Acceptance check: opening a second deck leaves nothing to undo, and no edit of the first deck can be applied to it.

### R5 Doing it by hand

**User Story:** As a deck builder, I want to drag a card where I want it, so that arranging a deck feels like arranging cards.

#### Acceptance Criteria

1. `R5.AC1` WHEN the user drags a card onto another section, the system SHALL move it there.
   - Acceptance check: a card dragged from the main deck onto the side deck is held by the side deck afterwards.
2. `R5.AC2` WHEN the user drags a candidate from the card search onto a section, the system SHALL add it to that section.
   - Acceptance check: a candidate dragged onto the extra deck is held by the extra deck afterwards.
3. `R5.AC3` WHILE a card is being dragged, the system SHALL show which section would receive it.
   - Acceptance check: the section under the pointer is distinguished from the others while a drag is in progress.
4. `R5.AC4` The system SHALL offer every move and count change through the keyboard as well as by dragging.
   - Acceptance check: moving a card to another section and changing its count are both reachable without a pointer.

## Non-Functional Requirements

- `NFR1` Responsiveness: an edit is reflected in the editor within 100 ms, so that dragging a card does not feel like waiting for a save. Bridged by `R2.AC1` and `R3.AC1`.
- `NFR2` Durability: an edit is written before it is reported as done, so closing the application immediately afterwards does not lose it. Bridged by `R2.AC4` and `R4.AC1`.
- `NFR3` Honesty: an edit that fails says so, and the deck shown is the deck stored. Bridged by `R2.AC4` and `R2.AC5`.
- `NFR4` Accessibility: every edit is reachable by keyboard, and each card in the deck reads as a sentence naming it, its section and its count. Bridged by `R5.AC4`.
- `NFR5` Offline operation: every edit is applied to local storage with no network. Bridged by the storage acceptance checks on `R2.AC1` and `R3.AC1`.
- `NFR6` Concurrency safety: the feature builds and runs under Swift 6 strict concurrency checking with no data-race diagnostics suppressed.

## Constraints And Dependencies

- `C1` Writing stays permissive. `deck-builder` established that the repository accepts an edit and the validator reports what is wrong with the result; this feature adds operations, not refusals.
- `C2` A deck slot is identified by deck, section and artwork. A move therefore changes a row's section, and two artworks of the same card are two entries.
- `C3` Section limits are the rules': 40 to 60 for the main deck, 0 to 15 for the extra and the side. They are reported, not enforced.
- `C4` The copy limit counts across sections and across artworks, and groups cards that are treated as one another. That is `deck-builder`'s `CopyTally` and is not reimplemented here.
- `C5` The undo history lives for as long as a deck is open. It is not stored, so it does not survive closing the application.
- `C6` Drag and drop is a gesture. The model operation beneath it is proven; the gesture itself is not covered by an automated proof, and `R5.AC1` to `R5.AC3` are verified by hand.
- `C7` Target platform is macOS 27 on arm64, built with Swift 6.4 and Swift Package Manager.

## Out Of Scope

- Changing a deck's format, name or notes, which `deck-builder` already owns.
- Deleting a deck, which `deck-builder` already owns and already confirms.
- Editing the collection from the deck editor.
- Suggesting cards, scoring a deck or anything that decides what should be in it.
- Persisting the undo history across sessions.
