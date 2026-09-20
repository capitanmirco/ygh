# YGODeckManager

A native macOS application for managing a personal Yu-Gi-Oh! collection and deck
portfolio. Single local user, offline-first, no accounts and no server.

## Status

The `card-catalog` feature is complete: the application acquires the full card
pool, keeps it current, stores artwork locally, and browses and searches it
entirely offline. Deck building, collection tracking, statistics and pricing are
separate specifications that consume this catalog and are not built yet.

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
| `YGOSync` | Seeding and updating the catalog. |
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

Card names, text and artwork are copyright Konami Digital Entertainment and are
stored here for personal local use.

## Measured figures

Taken from the live API and from the test suite, not estimated:

| | |
| --- | --- |
| Cards | 14,566 English, 11,599 Italian |
| Artwork identifiers | 14,730 |
| Database, full catalog | 35 MB (budget 250 MB) |
| Thumbnails, projected | 337 MB (budget 500 MB) |
| Search latency, p95 | under 100 ms in a debug build |

## Specification workflow

Work is governed by [Walden](https://github.com/andrearaponi/walden) specs under
`.walden/specs/`. Each holds EARS requirements, a reviewed design and an
executable task plan whose proofs are re-run on demand:

```bash
walden status card-catalog
walden verify card-catalog
```

`.walden/specs/card-catalog/design.md` records the architectural decisions and
the alternatives weighed against them, so there is no separate ADR directory for
this feature.

## Tests

Database tests run against an in-memory SQLite database. Network tests run
against recorded fixtures in `fixtures/`, captured from the live endpoints and
chosen to cover the structural edge cases the real data contains — untranslated
cards, cards with several artworks, every ban status, and the duplicate format
entries upstream publishes for a handful of cards. No test contacts a live host.
