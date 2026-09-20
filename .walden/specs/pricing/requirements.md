---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-20T21:27:48Z
last_modified: 2026-09-20T21:27:48Z
approved_fingerprint: sha256:38e8f8ce4a61593918a228bff44a946ecd3f25fef935798fe52907ffc8359856
---

# Requirements Document

## Introduction

Pricing puts a number on what a collection holds and what a deck would cost. It is the last of the five specifications and the one where being honest about the data matters most, because the data is poor in ways a figure on screen does not show.

This feature covers a card's price from a chosen source, disagreement between sources, the value of a collection, the cost of a deck and of completing one, the most valuable cards held, and stating plainly what each figure is and is not.

Facts established against the user's own database on 2026-09-20. They are the reason this specification is shaped the way it is:

- **The sources do not agree, and not by a little.** For cards priced by at least three of them, the median ratio between the highest and lowest is **74×**, and the worst is **50,000×**. `Gate Guardian` is listed at €999.99 on Amazon and €0.02 on Cardmarket.
- **Two of the five are a different kind of number.** eBay exceeds Cardmarket tenfold on **7,096 of 12,069** cards, and Amazon on **4,208 of 11,761**. TCGplayer does so on **289 of 13,949**. eBay and Amazon carry asking prices; Cardmarket and TCGplayer carry market prices, and they broadly agree with each other.
- **Averaging them would be worse than useless.** The mean of €999.99 and €0.02 describes nothing that exists.
- **Prices are per card, not per printing.** A Secret Rare and a Common of the same card carry the same figure. 64,503 price rows cover 14,277 of 14,566 cards, while only **12,354 of 44,491 printings** carry a price of their own.
- **Every price was observed at one moment**, the last catalog synchronisation. There is no separate price feed and no per-card refresh, so a figure is exactly as old as the catalog.

The user has chosen Cardmarket as the reference source, since it is the European market they actually buy in, and has asked for cards to be flagged when another source disagrees sharply rather than having outliers silently dropped.

## Requirements

### R1 What a card is worth

**User Story:** As a collector, I want a card's price from the market I actually buy in, so that the number means something where I live.

#### Acceptance Criteria

1. `R1.AC1` WHEN the user asks a card's price, the system SHALL report the value recorded for the chosen source.
   - Acceptance check: a card priced on Cardmarket reports that figure and not another source's, and changing the chosen source changes the figure reported.
2. `R1.AC2` The system SHALL report every source's price for a card alongside the chosen one.
   - Acceptance check: a card priced by five sources reports five figures, each named by its source.
3. `R1.AC3` IF the chosen source has no price for a card, THEN the system SHALL report it as unpriced rather than as zero.
   - Acceptance check: a card absent from the chosen source reports no price, and is excluded from totals rather than contributing nothing-as-zero.
4. `R1.AC4` The system SHALL report when each price was observed.
   - Acceptance check: a reported price carries the observation time stored with it, which is the last catalog synchronisation.
5. `R1.AC5` The system SHALL report the same price for every printing of a card.
   - Acceptance check: two printings of one card report identical prices, because the source publishes one figure per card.

### R2 When the sources disagree

**User Story:** As a collector, I want to know when a price is doubtful, so that I do not act on a number that one marketplace invented.

#### Acceptance Criteria

1. `R2.AC1` WHERE another source's price for a card exceeds the chosen source's by a factor of ten or more, the system SHALL mark that card as disputed.
   - Acceptance check: a card priced at €0.02 on the chosen source and €999.99 elsewhere is marked disputed, and one whose sources agree within that factor is not.
2. `R2.AC2` WHEN a card is disputed, the system SHALL report which source disagrees and by how much.
   - Acceptance check: a disputed card names the disagreeing source and the ratio between the two figures.
3. `R2.AC3` The system SHALL include a disputed card's chosen-source price in every total it belongs to.
   - Acceptance check: marking a card disputed does not change any total it contributes to; the flag informs rather than excludes.
4. `R2.AC4` The system SHALL report how many cards in a collection or deck are disputed.
   - Acceptance check: a total is accompanied by the count of disputed cards behind it.

### R3 What a collection is worth

**User Story:** As a collector, I want to know what I am holding, so that I can insure it, sell it, or simply know.

#### Acceptance Criteria

1. `R3.AC1` WHEN the user asks a collection's value, the system SHALL report the sum of each copy's price at the chosen source.
   - Acceptance check: a collection of three copies at €2 and one at €5 reports €11.
2. `R3.AC2` The system SHALL exclude copies the chosen source does not price, and report how many were excluded.
   - Acceptance check: a collection holding one unpriced card reports a total covering the rest and states that one copy could not be valued.
3. `R3.AC3` The system SHALL report a collection's value broken down by rarity.
   - Acceptance check: the per-rarity values sum to the collection's total value.
4. `R3.AC4` The system SHALL report a collection's value broken down by storage location.
   - Acceptance check: the per-location values, including unfiled copies, sum to the collection's total value.
5. `R3.AC5` The system SHALL report a collection's value beside what the user recorded as paid for it.
   - Acceptance check: a collection with recorded purchase prices reports both figures, and the difference between them.

### R4 What a deck costs

**User Story:** As a duelist, I want to know what a list would cost to build, so that I can tell an idea from a plan.

#### Acceptance Criteria

