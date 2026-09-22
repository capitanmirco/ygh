---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-22T12:34:04Z
last_modified: 2026-09-22T12:34:04Z
approved_fingerprint: sha256:635ecd967b2b569596eff9edf4f2a9976618991dde28cb8d50485dc0793ac2b4
---

# Requirements Document

## Introduction

A deck row reads *GOAT · 43 carte*. The word GOAT is the deck's format, it decides every restriction the editor reports, and there is no way to change it. A deck imported as the wrong format stays that way for good.

Tags are the other half of the same problem. `deck-builder`'s organisation requirement says a duelist with many decks wants them sorted, and the storage for that was written and certified. Nothing has ever called it.

Facts measured on 2026-09-22:

- **Both of the user's decks are GOAT**, and both were given that format by the importer's guess, not by a choice.
- **`changeFormat` exists twice over** — on `SQLiteDeckRepository` and on `DeckLibraryViewModel` — **and has no caller.** The deck's context menu offers Rinomina, Duplica, Esporta and Elimina, and nothing else.
- **`CardFormat` holds nine formats**: TCG, OCG, Master Duel, GOAT, OCG GOAT, Edison, Duel Links, Speed Duel and Common Charity. The catalog knows which cards each pool holds: 1,684 for GOAT, 3,662 for Edison, 13,919 for TCG.
- **`tag` and `deck_tag` hold 0 rows each.** The tables exist, cascade correctly, and have never been written to.
- **The tag storage is half-built**: `addTag(_:to:)` and `decks(withTag:)` exist. There is no way to read a deck's tags, to remove one, or to list the tags in use.
- **`Deck` carries `folderID` and `notes` but not its tags**, so a deck read from storage cannot say what it is tagged with.
- **Changing a format already re-judges the deck**: `deck-builder` certified that, and this feature gives the behaviour a way to be triggered.

This feature is the two labels on a deck: the format it is played in, and whatever else the user wants to call it.

## Requirements

### R1 Changing a deck's format

**User Story:** As a duelist, I want to say which format a deck is for, so that the restrictions reported against it are the ones I actually play under.

#### Acceptance Criteria

1. `R1.AC1` WHEN the user chooses a different format for a deck, the system SHALL store it and report the new format wherever that deck is named.
   - Acceptance check: a GOAT deck set to Edison reads Edison in the deck list and in the editor's header, and still reads Edison after the application is restarted.
2. `R1.AC2` WHEN a deck's format changes, the system SHALL re-judge the deck against the new format.
   - Acceptance check: a deck legal in GOAT and holding cards outside Edison's pool reports violations once it is set to Edison, without being reopened.
3. `R1.AC3` The system SHALL offer every format the catalog knows.
   - Acceptance check: the chooser lists all nine, and the one the deck currently holds is marked as chosen.
4. `R1.AC4` IF storing the new format fails, THEN the system SHALL report it and leave the deck on the format it had.
   - Acceptance check: with storage refusing, the deck still reads its previous format and a failure is reported.

### R2 Tagging a deck

**User Story:** As a duelist with many decks, I want to label them in my own words, so that I can tell at a glance what each one is for.

#### Acceptance Criteria

1. `R2.AC1` WHEN the user adds a tag to a deck, the system SHALL list that tag on that deck.
   - Acceptance check: a deck given *da testare* carries it immediately and still carries it after a restart.
2. `R2.AC2` The system SHALL report a deck's tags wherever it reports the deck's format.
   - Acceptance check: a deck carrying two tags shows both in the deck list beside its format.
3. `R2.AC3` WHEN the user removes a tag from a deck, the system SHALL stop listing it on that deck and leave it on every other deck carrying it.
   - Acceptance check: two decks share a tag; removing it from one leaves the other carrying it.
4. `R2.AC4` The system SHALL treat tags differing only in surrounding spaces or in letter case as one tag.
   - Acceptance check: adding *Goat*, *goat* and * goat * to one deck leaves it carrying a single tag.
5. `R2.AC5` IF a tag's name is empty once trimmed, THEN the system SHALL refuse it and leave the deck's tags unchanged.
   - Acceptance check: adding a blank tag adds nothing and reports nothing new.
6. `R2.AC6` The system SHALL offer the tags already in use when the user is adding one.
   - Acceptance check: with *da testare* on one deck, it is offered while tagging another.

### R3 Finding decks by their labels

**User Story:** As a duelist with many decks, I want to narrow the list to the ones I mean, so that I do not read every name to find one.

#### Acceptance Criteria

1. `R3.AC1` WHEN the user chooses a tag to filter by, the system SHALL list only the decks carrying it.
   - Acceptance check: with three decks and a tag on two, the list holds those two.
2. `R3.AC2` WHEN the user clears the filter, the system SHALL list every deck again.
   - Acceptance check: the list returns to its full length, in its usual order.
3. `R3.AC3` WHILE a filter is applied, the system SHALL say which tag it is filtering by.
   - Acceptance check: the chosen tag is named on screen rather than only implied by a shorter list.
4. `R3.AC4` WHERE a filter matches no deck, the system SHALL say so rather than showing an empty list.
   - Acceptance check: filtering by a tag whose only deck was deleted reads a sentence, not a blank area.

## Non-Functional Requirements

- `NFR1` No silent loss. Neither label reaches a deck's cards: changing a format and editing tags leave every slot untouched — bridged by `R1.AC1`, `R2.AC1`, `R2.AC3`.
- `NFR2` Offline. Formats and tags are local state; nothing here reaches the network — bridged by `R1.AC1`, `R2.AC1`, `R3.AC1`.
- `NFR3` Accessibility. The format chooser and the tag controls are reachable and operable from the keyboard, and a deck's labels are announced with the deck rather than as loose words — bridged by `R1.AC3`, `R2.AC2`.
- `NFR4` A deck's labels arrive with the deck. Reading the deck list must not cost one query per deck to learn its tags — bridged by `R2.AC2`, `R3.AC1`.

## Constraints And Dependencies

- `C1` `tag` and `deck_tag` exist and cascade with their deck; this feature adds no table, no column and no migration.
- `C2` The tag storage is half-built: `addTag(_:to:)` and `decks(withTag:)` exist, while reading a deck's tags, removing one and listing those in use do not. `R2` completes it.
- `C3` `Deck` does not carry its tags today, so `R2.AC2` requires either that it does or that the list reads them separately — and `NFR4` rules out reading them one deck at a time.
- `C4` The nine formats in `CardFormat` are the catalog's own, and their card pools come from upstream. This feature chooses among them and does not invent one.
- `C5` Changing a format re-judges a deck through behaviour `deck-builder` already certified. `R1.AC2` reports that rather than re-implementing it.
- `C6` macOS 27 on arm64, Swift 6.4, SwiftUI. The deck list and the editor header are existing certified screens.

## Out Of Scope

- Folders. The other half of `deck-builder`'s organisation requirement, storage-only for the same reason, and a separate decision.
- Searching decks by name, which `decks(named:)` already implements and nothing calls.
- Renaming a tag everywhere it is used, or deleting a tag from every deck at once.
- Colours, icons or ordering for tags.
- Inventing a format the catalog does not publish, or editing a format's card pool.
- Per-card legality against a chosen ban list, which is its own specification.
