---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-20T21:30:07Z
last_modified: 2026-09-20T21:30:07Z
approved_fingerprint: sha256:9b25a5119bfe4cac8af98a9bc9cf7357518a9c7bdb6e050e4497cd8ec99b7b3d
source_requirements_approved_at: 2026-09-20T21:27:48Z
source_requirements_fingerprint: sha256:38e8f8ce4a61593918a228bff44a946ecd3f25fef935798fe52907ffc8359856
---

# Feature Design

## Architecture

Every figure is a sum of cents over a set of (card, quantity) pairs. A collection, a deck, the cards a deck still needs and the most valuable things held are all that same sum over a different set, so there is one function and four callers.

### Module graph

```
App ─▶ YGOFeaturePricing ─┐
                          ├─▶ YGOCore   (money, sources, quotes, valuation)
YGOPricing (the sums) ────┤
YGOPersistence (lookups) ─┘
```

`YGOPricing` depends on `YGOCore` alone. The repository supplies prices through a protocol, so a valuation is checkable without a database.

### Money is integer cents

Summing prices as `Double` over ten thousand copies accumulates error: ten thousand additions of `0.89` gives `8900.000000000853`. The error is small enough to vanish when rounded for display, which is exactly what makes it the kind of thing nobody notices going wrong.

Prices are converted to cents on the way in and summed as `Int`. The arithmetic is then exact by construction and `NFR2` needs no tolerance.

```swift
struct Money: Hashable, Sendable {
    let cents: Int
    let currency: Currency   // from the source; never converted
}
```

The currency travels with the amount because `C7` forbids conversion: Cardmarket publishes euro and TCGplayer dollars, and adding them would produce a number in no currency at all. Two `Money` values of different currencies cannot be summed, which the type enforces rather than a comment asking.

### One chosen source, never an average

The five sources disagree by a median factor of 74 and a maximum of 50,000. eBay exceeds Cardmarket tenfold on 59% of cards and Amazon on 36%, because those two carry asking prices rather than market prices.

So a figure comes from one source, named. Averaging `€999.99` and `€0.02` would produce `€500.00` — a number describing nothing that exists, presented with the authority of arithmetic.

<!-- assumed: Cardmarket is the default source (source: the user chose it, being the European market they buy in; C4 records that it is a default rather than a judgement) -->

### Disagreement is flagged, not resolved

When another source exceeds the chosen one by tenfold, the card is marked disputed and **its chosen-source price still counts in every total**. Deciding which of two figures is wrong would be inventing data. Marking it lets the user check a card whose ranking looks implausible.

## Data Model

No schema change. Pricing reads `card_price`, which `card-catalog` already fills, joined to the collection and the decks.

```swift
public enum PriceSource: String, CaseIterable {
    case cardmarket, tcgplayer, ebay, amazon, coolstuffinc

    var currency: Currency        // cardmarket → EUR, the rest → USD
    var carriesAskingPrices: Bool // ebay and amazon
}
```

`carriesAskingPrices` is not decoration. It records, in the type, why two of the five behave differently, so a later reader does not add them to an average.

The lookup the sums need:

```swift
public protocol PriceLookup: Sendable {
    /// Every source's price for the given cards, in one query.
    func prices(forCards: Set<CardIdentifier>) async throws
        -> [CardIdentifier: [PriceSource: Money]]
}
```

One query for a whole collection rather than one per card, which is what keeps `NFR1` a matter of arithmetic over ten thousand rows already in memory.

## Options Considered

1. **Integer cents over `Double`.** Doubles are simpler and the error is invisible after rounding. It is also the kind of error that grows with the collection and is never noticed, and money is the one place a reader will trust the last digit. Integers cost one conversion at each boundary.
2. **One chosen source over an average or a median.** An average is indefensible when two of five sources are a different kind of number. A median of five would be more robust and would still silently pick between markets on the user's behalf, and would make the figure unexplainable: no marketplace would quote it.
3. **Flagging disputes over excluding outliers.** Excluding them would give tidier totals. It would also mean the application deciding which price is wrong, on no evidence beyond disagreement, and quietly removing cards from a total the user believes is complete.
4. **Currency carried, not converted.** Converting would let the sources be compared. It would also require a rate the application does not have and cannot date, and would turn a published figure into a derived one.
5. **Reusing the shortfall for completion cost.** Counting the missing copies again here would be a second implementation of a rule that is already proven, and the two would eventually disagree about a card the user owns.

## Simplicity And Elegance Review

What keeps this small:

- One function sums cents over (card, quantity) pairs. The collection, a deck, a deck's shortfall and the most valuable cards are four callers, so a fix to coverage reporting fixes all four.
- Coverage is part of the result rather than a second call: a `Valuation` carries its total, how many copies it covered, how many it could not, and how many were disputed. `R6.AC4` is then impossible to forget, because the figure cannot be constructed without it.
- `Money` refuses to add two currencies, so `C7` is enforced by the compiler rather than by review.
- Disputes are computed once per card from the prices already fetched, not by a second pass over the sources.

Challenged once: the sums could live in `YGOAnalytics`, which already holds pure functions over decks. Rejected because that module answers how a deck behaves and this answers what it costs; a reader looking for one should not have to read the other, and analytics has no business knowing about a collection.

