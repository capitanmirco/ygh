---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-20T10:35:09Z
last_modified: 2026-09-20T10:35:09Z
approved_fingerprint: sha256:6c524234a6b8ec40e469976a4a3b2a078b8b8b0cbf16b5e5e8286a31c860aa25
---

# Requirements Document

## Introduction

The collection tracker records which physical cards the user actually owns, and answers the question that makes a deck builder practical: what is missing before this list can be sleeved up.

This feature covers recording owned copies against the printings the catalog knows, the details that distinguish one copy from another, where a copy is physically kept, browsing and totalling a collection, reporting what a deck still needs, and keeping a backup of data that exists nowhere else.

Facts established against the live catalog on 2026-09-20, which shape several requirements:

- **The catalog holds 44,491 printings across 14,566 cards**, averaging 3.1 per card and reaching 78 for one. Recording which printing a copy is therefore means choosing from a list that is sometimes long.
- **552 cards have no printing at all**, 30 of them legal in TCG. A copy of one of these cannot be recorded against a printing, and the feature must not make those cards unrecordable.
- **48 distinct rarities** appear, from `Common` to `Quarter Century Secret Rare`. They come from the catalog and are not a fixed list this application can hard-code.
- **Printings are English-coded.** 38,796 of the codes carry `EN`, 456 `PT`, and 1,808 carry no language segment at all. The upstream source publishes no Italian printings, and the Italian dataset repeats the same English codes. The user has chosen not to track the language of their copies, so this is recorded as a limit of what the catalog can describe rather than worked around.
- **72.2% of printings carry no price.** Any valuation built on them will be partial, which is the `pricing` specification's problem but is why this one stores what was paid rather than deriving worth.

The collection is hand-entered and exists nowhere else. Losing it cannot be undone by re-downloading anything, which is why `R6` exists and why `NFR2` is stated as strongly as it is.

## Requirements

### R1 Recording what you own

**User Story:** As a collector, I want to record the cards I physically hold, so that the application knows what I have rather than only what exists.

#### Acceptance Criteria

1. `R1.AC1` WHEN the user records a copy against a printing, the system SHALL increase the number of copies held of that printing by one.
   - Acceptance check: recording the same printing three times reports three copies of it and leaves every other printing unchanged.
2. `R1.AC2` WHEN the user removes a copy, the system SHALL decrease the number held by one and remove the entry once none are left.
   - Acceptance check: removing the last copy leaves no entry for that printing, and removing from a printing that is not held changes nothing.
3. `R1.AC3` WHEN the user sets the number of copies of a printing directly, the system SHALL store that number.
   - Acceptance check: setting four copies where one was held reports four; setting zero removes the entry.
4. `R1.AC4` WHERE a card has no printing in the catalog, the system SHALL allow copies of it to be recorded against the card itself.
   - Acceptance check: a card the catalog lists no printing for can still be recorded as owned, and its copies count towards that card's total.
5. `R1.AC5` The system SHALL report the total number of copies of a card held across all of its printings.
   - Acceptance check: two copies of one printing and one of another report three copies of that card.
6. `R1.AC6` IF the user records a copy against a printing that does not exist in the catalog, THEN the system SHALL refuse it and record nothing.
   - Acceptance check: an unknown printing identifier leaves the stored copy count unchanged and reports the refusal.

### R2 What distinguishes one copy from another

**User Story:** As a collector, I want to record the state and history of each copy, so that two copies of the same card are not treated as interchangeable when they are not.

#### Acceptance Criteria

1. `R2.AC1` WHEN the user records a copy, the system SHALL store its condition from the grades the trading-card market uses.
   - Acceptance check: a copy recorded as Lightly Played reports that grade, and the grades offered are Near Mint, Lightly Played, Moderately Played, Heavily Played and Damaged.
2. `R2.AC2` WHEN the user records what a copy cost and when it was acquired, the system SHALL store both.
   - Acceptance check: a copy recorded at a stated price and date reports both unchanged after a restart.
3. `R2.AC3` WHERE the user has not stated a price or an acquisition date, the system SHALL store the copy without them.
   - Acceptance check: a copy recorded with neither is stored, and reports no price rather than a price of zero.
