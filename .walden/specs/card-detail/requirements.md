---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T08:49:38Z
last_modified: 2026-09-21T08:49:38Z
approved_fingerprint: sha256:bf93d013d7466e4bd8e735ac812d3a33b176694ccfa6c6d4030856458722b742
---

# Requirements Document

## Introduction

The browser today answers a question and then forgets it: it opens on "Cerca una carta per iniziare", searches only when Enter is pressed, and a card tile leads nowhere. This feature makes the catalog something you can look through rather than only query, and makes a card something you can open.

The detail gathers what five certified specifications already store — the card's text, its artwork, its printings, its prices, the copies owned, the decks using it, and its status across every published list — into one panel. Almost nothing here is new data. What is new is the assembling, the paging, and saying plainly when a piece is missing.

Facts measured against the user's own database on 2026-09-21:

- **The catalog is 14,566 cards.** An unfiltered query returns its first 200 in 3.9 ms and the total count in 0.1 ms, so opening on the whole catalog costs nothing worth avoiding.
- **2,981 cards carry no Italian translation**, out of 14,566.
- **85 cards carry no release date at all.** 14,043 have a TCG date and 14,015 an OCG date.
- **552 cards have no printing recorded.** The other 14,014 share 44,491 printings across 48 rarities, none of them blank. Blue-Eyes White Dragon alone has 78.
- **289 cards have no price from any source**, and only 11,530 are priced by all five. Cardmarket covers 14,029, TCGplayer 14,003, CoolStuffInc 12,276, eBay 12,243, Amazon 11,952.
- **124 cards have more than one artwork**, out of 14,730 artworks.
- **Only thumbnails are stored**: 14,730 of them, 268×391 pixels, 417 MB on disk. No full-resolution image is held yet.
- **The collection is empty** — zero entries, zero locations — while two decks hold 74 slots across 65 distinct cards. Upstart Goblin appears in both.

## Requirements

### R1 Looking through the catalog

**User Story:** As a duelist, I want the browser to show me cards straight away and narrow as I type, so that I can look through the catalog instead of having to know what I am looking for.

#### Acceptance Criteria

1. `R1.AC1` WHEN the browser opens, the system SHALL show cards without the user having typed anything.
   - Acceptance check: on opening, the grid holds cards rather than an instruction to search.
2. `R1.AC2` WHEN the query text is emptied, the system SHALL show the unnarrowed catalog again.
   - Acceptance check: typing and then clearing returns the grid to what it showed on opening, not to an empty state.
3. `R1.AC3` WHEN the query text changes, the system SHALL update the results without the user submitting them.
   - Acceptance check: successive keystrokes narrow the grid with no Enter pressed.
4. `R1.AC4` The system SHALL report how many cards match and how many of them are shown.
   - Acceptance check: an unnarrowed browser reports 14,566 matching and 200 shown.
5. `R1.AC5` WHEN the user asks for more of the current results, the system SHALL show the next batch alongside those already shown.
   - Acceptance check: after one advance the grid holds 400 cards of the same result, in the same order, with no card appearing twice.
6. `R1.AC6` WHILE filters are applied and the query text is empty, the system SHALL narrow the shown cards to those the filters admit.
   - Acceptance check: a format filter alone reduces the reported match count below 14,566 and every shown card is legal in that format.
7. `R1.AC7` IF a query matches no card, THEN the system SHALL report that as a settled answer.
   - Acceptance check: a query matching nothing shows a stated "no matches" rather than a spinner or a bare empty grid.

### R2 Opening a card

**User Story:** As a duelist, I want to open a card and read it, so that I can see what it does without leaving the browser.

#### Acceptance Criteria

1. `R2.AC1` WHEN the user selects a card in the results, the system SHALL show its detail beside them.
   - Acceptance check: after selecting, the detail describes that card while the grid is still visible with its selection marked.
2. `R2.AC2` WHEN a card's detail is shown, the system SHALL report its name, its type and its effect text in the chosen language.
   - Acceptance check: a translated card reads in Italian, and switching language changes all three.
3. `R2.AC3` IF a card has no translation in the chosen language, THEN the system SHALL present its English text and state that it is untranslated.
   - Acceptance check: one of the 2,981 untranslated cards reads in English and is marked as untranslated rather than appearing blank.
4. `R2.AC4` WHEN a card's detail is shown, the system SHALL report the date the card was released and which region that date belongs to.
   - Acceptance check: a card released in both regions reports both dates, each named; a card released in only one reports that one, named.
5. `R2.AC5` IF a card has no release date recorded, THEN the system SHALL state that it is unknown.
   - Acceptance check: one of the 85 cards with neither date reports an unknown release date rather than an empty field.
6. `R2.AC6` WHERE a card has more than one artwork, the system SHALL let the user see each of them.
   - Acceptance check: one of the 124 multi-artwork cards offers all its artworks, and a single-artwork card offers no chooser.
7. `R2.AC7` WHEN the user selects a different card, the system SHALL replace the detail without disturbing the results.
   - Acceptance check: selecting a second card changes the detail while the grid keeps the same cards, the same order and the same scroll position.

### R3 Where it was printed and what it costs

**User Story:** As a collector, I want to see every printing of a card and what each source says it is worth, so that I know what I would be buying and roughly what it costs.

#### Acceptance Criteria

1. `R3.AC1` WHEN a card's detail is shown, the system SHALL report every printing with its set name, its set code and its rarity.
   - Acceptance check: Blue-Eyes White Dragon reports 78 printings, each carrying all three.
2. `R3.AC2` IF the catalog holds no printing for a card, THEN the system SHALL state that none is recorded.
   - Acceptance check: one of the 552 cards with no printing says so rather than showing an empty table.
