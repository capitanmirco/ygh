---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T18:55:04Z
last_modified: 2026-09-21T18:55:04Z
approved_fingerprint: sha256:1291899a09eac46d2fae4c19d2993f54d7be27e369f7633f0dd70f56fe88a3a8
---

# Requirements Document

## Introduction

A deck can only enter this application by being imported. The sidebar offers *Importa un .ydk* and nothing else: there is no way to start one, and no way to get one back out.

Both operations already exist and are certified. `deck-builder` built `createDeck(name:format:)`, and `DeckExporter` writes a deck as `.ydk` text or as a `ydke://` link, reading each slot's artwork so a deck comes out holding the printings that were put into it. What neither has is a caller.

This feature gives them one: start a deck from nothing, and take one out.

Facts measured against the user's own code and database on 2026-09-21:

- **Nothing calls `createDeck`.** The sidebar has an import button and a list of existing decks.
- **Nothing calls `DeckExporter`.** Its three entry points — `ydkText`, `ydkeLink` and `write(_:to:)` — have no caller outside their own tests.
- **Export reads artworks, not cards.** A deck carries the printings the user chose, and substituting a card's primary artwork would quietly rewrite them.
- **Export does not check legality**, deliberately: an unfinished deck is exactly the kind a duelist carries between machines.
- **The user has two decks**, both imported, holding 74 slots across 65 distinct cards.
- **Nine formats exist**, and a deck's format decides which cards it may hold and which restrictions apply to it.
- **Deck organisation already exists** — folders, tags, renaming and search are all in `SQLiteDeckOrganisation` — and is equally uncalled.

## Requirements

### R1 Starting a deck

**User Story:** As a deck builder, I want to start a deck from nothing, so that I do not have to find a `.ydk` somewhere just to begin.

#### Acceptance Criteria

1. `R1.AC1` WHEN the user creates a deck with a name and a format, the system SHALL store it and open it for editing.
   - Acceptance check: after creating, the deck appears in the list and the editor is showing it, empty.
2. `R1.AC2` WHEN a deck is created, the system SHALL record the format it was created for.
   - Acceptance check: a deck created for GOAT is judged by GOAT's rules and offers GOAT's card pool.
3. `R1.AC3` IF the user creates a deck without naming it, THEN the system SHALL give it a name rather than storing an unnamed one.
   - Acceptance check: creating with an empty name produces a deck with a stated default name.
4. `R1.AC4` WHERE a deck of the same name already exists, the system SHALL create the new one and keep both.
   - Acceptance check: creating a second deck with an existing name leaves two decks, each openable.
5. `R1.AC5` IF a deck cannot be created, THEN the system SHALL report the failure and leave the list unchanged.
   - Acceptance check: with storage refusing writes, no deck is added and the failure is stated.

### R2 Taking a deck out

**User Story:** As someone who plays on other machines, I want my deck as a `.ydk` file, so that I can take it to a simulator or share it.

#### Acceptance Criteria

1. `R2.AC1` WHEN the user exports a deck, the system SHALL write a `.ydk` file holding its cards.
   - Acceptance check: the written file lists each slot's passcode once per copy, under its section.
2. `R2.AC2` WHEN a deck is exported, the system SHALL write the printings the deck holds rather than substituting others.
   - Acceptance check: a deck holding a particular artwork of a card exports that artwork's passcode.
3. `R2.AC3` The system SHALL export a deck whether or not it is legal.
   - Acceptance check: a deck of ten cards exports, and a deck breaking a copy limit exports.
4. `R2.AC4` WHEN the user asks for a deck as a link, the system SHALL produce a `ydke://` link for it.
   - Acceptance check: the link decodes back to the same cards in the same sections.
5. `R2.AC5` IF a deck cannot be written, THEN the system SHALL report the failure rather than appearing to succeed.
   - Acceptance check: with the destination unwritable, the failure is stated and no partial file is left.
6. `R2.AC6` WHEN a deck is exported and imported again, the system SHALL produce the same deck.
   - Acceptance check: exporting a deck and importing the result yields the same sections, cards and counts.

### R3 Managing what is there

**User Story:** As someone with more than two decks, I want to rename and remove them, so that the list stays mine rather than a history of imports.

#### Acceptance Criteria

1. `R3.AC1` WHEN the user renames a deck, the system SHALL store the new name and show it.
   - Acceptance check: a renamed deck appears under its new name in the list and the editor.
2. `R3.AC2` WHEN the user duplicates a deck, the system SHALL create a copy holding the same cards.
   - Acceptance check: the copy holds the same sections, cards and counts, and editing it leaves the original alone.
3. `R3.AC3` IF the user deletes a deck, THEN the system SHALL ask first and delete only on confirmation.
   - Acceptance check: a delete without confirmation leaves the deck; with confirmation it is gone.
4. `R3.AC4` The system SHALL let a deck's format be changed after it is created.
   - Acceptance check: changing a deck's format re-judges it against the new format's rules.

## Non-Functional Requirements

- `NFR1` Responsiveness: creating, duplicating or exporting a deck completes within 200 ms for a deck of seventy cards. Bridged by `R1.AC1` and `R2.AC1`.
- `NFR2` Durability: a created or renamed deck is stored before it is reported as done. Bridged by `R1.AC1` and `R3.AC1`.
- `NFR3` Honesty: an operation that fails says so, and the list shown is the list stored. Bridged by `R1.AC5` and `R2.AC5`.
- `NFR4` Offline operation: creating, editing, duplicating and exporting a deck need no network. Bridged by `R2.AC1`.
- `NFR5` Accessibility: creating, exporting, renaming and deleting are reachable by keyboard and each reads as a sentence. Bridged by `R1.AC1` and `R3.AC3`.
- `NFR6` Concurrency safety: the feature builds and runs under Swift 6 strict concurrency checking with no data-race diagnostics suppressed.

## Constraints And Dependencies

- `C1` Creating and exporting are `deck-builder`'s and `YGODeckIO`'s, already certified. This feature calls them; it does not reimplement them.
- `C2` Export writes artwork passcodes, because that is what the deck holds. A card with several printings exports the one chosen.
- `C3` Export does not judge legality, by decision recorded in `deck-builder`.
- `C4` A `.ydk` file carries passcodes and sections and nothing else — no name, no format. A deck exported and imported again comes back named after the file.
- `C5` Deleting a deck is irreversible, which is why `R3.AC3` requires a confirmation.
- `C6` Target platform is macOS 27 on arm64, built with Swift 6.4 and Swift Package Manager.

## Out Of Scope

- Folders and tags, which exist in storage and deserve their own screen.
- Sharing a deck anywhere other than to a file or a link.
- Importing from a link, as opposed to from a file.
- Deck templates or starting from another deck's list.
- Printing a deck or producing a decklist sheet.
