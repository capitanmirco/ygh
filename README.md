# YGODeckManager

A native macOS application for managing a personal Yu-Gi-Oh! collection and deck
portfolio. Single local user, offline-first, no accounts and no server.

## Status

Eleven specifications are complete and certified: `card-catalog`,
`deck-builder`, `collection-tracker`, `deck-analytics`, `pricing`,
`banlist-history`, `card-detail`, `deck-editing`, `visual-language`,
`catalog-filters` and `italian-vocabulary`. The application acquires the full card pool, keeps it current,
stores artwork locally, and browses, builds, tracks, analyses and prices
entirely offline.

The catalog opens showing cards and narrows as you type, 200 at a time against
a stated total. Selecting a card opens a panel beside the results carrying its
text, its release dates, its printings, all five price sources, the copies you
own, the decks using it, and what every published Forbidden & Limited List has
said about it since 1999.

A deck is freely editable: search and insert, set a count outright, drag a card
from one section to another or move it from the keyboard, and undo any of it.

The catalog narrows ten ways: card type, attribute, level, monster type,
archetype, attack and defence, release year, format, cards owned, and
membership of a published Forbidden & Limited List — choose the list from March
2005 and the grid shows the cards it named, with the statuses it gave them.

The catalog's vocabulary reads in Italian. The upstream localises a card's name
and text and nothing else — a card reads *Un Oceano Leggendario* and, under it,
*Field Spell* — so the kinds, attributes, monster types and the rarities the
Italian market renames are translated here. A term the table does not hold is
shown as published rather than blanked: the game keeps adding kinds.

Colour carries meaning rather than decorating. A card's frame — monster, spell,
trap, fusion, synchro, Xyz, link — is marked in its own colour wherever the card
appears, so a grid or a deck list can be read without reading every label.

## Requirements

- macOS 27 or later, Apple silicon
- Xcode 16.3 or later (the toolchain ships the swift-testing macro plugin and
  XCTest; the Command Line Tools alone cannot build or run the test suite)
- Swift 6.4

## Building and running

```bash
swift build          # builds every module and the app executable
swift test           # 94 tests across 8 targets
swift run YGODeckManager
```

First launch downloads the catalog: one 23.7 MB request for the English dataset
and one 17.3 MB request for the Italian one, then thumbnails fill in behind the
interface.

## Layout

A Swift Package Manager monorepo. The app target is a thin composition root;
everything else lives in local packages.

| Module | Responsibility |
| --- | --- |
| `YGOCore` | Domain types and every protocol the other modules meet across. Depends on nothing. |
| `YGOPersistence` | SQLite schema, migrations, repositories, the catalog writer. |
| `YGONetworking` | Upstream client, artwork fetcher, and the one rate limiter both pass through. |
| `YGOSync` | Seeding and updating the catalog, and the banlist history. |
| `YGOBanlistHistory` | A card's status across every published list, and when it changed. Depends on `YGOCore` alone. |
| `YGOImageStore` | The on-disk artwork store and its background prefetcher. |
| `YGODesignSystem` | Spacing, colour and typography tokens, and the measured frame palette. |
| `YGOFeatureBrowser` | Card browsing, searching, filtering, paging. |
| `YGOFeatureCardDetail` | The panel beside the results: one card, assembled from every other module's ports. |
| `YGOComposition` | The composition root: the only place that knows every concrete implementation. |

Feature modules depend on `YGOCore` protocols, never on a concrete persistence
or networking type. That is what lets them be tested without SQLite or a
network, and what lets the whole graph be rebuilt against failing stubs to prove
the application works offline.

## Data source

