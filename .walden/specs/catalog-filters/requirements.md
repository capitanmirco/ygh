---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T13:29:30Z
last_modified: 2026-09-21T13:29:30Z
approved_fingerprint: sha256:ab86a249c22d82525876ed5b7ada5366c940c0001cd2a085a2e2a12b980f7b8b
---

# Requirements Document

## Introduction

The browser can be narrowed by a dozen things and offers none of them. `CardFilters` already carries format, frame, attribute, race, archetype, level and the attack and defence ranges; the view shows a search field and a language picker. Everything else is reachable only from a test.

This feature puts those filters in front of the user, adds the ones the model does not have — card type, release year, and membership of a published Forbidden & Limited List — and gets the lists into the application at all, because nothing does that yet.

Facts measured against the user's own database on 2026-09-21:

- **The lists were never downloaded.** `banlist_revision` holds zero rows and `banlist_entry` zero. `banlist-history` built the synchroniser and the app never constructs it, so a card's detail panel currently says no list has been downloaded, for every card.
- **Card type splits 9,365 monsters, 2,886 spells, 2,085 traps** and 230 tokens and skills, which the catalog stores as seventeen frames rather than as a type.
- **Release dates run from 2001-01-01 to 2027-02-16** across 27 distinct years, and **523 cards carry no TCG date at all**.
- **Nine formats**, very unevenly stocked: OCG 14,015, TCG 13,919, Master Duel 13,865, then Common Charity 8,654, Duel Links 8,256, Edison 3,662, OCG GOAT 2,084, GOAT 1,684 and Speed Duel 1,684.
- **Seven attributes across 9,364 monsters**, levels from 0 to 13 on 8,999 of them.
- **Attack and defence are `-1` where the card prints "?"** — 9,364 cards carry an attack value and the lowest is not a number.
- **87 monster types and 662 archetypes.** Neither fits in a menu.
- **The collection is empty**, so a filter for cards owned would currently hide everything.

## Requirements

### R1 Narrowing by what a card is

**User Story:** As a deck builder, I want to narrow the catalog by a card's own properties, so that I can find the Level 4 DARK monsters instead of scrolling past fourteen thousand cards.

#### Acceptance Criteria

1. `R1.AC1` WHEN the user selects one or more card types, the system SHALL show only cards of those types.
   - Acceptance check: selecting spells alone reports 2,886 matches and every shown card is a spell.
2. `R1.AC2` WHEN the user selects one or more attributes, the system SHALL show only monsters carrying them.
   - Acceptance check: selecting DARK shows only DARK monsters, and no spell or trap appears.
3. `R1.AC3` WHEN the user sets a level or rank range, the system SHALL show only monsters within it.
   - Acceptance check: a range of 4 to 4 shows only Level 4 monsters, and cards with no level are absent rather than treated as zero.
4. `R1.AC4` WHEN the user chooses a monster type or an archetype, the system SHALL show only cards carrying it.
   - Acceptance check: choosing the Dragon type shows only dragons; choosing an archetype shows only its members.
5. `R1.AC5` WHILE a field offers more values than a menu can hold, the system SHALL let the user narrow the choices by typing.
   - Acceptance check: typing into the archetype field narrows its 662 values, and typing into the monster type field narrows its 87.
6. `R1.AC6` WHEN the user sets an attack or defence range, the system SHALL show only monsters whose value falls within it.
   - Acceptance check: a range of 2000 to 3000 shows only monsters in that band.
7. `R1.AC7` IF a card prints "?" for attack or defence, THEN the system SHALL exclude it from a numeric range rather than treating its stored `-1` as a value.
   - Acceptance check: a range starting at 0 does not admit a card whose attack is "?", and a filter for "?" finds them.

### R2 Narrowing by when and where

**User Story:** As someone who plays retro formats, I want to narrow by year and by format, so that I can see what a 2005 card pool actually looked like.

#### Acceptance Criteria

1. `R2.AC1` WHEN the user sets a release year range, the system SHALL show only cards released within it.
   - Acceptance check: a range of 2004 to 2005 shows only cards whose release date falls in those years.
2. `R2.AC2` IF a card has no release date recorded, THEN the system SHALL exclude it from a year range and say how many were excluded.
   - Acceptance check: with a year range applied, the 523 undated cards are absent and their number is reported.
3. `R2.AC3` WHEN the user selects a format, the system SHALL show only cards legal in it.
   - Acceptance check: selecting GOAT reports 1,684 matches and every shown card is in the GOAT pool.
4. `R2.AC4` WHEN a format is selected, the system SHALL report each shown card's restriction status in that format.
   - Acceptance check: a card forbidden in the selected format is shown as forbidden rather than as unrestricted.

### R3 Narrowing by a published list

**User Story:** As someone building a deck for a specific era, I want to pick the list from April 2005 and see exactly the cards it named, so that I know what was restricted then.

#### Acceptance Criteria

1. `R3.AC1` WHEN the user chooses a published list by format and date, the system SHALL show only the cards that list named.
   - Acceptance check: choosing the 2005-03-01 TCG list shows 77 cards, and no card the list did not name.