4. `R2.AC4` WHEN the user edits a copy's condition, price, date or notes, the system SHALL store the change.
   - Acceptance check: each field edited in turn reports its new value and leaves the others as they were.
5. `R2.AC5` The system SHALL keep copies of one printing in different conditions as separate entries.
   - Acceptance check: two Near Mint and one Damaged copy of one printing report three copies in total and three entries distinguishable by grade.
6. `R2.AC6` The system SHALL report the total amount recorded as paid across a collection.
   - Acceptance check: a collection of copies with stated prices reports their sum, and copies with no stated price contribute nothing rather than zero-ing the total.

### R3 Where a copy is kept

**User Story:** As a collector with more than one binder, I want to know where a card physically is, so that finding it does not mean emptying every box.

#### Acceptance Criteria

1. `R3.AC1` WHEN the user creates a storage location, the system SHALL store it under the name given.
   - Acceptance check: a location named "Raccoglitore GOAT" is retrievable under that name afterwards.
2. `R3.AC2` WHEN the user assigns a copy to a location, the system SHALL report that copy under that location.
   - Acceptance check: a copy moved to a binder is listed under it and no longer among the unfiled copies.
3. `R3.AC3` IF a location holding copies is deleted, THEN the system SHALL keep those copies and report them as unfiled.
   - Acceptance check: deleting a binder holding five copies leaves all five recorded, none assigned to a location.
4. `R3.AC4` WHEN the user requests a card's whereabouts, the system SHALL report each location holding a copy of it together with the number held there.
   - Acceptance check: a card with two copies in one binder and one in another reports both locations with their counts.

### R4 Browsing the collection

**User Story:** As a collector, I want to look through what I own, so that the record is something I use rather than only something I feed.

#### Acceptance Criteria

1. `R4.AC1` The system SHALL report how many distinct cards and how many total copies a collection holds.
   - Acceptance check: a collection of three copies of one card and one of another reports two distinct cards and four copies.
2. `R4.AC2` WHEN the user searches the collection by card name, the system SHALL return only the owned cards whose name matches.
   - Acceptance check: a search naming an owned card returns it, and naming an unowned one returns nothing even though the catalog holds it.
3. `R4.AC3` WHEN the user filters the collection by set, rarity or condition, the system SHALL return only the copies satisfying every applied filter.
   - Acceptance check: filtering by one rarity returns only copies of that rarity, and combining it with a condition returns only copies satisfying both.
4. `R4.AC4` The system SHALL report how many copies of each rarity a collection holds.
   - Acceptance check: the reported counts per rarity sum to the collection's total copy count.
5. `R4.AC5` IF the collection holds nothing, THEN the system SHALL present an empty state distinct from a filter matching nothing.
   - Acceptance check: an empty collection and a filter that excludes everything are distinguishable without inspecting counts.

### R5 What a deck is missing

**User Story:** As a duelist, I want to know what I still need to buy before a deck can be built, so that the list on screen and the cards in my hands are the same thing.

#### Acceptance Criteria

1. `R5.AC1` WHEN the user asks what a deck needs, the system SHALL report each card the deck holds more copies of than the collection does, with the number still needed.
   - Acceptance check: a deck asking for three copies of a card the collection holds one of reports that card as needing two more.
2. `R5.AC2` The system SHALL count a card's owned copies across every printing when answering what a deck needs.
   - Acceptance check: a deck asking for two copies is satisfied by one copy of each of two different printings.
3. `R5.AC3` WHEN a deck asks for no more copies than the collection holds of every card, the system SHALL report that nothing is missing.
   - Acceptance check: a deck built entirely from owned cards reports an empty shortfall.
4. `R5.AC4` The system SHALL count every section of a deck when answering what it needs.
   - Acceptance check: a card held once and asked for once in the main section and once in the side section is reported as needing one more.
5. `R5.AC5` WHERE a deck holds a card the collection has no copies of at all, the system SHALL report the full number the deck asks for.
   - Acceptance check: a deck asking for three copies of an unowned card reports three needed, not two.
