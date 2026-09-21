---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T07:42:13Z
last_modified: 2026-09-21T07:42:13Z
approved_fingerprint: sha256:fa8df22d60842528f7d4f9693f093f5921d7050dae2d9c1e1016e44f37e7c20d
---

# Requirements Document

## Introduction

A card's current restriction says what a deck may hold today. Its history says what the game thought of that card over twenty-seven years, which is what a duelist means when they ask whether something "used to be banned".

This feature acquires the published Forbidden & Limited Lists, stores them, and answers what a card's status was on any list and when it changed. It does not display them; the `card-detail` specification will.

Facts established on 2026-09-21 against the published data and the user's own database:

- **The catalog cannot answer this.** YGOPRODeck publishes three current statuses — `ban_tcg`, `ban_ocg`, `ban_goat` — and nothing dated. There is no history endpoint and no date parameter; both were tried and return 404 and 400.
- **A second source has it.** The `yaml-yugi-limit-regulation` project publishes every list as JSON: **73 for the TCG from 1999-08-01 to the current one**, 23 for the OCG, 66 for Master Duel and 15 for Rush Duel. Each format also carries a `current.vector.json`, which is a pointer at the newest dated list and not a list of its own: for the TCG it reports 2026-05-18, which is already there as a dated file.
- **The join key is already stored.** Each list maps `konami_id` to a status, and the catalog holds a `konami_id` for 14,363 of its 14,566 cards. Across four lists spanning 1999 to 2026, **every identifier matched**.
- **The two sources agree.** On the 222 cards both describe as restricted in the current TCG list, there were **zero disagreements**. The newer source lists four cards the catalog has not yet picked up.
- **It is small.** A list averages 2.5 KB; all 177 lists across the four formats come to 0.43 MB and 28,648 entries, and were fetched in a few seconds.
- **Status is encoded as a number**: 0 forbidden, 1 limited, 2 semi-limited. A card absent from a list was unrestricted on it.

## Requirements

### R1 Acquiring the lists

**User Story:** As a duelist, I want the published lists stored locally, so that a card's history is there when I look at it rather than fetched while I wait.

#### Acceptance Criteria

1. `R1.AC1` WHEN the user synchronises the banlist history, the system SHALL retrieve every published list for the supported formats.
   - Acceptance check: after a synchronisation the stored list count matches the number the source publishes for each format.
2. `R1.AC2` WHEN a list is stored, the system SHALL record the date it took effect and the format it belongs to.
   - Acceptance check: a stored list reports both, and two lists of different formats sharing a date remain distinct.
3. `R1.AC3` WHEN a list is stored, the system SHALL record each card's status on it.
   - Acceptance check: the 2005-03-01 TCG list stores 77 entries, being 18 forbidden, 44 limited and 15 semi-limited.
4. `R1.AC4` WHEN the lists are synchronised again, the system SHALL store only the lists it does not already hold.
   - Acceptance check: a second synchronisation with no new lists published retrieves no list bodies and leaves the stored entries unchanged.
5. `R1.AC5` IF the banlist source is unreachable, THEN the system SHALL keep the lists already stored and report the failure.
   - Acceptance check: with the source unreachable, previously stored history still answers every question and the failure is reported without affecting the card catalog.
6. `R1.AC6` IF a list names a card the catalog does not hold, THEN the system SHALL store the remaining entries and report how many were unmatched.
   - Acceptance check: a list containing one unknown identifier stores its other entries and reports one unmatched.

### R2 A card's history

**User Story:** As a duelist, I want to see what a card's status was over time, so that I understand how the game has treated it.

#### Acceptance Criteria

1. `R2.AC1` WHEN the user asks a card's history in a format, the system SHALL report its status on every list of that format, in date order.
   - Acceptance check: a card restricted since 2005 reports one entry per list from that date onwards, oldest first.
2. `R2.AC2` The system SHALL report a card as unrestricted on a list that does not name it.
   - Acceptance check: a card absent from a list reports unrestricted for that list rather than being omitted from the history.
3. `R2.AC3` The system SHALL report only the lists published while a card existed.
   - Acceptance check: a card released in 2015 reports no status for lists published before it, rather than reporting it as unrestricted on them.
