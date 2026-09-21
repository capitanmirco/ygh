---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T19:45:15Z
last_modified: 2026-09-21T19:45:15Z
approved_fingerprint: sha256:ec5d4123432b049de877f9a2fddf2f855cf1aacfc1a84f92d42f4db002fc0605
---

# Requirements Document

## Introduction

The published lists are stored and can narrow the catalog, which answers *which cards were on the April 2005 list*. What it does not answer is the question a duelist actually asks of a list: *what does this list say*.

A Forbidden & Limited List is read in three blocks — what is banned, what is down to one, what is down to two — and within each block a player looks for monsters first, then spells, then traps. That is how the list is published and how it is discussed. The catalog grid, sorted by name across all three statuses, is the wrong shape for it.

This feature is that screen.

Facts measured against the user's own database on 2026-09-21, after a synchronisation:

- **177 lists are stored**: 73 TCG, 66 Master Duel, 23 OCG, 15 Rush Duel, holding 28,648 entries between them.
- **The list that defines GOAT holds 77 cards** — 18 forbidden, 44 limited, 15 semi-limited — and every one of them matches a card in the catalog.
- **Its shape is uneven in a way that matters**: among the forbidden, spells outnumber monsters ten to six; among the limited, monsters lead twenty-two to twelve.
- **Entries are keyed by `konami_id`**, and 203 of the catalog's 14,566 cards carry none, so a list can name a card this application cannot show.
- **The stored entry carries no card type.** `BanlistListEntry` holds the identifier, the card's names and the status, which is not enough to order a block by kind.
- **The detail panel exists and is reused twice already**, in the catalog and in the deck editor.

## Requirements

### R1 Reading a list as a list

**User Story:** As a duelist, I want to read a Forbidden & Limited List the way it is published, so that I can see what a format's rules actually are.

#### Acceptance Criteria

1. `R1.AC1` WHEN the user opens a stored list, the system SHALL group its cards by restriction status.
   - Acceptance check: the GOAT list is shown as three groups holding 18, 44 and 15 cards.
2. `R1.AC2` The system SHALL order the groups from most restrictive to least.
   - Acceptance check: forbidden is shown first, then limited, then semi-limited.
3. `R1.AC3` WITHIN a group, the system SHALL order cards by kind: monsters, then spells, then traps.
   - Acceptance check: in the GOAT list's forbidden group, its six monsters precede its ten spells, which precede its two traps.
4. `R1.AC4` WITHIN a kind, the system SHALL order cards by name.
   - Acceptance check: the monsters in a group read alphabetically.
5. `R1.AC5` The system SHALL report how many cards each group holds.
   - Acceptance check: each group states its count, and the three sum to the list's size.
6. `R1.AC6` IF a list names a card the catalog cannot match, THEN the system SHALL report how many rather than omitting them silently.
   - Acceptance check: a list with unmatched entries states the number, and the groups' counts plus that number equal the list's size.

### R2 Choosing a list

**User Story:** As someone who plays more than one format, I want to pick which list I am reading, so that I can compare an era to the present.

#### Acceptance Criteria

1. `R2.AC1` WHEN the user chooses a format, the system SHALL offer the lists stored for it, newest first.
   - Acceptance check: choosing TCG offers its 73 lists with the most recent at the top.
2. `R2.AC2` WHEN the user chooses a list, the system SHALL show that list's cards.
   - Acceptance check: choosing a different date replaces the three groups with that list's.
3. `R2.AC3` WHERE a format is frozen at a particular list, the system SHALL name that list.
   - Acceptance check: the list defining GOAT is labelled as such among the TCG lists.
4. `R2.AC4` IF no list is stored for the chosen format, THEN the system SHALL say so and offer to download them.
   - Acceptance check: with nothing stored, the screen states it and the synchronisation is reachable from there.
5. `R2.AC5` The system SHALL report which list is being shown and when it took effect.
   - Acceptance check: the screen names the format and the effective date of what it is showing.

### R3 Reading a card on the list

**User Story:** As someone reading a list, I want to see what a card does without leaving it, so that a name I do not recognise does not send me elsewhere.

#### Acceptance Criteria

1. `R3.AC1` WHEN the user selects a card on the list, the system SHALL show its detail beside the list.
   - Acceptance check: selecting a card shows its effect text while the list stays visible.
2. `R3.AC2` The system SHALL show the same detail the catalog shows.
   - Acceptance check: a card opened from a list carries what the same card carries in the catalog.
3. `R3.AC3` IF a card cannot be shown, THEN the system SHALL say so rather than leaving the panel blank.
   - Acceptance check: an entry the catalog cannot match states that rather than opening nothing.

## Non-Functional Requirements

- `NFR1` Responsiveness: a list of any stored size is grouped and shown within 150 ms. Bridged by `R1.AC1` and `R2.AC2`.
- `NFR2` Honesty: every entry a list holds is either shown or counted as unmatched, and the numbers add up. Bridged by `R1.AC5` and `R1.AC6`.
- `NFR3` Offline operation: reading a stored list needs no network. Bridged by `R2.AC2`.
- `NFR4` Accessibility: each group and each card reads as a sentence naming the card, its kind and its status, and the screen is navigable by keyboard. Bridged by `R1.AC3` and `R3.AC1`.
- `NFR5` Concurrency safety: the feature builds and runs under Swift 6 strict concurrency checking with no data-race diagnostics suppressed.

## Constraints And Dependencies

- `C1` The lists are `banlist-history`'s, already stored and certified. This feature reads them; it does not fetch or change them.
- `C2` A stored entry carries no card kind, so grouping by kind needs the catalog joined to it.
- `C3` Entries are keyed by `konami_id`, which 203 of 14,566 cards do not carry. A list can therefore name a card this application cannot show, which is why `R1.AC6` exists.
- `C4` Only the three restricted statuses are stored. A card absent from a list is unrestricted on it, and unrestricted cards are not part of a list.
- `C5` The detail panel is `card-detail`'s, reused as it is in the catalog and the deck editor.
- `C6` Target platform is macOS 27 on arm64, built with Swift 6.4 and Swift Package Manager.

## Out Of Scope

- Editing a list, which is nobody's to edit.
- Comparing two lists side by side, which `banlist-history` can already answer and which deserves its own screen.
- Showing a card's history from this screen, which the detail panel already carries.
- Downloading lists, which `catalog-filters` wired and which this screen only links to.
