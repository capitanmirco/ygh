# YGODeckManager

A native macOS application for managing a personal Yu-Gi-Oh! collection and deck
portfolio. Single local user, offline-first, no accounts and no server.

## Status

Six specifications are complete and certified: `card-catalog`, `deck-builder`,
`collection-tracker`, `deck-analytics`, `pricing` and `banlist-history`. The
application acquires the full card pool, keeps it current, stores artwork
locally, and browses, builds, tracks, analyses and prices entirely offline.

`banlist-history` acquires and stores the published Forbidden & Limited Lists
and answers what a card's status was on any of them; displaying that history is
the `card-detail` specification's work and is not built yet.

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
| `YGODesignSystem` | Spacing, colour and typography tokens. |
| `YGOFeatureBrowser` | Card browsing, searching, filtering. |
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
| Tests | 317, all green |

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
