---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T15:31:40Z
last_modified: 2026-09-21T15:31:40Z
approved_fingerprint: sha256:7c087149049c8127db0ba386e88816db8878bc1a98c3ef4dd4a7eca45dec768b
---

# Requirements Document

## Introduction

A deck list names cards and says nothing about them. Clicking an entry selects it for editing and nothing else — to read what a card does, you leave the deck, go to the catalog, search for it, and come back.

This feature puts the card beside the deck: selecting an entry shows what that card is and what it does, in the panel the catalog already has.

Facts measured against the user's own code and database on 2026-09-21:

- **The panel already exists and is certified.** `card-detail` built `CardDetailView` and `CardDetailViewModel`, which assemble a card's text, artwork, release dates, printings, prices, holdings, deck usage and restriction history from ports in `YGOCore`.
- **The deck editor already tracks a selection.** `selectedItem` returns the `DeckEntryItem` the keyboard is on, carrying the card's identifier, its section and its count.
- **What it does not have is the card.** A `DeckEntryItem` holds a `CardIdentifier`, a title and a frame; the panel needs a `Card`.
- **The deck editor is already two columns**: the sections and their entries, and the card search that adds to them.
- **The user's decks hold 65 distinct cards** across 74 slots, so the panel is opened and replaced constantly rather than once.
- **The catalog's detail column is capped at a quarter of the window**, which is what keeps the grid readable when the filters are open.

## Requirements

### R1 Reading a card without leaving the deck

**User Story:** As a deck builder, I want to see what a card does while I am looking at my deck, so that I do not have to go to the catalog and come back.

#### Acceptance Criteria

1. `R1.AC1` WHEN the user selects an entry in the deck, the system SHALL show that card's detail beside the deck.
   - Acceptance check: selecting an entry shows that card's name and effect text while the deck list stays visible.
2. `R1.AC2` WHEN a card's detail is shown from a deck, the system SHALL show the same information the catalog shows for it.
   - Acceptance check: the same card opened from a deck and from the catalog shows the same text, release dates, printings, prices and restriction history.
3. `R1.AC3` WHEN the user selects a different entry, the system SHALL replace the detail without disturbing the deck list.
   - Acceptance check: selecting a second entry changes the panel while the sections keep their order, their counts and their scroll position.
4. `R1.AC4` WHEN the user selects a candidate in the card search, the system SHALL show that card's detail.
   - Acceptance check: selecting a search result shows its detail before it has been added to the deck.
5. `R1.AC5` IF the catalog cannot supply the selected card, THEN the system SHALL say so rather than showing an empty panel.
   - Acceptance check: an entry whose card the catalog cannot return leaves a stated message rather than a blank column.
6. `R1.AC6` WHILE no entry is selected, the system SHALL invite a selection rather than showing an empty panel.
   - Acceptance check: a freshly opened deck shows a prompt in the panel.

### R2 Keeping the screen readable

**User Story:** As someone editing a deck on a laptop, I want the deck to stay the main thing on screen, so that adding a third column does not leave me with three narrow strips.

#### Acceptance Criteria

1. `R2.AC1` The system SHALL limit the card detail to at most a quarter of the window's width.
   - Acceptance check: at any window width the detail column is no wider than a quarter of it, and the deck keeps the rest.
2. `R2.AC2` The system SHALL keep the card detail at a readable width when the window is narrow.
   - Acceptance check: at the smallest supported window the detail is still wide enough to read a card's effect.
3. `R2.AC3` WHERE the user does not want the detail, the system SHALL let it be dismissed and brought back.
   - Acceptance check: the panel can be closed, the deck takes the space, and it returns on request with the same card.
4. `R2.AC4` The system SHALL let the detail be opened, dismissed and moved between cards from the keyboard.
   - Acceptance check: selecting entries and dismissing the panel are reachable without a pointer.

## Non-Functional Requirements

- `NFR1` Responsiveness: the detail follows a selection within 100 ms, so moving down a deck list with the arrow keys does not stutter. Bridged by `R1.AC1` and `R1.AC3`.
- `NFR2` Consistency: the panel is the catalog's, not a second one that will drift from it. Bridged by `R1.AC2`.
- `NFR3` Offline operation: everything but the full-resolution artwork is produced from stored data. Bridged by `R1.AC2`.
- `NFR4` Accessibility: the panel and every section in it are reachable by keyboard, and each figure reads as a sentence. Bridged by `R2.AC4`.
- `NFR5` Concurrency safety: the feature builds and runs under Swift 6 strict concurrency checking with no data-race diagnostics suppressed.

## Constraints And Dependencies

- `C1` The panel is `card-detail`'s. This feature supplies it with a card and a place to sit; it does not change what the panel shows.
- `C2` A deck entry carries a `CardIdentifier`, not a `Card`. Resolving one to the other is a catalog read.
- `C3` The first opening of a card still fetches its full-resolution artwork, because none is stored. That is `card-catalog`'s behaviour and is not changed here.
- `C4` The deck editor is already two columns. This makes three, which is why `R2` exists.
- `C5` Target platform is macOS 27 on arm64, built with Swift 6.4 and Swift Package Manager.

## Out Of Scope

- Changing what the card detail shows, which is `card-detail`'s contract.
- Editing the card from the panel, which `deck-editing` owns.
- Showing a card's detail in the collection or the statistics screens.
- Comparing two cards side by side.