## Failure Modes And Tradeoffs

| Failure | Containment |
| --- | --- |
| The chosen source does not price a card | Excluded and counted as uncovered (`R1.AC3`, `R6.AC4`), never treated as zero |
| No source prices a card at all | The same; 289 of 14,566 cards are in this position |
| A source publishes an absurd figure | The card is marked disputed and its chosen-source price still counts (`R2.AC3`) |
| Prices are stale | Every figure carries the observation time, which is the last catalog synchronisation (`R6.AC2`) |
| A deck holds a card in two printings | Both cost the same, because the source publishes one price per card (`R1.AC5`) |
| Two currencies in one total | Impossible: `Money` does not add across currencies |

Accepted tradeoffs:

- **A collection's value is an estimate and cannot be otherwise.** Prices are per card, so a Secret Rare and a Common of the same card carry one figure. `R6.AC3` requires every total to say so and to say why.
- **Coverage is partial and stated.** 289 cards carry no price from any source, and the figure reports what it could not reach rather than quietly covering less than the user thinks.
- **Cardmarket is a default, not a verdict.** It was chosen because it is the market the user buys in. Someone buying on TCGplayer switches source and gets a different, equally valid figure.
- **Prices are as old as the catalog.** There is no separate feed, so a figure refreshes when the catalog does and never in between.
- **Condition is ignored.** A played copy is priced as a mint one, because applying a multiplier would invent data the sources do not publish.

## Verification Plan

The sums are tested as arithmetic with no database. Repository tests run against an in-memory database seeded from the recorded fixtures. The dispute rule is tested against the real shape of the data: a card priced at €0.02 on one source and €999.99 on another.

| Check | Observation that decides it |
| --- | --- |
| Chosen source | A card reports its chosen source's figure, and changing the source changes it |
| Every source shown | A card priced by five sources reports five figures, each named |
| Unpriced card | Reported as unpriced, excluded from totals rather than added as zero |
| Observation time | A reported price carries the time it was observed |
| Same price per printing | Two printings of one card report identical prices |
| Dispute detected | €0.02 against €999.99 is disputed; figures within tenfold are not |
| Dispute described | A disputed card names the disagreeing source and the ratio |
| Disputes still count | Marking a card disputed changes no total it belongs to |
| Dispute count reported | A total carries how many disputed cards are behind it |
| Collection total | Three copies at €2 and one at €5 gives €11 |
| Exact summation | Ten thousand copies at €0.89 sums to exactly €8,900.00, which floating point does not |
| Coverage reported | A collection with one unpriced card reports the rest and says one copy was not valued |
| Value by rarity | Per-rarity values sum to the collection's total |
| Value by location | Per-location values, unfiled included, sum to the collection's total |
| Value against spend | Both figures and their difference are reported |
| Deck cost | Equals price times quantity summed over every section |
| Completion cost | Three copies of a €4 card with one owned costs €8 to complete and €12 to build |
| Nothing missing | A fully owned deck costs zero to complete and more than zero to build |
| Deck's dearest cards | Ordered by price times copies held |
| Deck coverage | An unpriced card is excluded and reported |
| Most valuable held | Two copies at €10 rank above one at €15 |
| Copies and locations listed | Each entry names its copy count and where the copies are |
| Disputes marked in the list | A disputed card is marked so a suspicious ranking can be checked |
| Source always named | No figure is produced without its source |
| Time always carried | Every total carries its prices' observation time |
| Estimate stated | Every total says it is an estimate and why |
| Currency never mixed | Adding two currencies is refused rather than producing a number in neither |
| Valuation latency | Ten thousand copies are valued within 200 ms |
| Offline | Every figure is computed from stored prices with no network available |
| Accessibility | Each figure reads as a sentence naming the amount, the source and the coverage; screens are keyboard reachable |
| Concurrency | The new modules build under Swift 6 strict concurrency with no data-race diagnostics |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `PriceQuote` over the `PriceLookup` protocol; the chosen-source, all-sources, unpriced, observation-time and per-printing checks |
| `R2` | The tenfold dispute rule computed from the prices already fetched; the four dispute checks |
| `R3` | `Valuation.of(collection:)` summing cents; the total, exactness, coverage, rarity, location and spend checks |
| `R4` | The same sum over a deck's slots and over the shortfall; the cost, completion, nothing-missing, dearest and coverage checks |
| `R5` | The same sum ranked by contribution; the ordering, copies-and-locations and dispute-marking checks |
| `R6` | `Valuation` carrying source, observation time, coverage and estimate wording by construction; the four honesty checks |
| `NFR1` | One query for a whole collection, then arithmetic in memory; measured latency on ten thousand copies |
| `NFR2` | Integer cents and a `Money` type that refuses mixed currencies; the exactness and currency checks |
| `NFR3` | Every figure computed from stored prices; the offline check |
| `NFR4` | Source, time, coverage and estimate wording carried in the result type; the four `R6` checks |
| `NFR5` | Figures rendered from sentences naming amount, source and coverage; the accessibility check |
| `NFR6` | Value types and pure functions throughout; the strict-concurrency build check |
