# Project Constitution

This file captures stable project-wide context that applies across all features. It is optional and does not participate in the approval workflow.

## Project Summary

YGODeckManager is a native macOS application for managing a personal Yu-Gi-Oh! collection and deck portfolio. It serves a single local user (no accounts, no server, no multi-device sync). Core value: an offline-first, fast local catalog of the full card pool that lets the user build and validate decks per format, track which physical cards they actually own, analyse deck consistency, and import/export decks in the community-standard interchange formats.

## Tech Stack

- **Language:** Swift 6.4 (strict concurrency enabled).
- **UI:** SwiftUI, targeting macOS 27 (arm64). AppKit interop only where SwiftUI lacks a capability.
- **State:** Observation framework (`@Observable`). No Combine unless a specific API forces it.
- **Persistence:** GRDB.swift over SQLite, including FTS5 for full-text card search. Not SwiftData.
- **Build:** Swift Package Manager modular monorepo. A thin app target acts as composition root; all logic lives in local packages under `Packages/`.
- **Tooling:** Xcode (being installed), `swift build`/`swift test` from the command line, SwiftLint.
- **External data:** YGOPRODeck public API v7 (`https://db.ygoprodeck.com/api/v7/`). No API key, no authentication.

## Conventions

- **Module layout:** `App/` (composition root), `Packages/YGO<Name>/` per module, `Packages/Features/YGOFeature<Name>/` per user-facing feature, `docs/adr/` for decision records, `fixtures/` for test data.
- **Dependency direction:** `YGOCore` holds domain types and repository protocols and depends on nothing. Every other module may depend on `YGOCore`; feature modules never depend on `YGOPersistence` or `YGONetworking` concretely, only on protocols injected from the composition root.
- **Naming:** types `UpperCamelCase`, members `lowerCamelCase`, SQL tables and columns `snake_case`, migration identifiers `vNNN_description`.
- **Tests:** swift-testing where available, XCTest otherwise; one test target per package; SQLite tests run against an in-memory database; network clients are tested against recorded JSON fixtures, never live endpoints.
- **Git:** trunk-based on `main`, Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`).

## Sanity Checks

```bash
swift build
swift test
swiftlint lint --strict
```

## Key Files

- `Package.swift` — module graph and dependency wiring.
- `App/YGODeckManagerApp.swift` — composition root; where protocols are bound to implementations.
- `Packages/YGOCore/Sources/YGOCore/` — domain model and repository protocols; read this first.
- `Packages/YGOPersistence/Sources/YGOPersistence/Migrations/` — authoritative database schema history.
- `.walden/constitution.md`, `docs/adr/` — project rules and recorded decisions.
- `fixtures/*.ydk` — real deck files used as golden import tests.

## Hard Rules

1. **No image hotlinking.** YGOPRODeck forbids serving images directly from their host and blacklists offending IPs. Every card image is downloaded once and cached on local disk under the app's Application Support directory. No view may reference a remote image URL at render time.
2. **API rate limit.** YGOPRODeck allows 20 requests per second and bans the client for one hour on violation. All outbound requests pass through a single rate-limiting actor configured below that ceiling.
3. **Offline-first.** Every feature except catalog synchronisation must work with no network connection. Network failure degrades functionality, never blocks the app.
4. **No silent data loss.** Deck and collection data is user-authored and irreplaceable. Destructive operations require confirmation, and schema migrations back up the database file before running.
5. **Card data is third-party.** All card text, names and images are copyright Konami Digital Entertainment. The app stores them for personal local use only; it must not offer bulk redistribution or publication of the catalog.
6. **Single local user.** No authentication, no network listener, no telemetry, no outbound traffic other than to the YGOPRODeck API and image host.
7. **Strict concurrency.** Swift 6 concurrency checking stays on. Network and disk I/O is confined to actors; UI state mutation happens on the main actor.