2. `R3.AC2` WHILE a published list is chosen, the system SHALL show each card's status on that list rather than its current one.
   - Acceptance check: a card forbidden in 2005 and unrestricted today is shown as forbidden while that list is chosen.
3. `R3.AC3` The system SHALL offer the lists it holds, by format, in date order.
   - Acceptance check: the list chooser offers the TCG lists from 1999-08-01 to the most recent one stored.
4. `R3.AC4` IF no list has been stored for a format, THEN the system SHALL say so rather than offering an empty chooser.
   - Acceptance check: before any synchronisation, the chooser states that no list has been downloaded.
5. `R3.AC5` IF a list names a card the catalog cannot match, THEN the system SHALL report how many were unmatched.
   - Acceptance check: a list whose entries exceed the cards shown reports the difference rather than silently showing fewer.

### R4 Getting the lists into the application

**User Story:** As the person using this, I want the published lists downloaded, so that the history and the list filter have something to work with.

#### Acceptance Criteria

1. `R4.AC1` WHEN the user asks for the banlist history to be synchronised, the system SHALL retrieve and store every published list.
   - Acceptance check: after a synchronisation the database holds the lists the source publishes, and a card's history panel stops saying none was downloaded.
2. `R4.AC2` WHILE a synchronisation is running, the system SHALL report its progress and keep the catalog usable.
   - Acceptance check: the interface reports how many lists have been stored, and search continues to answer while it runs.
3. `R4.AC3` IF the synchronisation fails, THEN the system SHALL report the failure and keep whatever was already stored.
   - Acceptance check: with the source unreachable, the stored lists are unchanged and the failure is stated.
4. `R4.AC4` WHEN a synchronisation has completed once, the system SHALL answer every list question without a network.
   - Acceptance check: with the source unreachable afterwards, the list chooser and the list filter still work.

### R5 Working with filters

**User Story:** As someone narrowing a search, I want to see what I have applied and undo it, so that I do not end up staring at an empty grid wondering why.

#### Acceptance Criteria

1. `R5.AC1` WHEN several filters are applied, the system SHALL show only cards satisfying all of them.
   - Acceptance check: a type and an attribute together admit only cards satisfying both, and the reported count matches.
2. `R5.AC2` The system SHALL report which filters are currently applied.
   - Acceptance check: each applied filter is visible with its value, and a filter that is not applied is not shown as one.
3. `R5.AC3` WHEN the user clears the filters, the system SHALL show the unnarrowed catalog again.
   - Acceptance check: clearing returns the reported count to 14,566.
4. `R5.AC4` IF the applied filters match no card, THEN the system SHALL say so and name the filters responsible.
   - Acceptance check: a combination matching nothing reports no matches and lists what is applied, rather than showing a bare empty grid.
5. `R5.AC5` WHERE the user asks for only the cards they own, the system SHALL narrow to those and report how many copies are held.
   - Acceptance check: with an empty collection the filter reports that nothing is owned rather than showing an unexplained empty grid.
6. `R5.AC6` The system SHALL let every filter be set and cleared from the keyboard.
   - Acceptance check: each filter is reachable and operable without a pointer.

## Non-Functional Requirements

- `NFR1` Responsiveness: applying or changing a filter updates the results within 150 ms against the full catalog. Bridged by `R5.AC1` and `R1.AC1`.
- `NFR2` Honesty: a filter that hides cards says how many and why, and an empty result names what caused it. Bridged by `R2.AC2`, `R3.AC5` and `R5.AC4`.
- `NFR3` Offline operation: every filter, including the published-list filter, is resolved from stored data once the lists have been synchronised. Bridged by `R4.AC4`.
- `NFR4` Accessibility: every filter is keyboard operable and each reads as a sentence naming what it narrows. Bridged by `R5.AC6` and `R5.AC2`.
- `NFR5` Concurrency safety: the feature builds and runs under Swift 6 strict concurrency checking with no data-race diagnostics suppressed.

## Constraints And Dependencies

- `C1` Card type is not stored. The catalog holds seventeen frames, and monster, spell and trap are derived from them.
- `C2` Attack and defence store `-1` where the card prints "?". A numeric range that admitted `-1` would return cards whose value is unknown, which is why `R1.AC7` exists.
- `C3` 523 cards carry no TCG release date, so any year range necessarily hides them.
- `C4` 87 monster types and 662 archetypes cannot be offered as menus.
- `C5` The published lists must be downloaded before `R3` can answer anything, which is why `R4` is part of this feature rather than assumed.
- `C6` The list filter joins on `konami_id`, which 203 of 14,566 cards do not carry.
- `C7` The collection is empty, so `R5.AC5` is proven against seeded data.
- `C8` Target platform is macOS 27 on arm64, built with Swift 6.4 and Swift Package Manager.

## Out Of Scope

- Saving a filter combination for later, or naming one.
- Filtering by rarity or by set, which belong to a printing rather than to a card.
- Sorting the results, which stays as it is.
- The card preview in the deck editor and building a deck from scratch, which are their own specifications.
- Editing a historical list.
