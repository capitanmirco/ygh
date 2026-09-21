---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T18:55:04Z
last_modified: 2026-09-21T18:55:04Z
approved_fingerprint: sha256:fa69d709d91d22a8e941b371884200a107346ca08e6d8dc3e48faa877bc03ea2
source_requirements_approved_at: 2026-09-21T18:55:04Z
source_requirements_fingerprint: sha256:1291899a09eac46d2fae4c19d2993f54d7be27e369f7633f0dd70f56fe88a3a8
---

# Feature Design

## Architecture

Almost everything this feature needs already exists and is certified. What is missing is a caller and a screen.

```
DeckLibraryViewModel ──▶ YGOCore (DeckBuilding, DeckLibraryWriting)
        │                         ▲
        │                         │
        └──▶ DeckExporter         SQLiteDeckRepository
             (YGODeckIO)
```

Measured before designing anything: `createDeck(name:format:)`, `rename(_:to:)`, `duplicate(_:named:)`, `changeFormat(_:to:)` and `delete(_:confirmed:)` are all implemented in `SQLiteDeckRepository`, and `DeckExporter` has `ydkText`, `ydkeLink` and `write(_:to:)`. Between them they cover every acceptance criterion in `R1`, `R2` and `R3`. None has a caller outside its own tests.

So this feature writes a view model, a screen, and one port.

### One new port, because two operations have none

`DeckBuilding` covers creating, adding, removing, changing format and deleting. `rename` and `duplicate` exist on the concrete repository and appear in no protocol, so nothing that depends on `YGOCore` can reach them.

`DeckLibraryWriting` declares those two. A separate port rather than two more methods on `DeckBuilding`, for the reason that has held three times now: every stub in a certified specification's offline proofs conforms to that protocol.

<!-- assumed: a new DeckLibraryWriting port rather than widening DeckBuilding (source: the same decision taken for CardSearchCounting, DeckEditing and CardDetailReading, each for the same reason) -->

### Duplication is a transaction, not a replay

`duplicate(_:named:)` already copies a deck's slots in one write. The alternative — create a deck, then add each card — would be N writes, would leave a half-built deck if one failed, and would produce a deck whose slots were added rather than copied, which is a different thing when a card holds a particular artwork.

### Export writes artworks, and that is the point

`DeckExporter.list` reads each slot's `artwork`, not its `card`. A deck that has been through this application comes out holding the printings the user put in it.

`R2.AC2` exists to keep that true, because the tempting simplification — export a card's primary artwork — would quietly rewrite someone's choice of printing, and would do it silently on every export.

### The round trip is the proof that matters

`R2.AC6` is the only check that tests export and import against each other rather than against an expectation. A format is a contract with other programs, and the cheapest way to be wrong about it is to write a file only this application can read.

So the check exports a real deck, imports the result through `DeckImporter`, and compares sections, cards and counts. It deliberately does not compare names: a `.ydk` carries passcodes and sections and nothing else, so the name comes from the file (`C4`).

### Creating opens the deck

`R1.AC1` requires the new deck to be open for editing, not merely listed. A deck created and left in a sidebar is a deck the user has to find again, and the reason to create one is to start putting cards in it.

## Data Model

No schema change. One port in `YGOCore`:

```swift
public protocol DeckLibraryWriting: Sendable {
    func rename(_ deckID: Int64, to name: String) async throws
    @discardableResult
    func duplicate(_ deckID: Int64, named name: String) async throws -> Deck
}
```

And a view model in `YGOFeatureDeckBuilder`:

```swift
@MainActor @Observable
public final class DeckLibraryViewModel {
    public private(set) var decks: [Deck]
    public private(set) var lastFailure: String?
    public private(set) var pendingDeletion: Int64?

    public func createDeck(named: String, format: CardFormat) async -> Deck?
    public func rename(_ deckID: Int64, to name: String) async
    public func duplicate(_ deckID: Int64) async -> Deck?
    public func changeFormat(_ deckID: Int64, to format: CardFormat) async
    public func requestDeletion(_ deckID: Int64)
    public func confirmDeletion() async -> Bool

    public func ydkText(for deckID: Int64) async -> String?
    public func export(_ deckID: Int64, to url: URL) async -> Bool
    public func ydkeLink(for deckID: Int64) async -> String?
}
```

Every write reloads the list from storage afterwards and reports its failure, which is the shape `deck-editing` settled: what is shown is what is stored, by construction rather than by care.

### Names

`R1.AC3` gives an unnamed deck a name rather than storing an empty one. The default is *Nuovo mazzo*, and a duplicate is the original's name followed by *(copia)* — both are the application's words, not the user's, so they are the application's to choose.

`R1.AC4` requires two decks of one name to coexist, which they already do: a deck is identified by its row, not by its name.

## Options Considered