1. `R4.AC1` WHEN the user asks a deck's cost, the system SHALL report the sum of every copy it holds at the chosen source.
   - Acceptance check: a deck's cost equals the sum over its slots of price times quantity, across all three sections.
2. `R4.AC2` The system SHALL report what completing a deck would cost, counting only the copies the collection does not already hold.
   - Acceptance check: a deck asking three copies of a €4 card the user owns one of contributes €8 to the completion cost and €12 to the full cost.
3. `R4.AC3` WHEN a deck needs nothing, the system SHALL report its completion cost as zero.
   - Acceptance check: a deck built entirely from owned cards reports zero to complete and a non-zero cost to build.
4. `R4.AC4` The system SHALL report the deck's most expensive cards.
   - Acceptance check: the reported cards are ordered by the cost they contribute, which is price times the copies the deck holds.
5. `R4.AC5` The system SHALL exclude copies the chosen source does not price, and report how many were excluded.
   - Acceptance check: a deck holding one unpriced card reports a cost covering the rest and states that one card could not be valued.

### R5 The cards worth the most

**User Story:** As a collector, I want to know which of my cards are the valuable ones, so that I know what to protect.

#### Acceptance Criteria

1. `R5.AC1` WHEN the user asks for their most valuable cards, the system SHALL report them ordered by the value of the copies held.
   - Acceptance check: a card held twice at €10 ranks above one held once at €15.
2. `R5.AC2` The system SHALL report, for each card listed, how many copies are held and where they are.
   - Acceptance check: each entry names its copy count and its storage locations.
3. `R5.AC3` The system SHALL mark disputed cards in the list.
   - Acceptance check: a card whose sources disagree sharply is marked, so a suspiciously high ranking can be checked.

### R6 Saying what a figure is

**User Story:** As someone who will act on these numbers, I want to know how much to trust them, so that I do not treat an estimate as an appraisal.

#### Acceptance Criteria

1. `R6.AC1` The system SHALL state which source every reported figure came from.
   - Acceptance check: no total or card price is presented without its source named.
2. `R6.AC2` The system SHALL state when the prices behind a figure were observed.
   - Acceptance check: every total carries the observation time of the prices it was computed from.
3. `R6.AC3` The system SHALL state that a figure is an estimate rather than a valuation.
   - Acceptance check: every total is accompanied by wording that does not claim to be an appraisal, and names the reason: the source publishes one price per card rather than one per printing.
4. `R6.AC4` The system SHALL report how much of a collection or deck could not be valued.
   - Acceptance check: a figure computed over nine of ten cards says so, rather than presenting itself as covering all ten.

## Non-Functional Requirements

- `NFR1` Responsiveness: a collection of ten thousand copies is valued within 200 ms, so the figure can be shown on opening rather than behind a button. Bridged by `R3.AC1` and `R3.AC3`.
- `NFR2` Arithmetic soundness: money is summed without accumulating floating-point error across ten thousand copies, and every reported total is non-negative. Bridged by `R3.AC1` and `R4.AC1`.
- `NFR3` Offline operation: every figure is computed from prices already stored, so nothing here needs a network. Bridged by the stored-price acceptance checks on `R1.AC1` and `R3.AC1`.
- `NFR4` Honesty: no figure is presented without its source, its observation time, its coverage and the fact that it is an estimate. Bridged by all four criteria of `R6`.
- `NFR5` Accessibility: the valuation screens are reachable by keyboard alone, and each figure reads as a sentence naming the amount, the source and what it covers. Bridged by `R6.AC1` and `R6.AC4`.
- `NFR6` Concurrency safety: the feature builds and runs under Swift 6 strict concurrency checking with no data-race diagnostics suppressed.

## Constraints And Dependencies

- `C1` This feature reads prices stored by `card-catalog`, the collection recorded by `collection-tracker`, and the decks built by `deck-builder`. It reuses the shortfall from `collection-tracker` for `R4.AC2` rather than counting copies again.
- `C2` Prices are published per card, not per printing. A Secret Rare and a Common of the same card carry the same figure, so a collection's value is an estimate and cannot be otherwise. This is the reason `R6.AC3` exists.
- `C3` The five sources disagree by a median factor of 74 and a maximum of 50,000. eBay and Amazon carry asking prices and exceed Cardmarket tenfold on 59% and 36% of cards respectively; TCGplayer does so on 2%. Averaging them is not an option, which is why `R1.AC1` reports one chosen source.
- `C4` Cardmarket is the default source, chosen because it is the European market the user buys in. It is a default rather than a judgement about which marketplace is correct.
- `C5` Every price carries the observation time of the last catalog synchronisation. There is no separate price feed, so prices are refreshed only when the catalog is, and a figure is exactly as old as the catalog.
- `C6` 289 of 14,566 cards carry no price from any source, and 32,137 of 44,491 printings carry none of their own. Coverage is reported rather than assumed.
- `C7` Currency is not converted. Cardmarket publishes in euro and TCGplayer in dollars, and the application reports the figure in the currency its source published.
- `C8` Target platform is macOS 27 on arm64, built with Swift 6.4 and Swift Package Manager.

## Out Of Scope

- Fetching prices from any marketplace directly, or refreshing them independently of the catalog.
- Converting between currencies.
- Price history, trends, or any claim about where a price is going.
- Condition-adjusted valuation. The sources publish one figure per card, and applying a multiplier for a played copy would be inventing data.
- Suggesting what to buy, sell or trade.
- Any outbound network traffic.