3. `R3.AC3` WHEN a card's detail is shown, the system SHALL report the figure each price source gives, naming the source and the currency.
   - Acceptance check: a card priced by all five reports five figures, each naming its source, with Cardmarket in euro and the others in dollars.
4. `R3.AC4` IF a source holds no price for a card, THEN the system SHALL report it as unpriced.
   - Acceptance check: a card priced by fewer than five sources shows the missing ones as unpriced rather than as zero.
5. `R3.AC5` WHEN prices are shown, the system SHALL report when they were observed.
   - Acceptance check: the prices carry the observation time recorded with them, not the time the panel was opened.
6. `R3.AC6` The system SHALL state that a price describes the card and not a particular printing.
   - Acceptance check: wherever a figure appears beside printings of differing rarity, the panel says the figure does not distinguish them.

### R4 Where the copies are

**User Story:** As someone who owns cards and builds decks, I want to know whether I already have this one and what it is already in, so that I do not buy a card twice or pull it out of a deck by accident.

#### Acceptance Criteria

1. `R4.AC1` WHEN a card's detail is shown, the system SHALL report how many copies are owned and where they are kept.
   - Acceptance check: a card with copies in two locations reports both locations with the count held in each.
2. `R4.AC2` IF no copy of a card is owned, THEN the system SHALL state that none is held.
   - Acceptance check: against an empty collection, the detail says no copy is held rather than showing nothing at all.
3. `R4.AC3` WHEN a card's detail is shown, the system SHALL report which decks use it and how many copies each holds.
   - Acceptance check: Upstart Goblin reports both decks with their counts; a card in no deck reports none.
4. `R4.AC4` The system SHALL report a deck's copies by the section holding them.
   - Acceptance check: a card held in both the main deck and the side deck is reported once per section rather than as a single total.

### R5 How the game has treated it

**User Story:** As a duelist, I want to see a card's restriction history where I am already reading the card, so that I understand what it is and what it has been.

#### Acceptance Criteria

1. `R5.AC1` WHEN a card's detail is shown, the system SHALL report its current status in the chosen format.
   - Acceptance check: a restricted card reports its status and an unrestricted one reports that it is unrestricted.
2. `R5.AC2` WHEN a card's detail is shown, the system SHALL report the dates on which its status changed.
   - Acceptance check: a card forbidden in one year and freed in another reports both dates with the statuses either side.
3. `R5.AC3` IF a card has never been restricted in the chosen format, THEN the system SHALL state that.
   - Acceptance check: a card named on no list of that format says it has never been restricted, rather than showing an empty history.
4. `R5.AC4` IF a card cannot be matched to the published lists, THEN the system SHALL state that its history is unavailable.
   - Acceptance check: one of the 203 cards carrying no `konami_id` reports an unavailable history, worded differently from a card that was simply never restricted.
5. `R5.AC5` WHERE the stored history and the catalog disagree about a card's current status, the system SHALL report both.
   - Acceptance check: a card the two sources describe differently shows both figures, each named with its source.

## Non-Functional Requirements

- `NFR1` Responsiveness while typing: the results shown follow a change to the query text within 150 ms, so narrowing feels like filtering rather than searching. Bridged by `R1.AC3` and `R1.AC4`.
- `NFR2` Responsiveness on opening: every part of a card's detail that comes from stored data is shown within 100 ms of selecting it. Bridged by `R2.AC1`, `R3.AC1` and `R5.AC2`.
- `NFR3` Offline operation: every section of the detail except the full-resolution artwork is produced from stored data with no network. Bridged by `R3.AC3`, `R4.AC3` and `R5.AC2`.
- `NFR4` Honesty about absence: a piece of information the catalog does not hold is stated as absent, never rendered as zero, as a blank, or as a confident-looking default. Bridged by `R2.AC5`, `R3.AC2`, `R3.AC4`, `R4.AC2` and `R5.AC4`.
- `NFR5` Accessibility: every figure in the detail reads as a sentence naming what it is and where it came from, and the grid, the detail and every section within it are reachable by keyboard alone. Bridged by `R2.AC1`, `R3.AC3` and `R3.AC5`.
- `NFR6` Concurrency safety: the feature builds and runs under Swift 6 strict concurrency checking with no data-race diagnostics suppressed.

## Constraints And Dependencies

- `C1` No full-resolution artwork is stored: the image store holds 14,730 thumbnails at 268×391 and nothing else. The `card-catalog` specification already requires that opening a card detail retrieves and stores its full image, and that an artwork which cannot be retrieved is replaced by a placeholder carrying the card's name. This feature relies on both and restates neither.
- `C2` Prices describe a card, not a printing. A Secret Rare and a Common of the same card carry the same figure, which is `pricing`'s stated and unavoidable limit.
- `C3` Restriction history joins on `konami_id`, which 203 of 14,566 cards do not carry. Those cards can have no history, which is why `R5.AC4` exists.
- `C4` The collection currently holds zero entries and zero locations, so `R4.AC1` is proven against seeded data rather than the live database.
- `C5` Prices are stored in the currency their source publishes: Cardmarket in euro, the other four in dollars. No conversion exists and none is to be invented.
- `C6` The unnarrowed catalog is shown 200 cards at a time by decision, not by limitation, so the grid never holds 14,566 live tiles.
- `C7` Target platform is macOS 27 on arm64, built with Swift 6.4 and Swift Package Manager.

## Out Of Scope

- Editing a deck or a collection from the detail panel, which belongs to `deck-editing` and `collection-tracker`.
- Editing a card's hand-maintained ban status, which `card-catalog` already owns.
- Retrieving and storing full-resolution artwork, which `card-catalog` specifies.
- Buying, price alerts, or anything that leaves the application.
- Showing a whole historical list, which `banlist-history` answers and a later screen may present.