1. **Calling the existing operations over reimplementing them.** Five of the six writes are certified already. Writing them again would be writing a second way to create a deck.
2. **A new port over widening `DeckBuilding`.** Widening breaks every stub in `deck-builder`'s offline proofs for two methods they do not use.
3. **The repository's `duplicate` over create-then-add.** One transaction against N writes, and a copy rather than a rebuild.
4. **A library view model over putting this in the app's sidebar.** The sidebar is a view; a view that creates and deletes decks holds policy and can only be checked by rendering.
5. **Opening a new deck over listing it.** A deck created and left in a list is one the user has to find again.
6. **Comparing cards and counts on the round trip, not names.** A `.ydk` has no name to compare, and asserting one would be asserting something the format does not carry.

## Simplicity And Elegance Review

What keeps this small:

- Six writes, five of which already exist and are proven.
- Export is three existing functions and a file dialog.
- The failure-and-reload shape is `deck-editing`'s, applied again rather than invented again.
- The round trip is one test that replaces a dozen assertions about file syntax.

Challenged once: the library could have lived in the app target beside the sidebar it feeds. Rejected because it would then be provable only by rendering, and because `deck-authoring`'s behaviour is exactly the kind that needs proving — a delete that deletes the wrong deck is not a rendering bug.

## Failure Modes And Tradeoffs

| Failure | Containment |
| --- | --- |
| A write fails | Reported, and the list reloaded from storage (`R1.AC5`, `NFR3`) |
| A deck is created with no name | Named *Nuovo mazzo* rather than stored blank (`R1.AC3`) |
| Two decks share a name | Both kept; a deck is its row, not its name (`R1.AC4`) |
| The export destination is unwritable | Reported, and no partial file left (`R2.AC5`) |
| An illegal deck is exported | Exported, because that is what carrying a deck between machines means (`R2.AC3`, `C3`) |
| A duplicated deck's slots are rebuilt rather than copied | The repository's transaction copies them, artworks included |
| A deck is deleted by accident | Confirmed first, and the deletion is irreversible (`R3.AC3`, `C5`) |
| A round trip loses the name | Expected: a `.ydk` carries no name (`C4`) |

Accepted tradeoffs:

- **A round trip does not preserve the deck's name or format.** The format `.ydk` does not carry them. The import names the deck after the file, which is what every other program does too.
- **Export does not warn about an illegal deck.** `deck-builder` decided that, and warning here would make the editor argue with the exporter.
- **Folders and tags stay uncalled.** They are in storage and out of scope; this feature does not make them harder to reach later.
- **`(copia)` is Italian in a type otherwise free of language.** The application has one language, and a default name is a label rather than data.

## Verification Plan

Proven against an in-memory database seeded from the user's own decks, and against a repository that refuses writes. The round trip goes through the real importer and exporter, never a hand-written file.

| Check | Observation that decides it |
| --- | --- |
| Creating stores and opens | A created deck is in the list and is the one the editor loads |
| The format is recorded | A deck created for GOAT judges by GOAT's rules |
| An unnamed deck | Creating with an empty name yields a deck named *Nuovo mazzo* |
| Two decks, one name | Both exist and open independently |
| A refused creation | Nothing is added and the failure is stated |
| Export writes cards | The file lists each passcode once per copy, under its section |
| Export writes artworks | A deck holding a particular artwork exports that artwork's passcode |
| Illegal decks export | A ten-card deck and a four-copy deck both export |
| A link | The `ydke://` link decodes to the same cards in the same sections |
| A refused write | The failure is stated and no partial file remains |
| Round trip | Export then import yields the same sections, cards and counts |
| Renaming | The new name is stored and shown |
| Duplicating | The copy holds the same cards; editing it leaves the original alone |
| Deleting | Without confirmation the deck stays; with it, it is gone |
| Changing format | The deck is re-judged against the new format |
| Latency | Creating, duplicating and exporting a seventy-card deck stay under 200 ms |
| Offline | Every operation completes with no network |
| Accessibility | Each operation is keyboard reachable and reads as a sentence |
| Concurrency | The feature builds under Swift 6 strict concurrency with no diagnostics |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `DeckLibraryViewModel.createDeck` over `DeckBuilding`, with the default name and the failure-and-reload shape; the first five checks |
| `R2` | `DeckExporter`'s three entry points behind `ydkText`, `export(_:to:)` and `ydkeLink`; the six export checks including the round trip |
| `R3` | `DeckLibraryWriting.rename` and `.duplicate`, and `DeckBuilding`'s `changeFormat` and `delete`; the four management checks |
| `NFR1` | One transaction per operation; measured latency on a seventy-card deck |
| `NFR2` | Every write completes before the list is reloaded and reported |
| `NFR3` | Failures caught and stated, and the list reloaded from storage |
| `NFR4` | Local SQL and a local file; the offline check |
| `NFR5` | Keyboard-reachable operations and sentence-forming labels |
| `NFR6` | Value types and an actor-isolated view model; the strict-concurrency build check |