4. `R2.AC4` WHEN the user asks a card's history, the system SHALL report the dates on which its status changed.
   - Acceptance check: a card forbidden in 2005 and unrestricted in 2015 reports exactly two changes, with their dates.
5. `R2.AC5` IF a card has never appeared on any list of a format, THEN the system SHALL report that it has never been restricted in it.
   - Acceptance check: a card absent from every TCG list reports no changes and an explicit never-restricted answer.

### R3 A list as it stood

**User Story:** As a duelist who plays retro formats, I want to see a whole list as it was published, so that I can check a deck against the rules of its era.

#### Acceptance Criteria

1. `R3.AC1` WHEN the user asks for a list by date, the system SHALL report every card on it with its status.
   - Acceptance check: the 2005-03-01 TCG list reports its 77 cards, each with a status and a card name.
2. `R3.AC2` The system SHALL report the lists it holds for a format, in date order.
   - Acceptance check: the TCG lists are reported from 1999-08-01 to the most recent, with no gaps against what the source publishes.
3. `R3.AC3` WHEN the user asks what changed between two consecutive lists, the system SHALL report the cards whose status differs.
   - Acceptance check: two consecutive lists report as changed exactly the cards whose statuses differ, including those newly added and those dropped.

### R4 Saying where it came from

**User Story:** As someone reading a historical claim, I want to know who published it, so that I can weigh it.

#### Acceptance Criteria

1. `R4.AC1` The system SHALL report that the history came from a different source than the card catalog.
   - Acceptance check: a reported history names its source, which is not the card catalog's.
2. `R4.AC2` The system SHALL report when the history was last synchronised.
   - Acceptance check: a reported history carries the time of the last successful synchronisation, which is independent of the catalog's.
3. `R4.AC3` WHERE the stored history and the catalog's current status disagree for a card, the system SHALL report the disagreement.
   - Acceptance check: a card whose newest historical status differs from the catalog's current one is reported as disagreeing, naming both.

## Non-Functional Requirements

- `NFR1` Responsiveness: a card's full history in one format is reported within 20 ms, so a detail panel can show it on opening. Bridged by `R2.AC1` and `R2.AC4`.
- `NFR2` Independence: a failure of the banlist source never affects the card catalog, and a failure of the catalog never affects stored history. Bridged by `R1.AC5`.
- `NFR3` Offline operation: every question in `R2` and `R3` is answered from stored data with no network. Bridged by the stored-history acceptance checks on `R2.AC1` and `R3.AC1`.
- `NFR4` Honesty: a history states its source and its freshness, and says when it disagrees with the catalog. Bridged by all three criteria of `R4`.
- `NFR5` Concurrency safety: the feature builds and runs under Swift 6 strict concurrency checking with no data-race diagnostics suppressed.

## Constraints And Dependencies

- `C1` The history comes from `yaml-yugi-limit-regulation`, a project independent of YGOPRODeck. It is a second upstream dependency with its own availability, its own update schedule and its own errors.
- `C2` The join is by `konami_id`. The catalog holds one for 14,363 of 14,566 cards; the remaining 203 cannot be matched to any list and have no history.
- `C3` Status is published as 0, 1 or 2, and absence from a list means unrestricted. There is no fourth value and no explicit "unlimited" entry.
- `C4` The source publishes lists for TCG, OCG, Master Duel and Rush Duel, plus OCG regional and Genesys variants. This feature stores the first four; the others are out of scope.
- `C5` A card released after a list was published has no status on it. Absence therefore means two different things — unrestricted, or not yet printed — and `R2.AC3` separates them using the release date the catalog already stores.
- `C6` The two sources agreed on all 222 cards they both described when this was written. That is evidence, not a guarantee, which is why `R4.AC3` reports disagreement rather than assuming it cannot happen.
- `C7` Target platform is macOS 27 on arm64, built with Swift 6.4 and Swift Package Manager.

## Out Of Scope

- Displaying the history, which is the `card-detail` specification's work.
- Validating a deck against a historical list. Deck legality uses the current list for its format, and changing that would alter a contract `deck-builder` already holds.
- Genesys, OCG Asian-English and OCG China lists.
- Explaining why a card was restricted, which nobody publishes as data.
- Predicting future lists.