Card data comes from the [YGOPRODeck public API](https://ygoprodeck.com/api-guide/).
No key, no authentication. Two constraints shape the design and are not
negotiable:

- **Images must not be hotlinked.** The host blacklists clients that serve its
  images directly. Every image is downloaded once and read from local disk
  afterwards.
- **Twenty requests per second, with a one-hour ban for exceeding it.** All
  outbound traffic passes a single rate limiter set to ten per second.

Ban lists are published for TCG, OCG and GOAT only. Edison and Master Duel
expose format membership but no restrictions, so those lists are maintained by
hand and preserved across catalog updates.

**Historical** lists come from a second, independent upstream:
[`yaml-yugi-limit-regulation`](https://github.com/DawnbrandBots/yaml-yugi-limit-regulation),
which publishes 177 lists across TCG, OCG, Master Duel and Rush Duel, from
1999-08-01 onwards. Its dated files are served but not indexed, so the dates are
enumerated through the GitHub contents API and the bodies fetched from GitHub
Pages — two hosts for one source. Its TCG dates are the European effective
dates, so the April 2024 list is 2024-04-22 and not the American 2024-04-15.

The two sources are never reconciled. Where they disagree about a card, both
figures are reported. On the 222 cards they both described on 2026-09-21 there
were no disagreements, which is evidence rather than a guarantee.

Card names, text and artwork are copyright Konami Digital Entertainment and are
stored here for personal local use.

## Measured figures

Taken from the live API and from the test suite, not estimated:

| | |
| --- | --- |
| Cards | 14,566 English, 11,599 Italian |
| Artwork identifiers | 14,730 |
| Database, full catalog | 40 MB (budget 250 MB) |
| Artwork on disk | 388.4 MB, all 14,730 downloaded (budget 500 MB) |
| Printings / prices | 44,491 / 64,503 |
| Banlist history | 177 lists, 28,648 entries, 0.43 MB |
| Search latency, p95 | under 100 ms in a debug build |
| Card history latency | under 20 ms, worst case, debug build |
| Card detail, opening | under 100 ms, worst case, debug build |
| Narrowing, per keystroke | under 150 ms against 14,566 cards |
| Deck edit, applied and reloaded | under 100 ms on a 70-card deck |
| Frame colours | 11, covering 17 frames |
| Palette separation | ΔE ≥ 25 from any restriction colour, ≥ 18 within a deck section |
| Contrast | markers ≥ 3:1, text ≥ 4.5:1, both appearances |
| Vocabulary | 47 card kinds, 33 monster types, 7 attributes translated |
| Tests | 477, all green |

## Specification workflow

Work is governed by [Walden](https://github.com/andrearaponi/walden) specs under
`.walden/specs/`. Each holds EARS requirements, a reviewed design and an
executable task plan whose proofs are re-run on demand:

```bash
walden status banlist-history
walden verify banlist-history
walden release check --strict
```

Each `design.md` records the architectural decisions and the alternatives
weighed against them, so there is no separate ADR directory.

## Tests

Database tests run against an in-memory SQLite database. Network tests run
against recorded fixtures in `fixtures/`, captured from the live endpoints and
chosen to cover the structural edge cases the real data contains — untranslated
cards, cards with several artworks, every ban status, and the duplicate format
entries upstream publishes for a handful of cards. No test contacts a live host.

The banlist fixtures are the complete published record rather than a sample: all
177 lists are recorded, because a proof that the stored list count matches the
published one cannot be made from three sampled lists.

Where a guard exists to discard stale work — a search result for text the user
has moved past — the test that covers it was checked by removing the guard and
confirming the test fails. A test that passes either way proves nothing.

The palette is arithmetic, not taste. Every frame colour is measured against
every restriction colour and against every other frame it can share a deck
section with, and against the surface it is drawn on, in both appearances. The
game's own effect-monster orange and normal-monster yellow are this
application's "limited" and "semi-limited", which is the kind of collision only
measuring catches.

One thing here is deliberately not proven automatically: the drag gesture in the
deck editor. What is proven is the drop handler beneath it and the keyboard path
beside it, so the gesture is an affordance rather than the only way to do
something. `deck-editing`'s `C6` says so rather than leaving it implied.