6. `R5.AC6` The system SHALL answer what a deck needs without altering the deck or the collection.
   - Acceptance check: deck slots and collection entries are unchanged after the report is produced.

### R6 Keeping the record safe

**User Story:** As a collector who typed all of this in by hand, I want a copy of it outside the application, so that a mistake or a lost machine does not mean starting again.

#### Acceptance Criteria

1. `R6.AC1` WHEN the user exports the collection, the system SHALL write every recorded copy with its printing, condition, count, price, acquisition date and location.
   - Acceptance check: an exported file holds one row per entry, and every stored field appears in it.
2. `R6.AC2` WHEN the user imports a previously exported collection, the system SHALL restore every entry it holds.
   - Acceptance check: exporting a collection, clearing it and importing the file back yields the same entries with the same counts and details.
3. `R6.AC3` IF an imported file is malformed, THEN the system SHALL leave the existing collection untouched and report the file as unreadable.
   - Acceptance check: a truncated or corrupt file leaves the stored entry count and contents unchanged.
4. `R6.AC4` IF an imported entry names a printing the catalog does not hold, THEN the system SHALL import the remaining entries and report that one as unresolved.
   - Acceptance check: a file with one unknown printing among known ones restores the known entries and names the unknown one.

## Non-Functional Requirements

- `NFR1` Responsiveness: recording, removing or editing a copy updates the reported totals within 50 ms for a collection of ten thousand copies. Bridged by `R1.AC1`, `R1.AC5` and `R4.AC1`, whose acceptance checks are measured under this budget.
- `NFR2` Data safety: the collection is hand-entered and cannot be recovered by re-downloading anything. No edit, deletion or import removes a recorded copy without an explicit confirmation, and an import never destroys what it cannot replace. Bridged by `R3.AC3`, `R6.AC2` and `R6.AC3`.
- `NFR3` Offline operation: every behaviour in this feature functions with no network connection, since it reads only the stored catalog and the user's own records. Bridged by the stored-catalog acceptance checks on `R4.AC2` and `R5.AC1`.
- `NFR4` Shortfall accuracy: what a deck needs is computed from the same copy-counting rule the deck builder validates with, so the two can never disagree about how many copies a card has. Bridged by `R5.AC2` and `R5.AC4`.
- `NFR5` Accessibility: the collection list, its filters and the shortfall report are reachable and operable by keyboard alone, and each shortfall entry reads as a sentence naming the card and the number still needed. Bridged by `R5.AC1`, which requires the number to be carried rather than implied.
- `NFR6` Concurrency safety: the feature builds and runs under Swift 6 strict concurrency checking with no data-race diagnostics suppressed.

## Constraints And Dependencies

- `C1` This feature reads the catalog produced by the `card-catalog` specification and the decks produced by `deck-builder`. The shortfall in `R5` uses the same limit-name copy counting that deck validation uses.
- `C2` The catalog's printings are English-coded: 38,796 carry `EN`, 456 `PT`, and 1,808 no language segment. The upstream source publishes no Italian printings. The user has chosen not to track the language of their copies, so a recorded copy identifies a set and a rarity but not a region.
- `C3` 552 cards carry no printing at all, 30 of them legal in TCG. Copies of those are recorded against the card rather than a printing (`R1.AC4`).
- `C4` Rarities come from the catalog and number 48 today. They are stored as the catalog reports them rather than mapped onto a fixed list this application defines.
- `C5` Condition grades are not in the catalog. The five in `R2.AC1` are the trading-card market's usual scale and are defined by this application.
- `C6` Target platform is macOS 27 on arm64, built with Swift 6.4 and Swift Package Manager.

## Out Of Scope

- Valuing a collection or a deck in money. Prices are stored by `card-catalog` and the `pricing` specification will use them; this feature records only what the user states they paid.
- Deck statistics and draw probability, covered by `deck-analytics`.
- Tracking the language or region of a copy, which the user has chosen not to record and which the catalog could not describe anyway.
- Reserving copies for a particular deck, or warning that two decks want the same physical cards.
- Trading, wishlists, or anything to do with acquiring cards from other people.
- Scanning cards by camera or importing from a marketplace account.
- Any outbound network traffic. Export writes a local file.
