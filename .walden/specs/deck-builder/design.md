---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-20T09:14:18Z
last_modified: 2026-09-20T09:14:18Z
approved_fingerprint: sha256:055d45a896ab7f72ab67ac84d8b8b2c2eae42984496ab790a25b6921fc686f9c
source_requirements_approved_at: 2026-09-20T09:09:40Z
source_requirements_fingerprint: sha256:801af3e91ff433fa491f1de8bd881dbea0ecd0e536bd4574d67890af90fe7bf7
---

# Feature Design

## Architecture

Decks live in the same database as the catalog, so a deck slot holds a real foreign key to a card and the two can be queried together. Validation is a pure function over a small snapshot, which is what keeps an edit inside the 50 ms budget without caching anything.

### Module graph

```
App ─▶ YGOFeatureDeckBuilder ─┐
                              ├─▶ YGOCore      (deck types, violations, protocols)
YGODeckIO   (.ydk, YDKe) ─────┤
YGOValidation (rules) ────────┤
YGOPersistence (schema, repo) ┘
```

Three modules are new: `YGODeckIO` for the interchange formats, `YGOValidation` for the rules, and `YGOFeatureDeckBuilder` for the interface. `YGOValidation` and `YGODeckIO` depend on `YGOCore` alone — neither touches SQLite, a network, or a view — so the rules that decide whether a deck is legal are testable as plain functions.

### Validation as a pure function

```
DeckValidator.violations(in: Deck, using: DeckCardIndex) -> [DeckViolation]
```

`DeckCardIndex` is a snapshot of just the cards a deck holds: at most ninety entries, each carrying the frame, the limit name, the format memberships and the ban status for the deck's format. The repository builds it in one query when the deck is opened and refreshes the single card that changed on an edit.

Validation itself performs no I/O and no lookups beyond that dictionary. That is what makes `NFR1` a matter of arithmetic over ninety entries rather than a database round trip per card, and it is why every rule in `R2`, `R3` and `R4` can be exercised without a database at all.

<!-- assumed: violations are recomputed on every edit rather than maintained incrementally (source: R4.AC4 requires the complete set every time, and ninety entries make an incremental cache more code for no measurable gain) -->

### Dependency on the catalog

`R3.AC3` needs each card's limit name, which the upstream `treated_as` field carries and the catalog does not currently store. This feature adds migration `v002` introducing `card.limit_name` and extends `CatalogWriter` to populate it.

That change is additive: it stores a field that was previously discarded and alters no behaviour the `card-catalog` specification approved. Its evidence still goes stale, so that specification is re-verified as part of this work rather than left claiming a code identity it no longer has.

## Data Model

Migration `v002_decks`, appended to the existing chain.

```sql
folder(id INTEGER PRIMARY KEY, name TEXT NOT NULL, parent_id REFERENCES folder(id) ON DELETE SET NULL)

deck(id INTEGER PRIMARY KEY, name TEXT NOT NULL, format_code TEXT NOT NULL,
     folder_id REFERENCES folder(id) ON DELETE SET NULL,
     notes TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)

-- Keyed by artwork, not by card: a deck may hold two copies of one card under
-- two different artworks, and an export has to give back the artwork the user
-- actually holds.
deck_slot(deck_id REFERENCES deck(id) ON DELETE CASCADE,
          section TEXT CHECK(section IN ('main','extra','side')),
          artwork_id INTEGER NOT NULL REFERENCES card_artwork(artwork_id),
          card_id INTEGER NOT NULL REFERENCES card(id),
          quantity INTEGER NOT NULL CHECK(quantity > 0),
          PRIMARY KEY(deck_id, section, artwork_id))

deck_version(id INTEGER PRIMARY KEY, deck_id REFERENCES deck(id) ON DELETE CASCADE,
             label TEXT, created_at TEXT NOT NULL, snapshot TEXT NOT NULL)

tag(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE)
deck_tag(deck_id REFERENCES deck(id) ON DELETE CASCADE,
         tag_id REFERENCES tag(id) ON DELETE CASCADE,
         PRIMARY KEY(deck_id, tag_id))

-- Added to the existing card table.
ALTER TABLE card ADD COLUMN limit_name TEXT
```

Four choices carry weight:

- **`deck_slot` is keyed by artwork.** Counting copies then means summing across artworks, which is exactly what `R3.AC2` asks for, while `R6.AC3` becomes a straight read rather than a guess about which printing to emit.
- **`card.limit_name`** holds the `treated_as` value when it differs from the card's own name, and the card's name otherwise. Copy counting groups on this one column, so `Harpie Lady 1`, `2` and `3` share a limit without any special case in the validator.
- **`deck_version.snapshot` is JSON**, not rows. A version is a historical record that must still read correctly after `deck_slot` gains a column, and it is written once and read rarely.
- **`folder.parent_id` and `deck.folder_id` are `ON DELETE SET NULL`.** `R7.AC3` requires a deleted folder to release its decks rather than take them with it, and the database is the right place for that guarantee.

## Options Considered

1. **Decks in the catalog database, not a separate file.** A separate deck store would let the catalog be rebuilt without touching irreplaceable lists. It would also forfeit the foreign key from `deck_slot` to `card` and force `ATTACH` for every join that reports a violation. The pre-migration backup from `R8` in `card-catalog` already contains that risk, and this keeps one migration chain rather than two that must agree.
2. **A pure validator over a snapshot, rather than SQL rules.** Expressing the rules as queries would put them next to the data, but each edit would then cost a round trip, the rules would be untestable without a database, and `R4.AC4`'s requirement to report every violation would become a union of several queries. Ninety dictionary entries are faster to walk than to query.
3. **Slots keyed by artwork rather than by card.** Keying by card would be a smaller table and simpler counting, but `R6.AC3` would be impossible: an export could not return the artwork the user holds, and a deck round-tripped through the application would quietly change its printings.
4. **Format proposed by fewest violations, rather than asked for.** Asking the user on every import is honest but useless when they do not yet know which format a downloaded list belongs to. Both of the user's own files score zero in GOAT and four or six in TCG, so the proposal is right where it matters and is presented as a suggestion they can override.
5. **Version snapshots as JSON, rather than copied rows.** Copied rows would allow querying across versions, which nothing in `R8` asks for, and would tie every historical version to the current shape of `deck_slot`.

## Simplicity And Elegance Review

What keeps this small:

- One column, `limit_name`, removes every special case for cards that share a name limit. The validator groups on it and never learns that *Harpie Lady 1* exists.
- Validation is one pure function returning one array. There is no rule engine, no registry and no per-rule protocol; the rules are a sequence of passes over the same snapshot, and `R4.AC4` falls out of appending to one array rather than short-circuiting.
- `.ydk` and YDKe share a decoded form: both parsers produce three arrays of passcodes, and one function turns those into a deck. Import resolution, alias handling and unresolved reporting are written once.
- The database enforces what it can — sections, positive quantities, folder release on delete — so the validator only has to hold rules SQLite cannot express.

Challenged once: the rules could live in the view model, saving a module. Rejected because `YGOValidation` with no dependency on persistence or SwiftUI is what makes every rule in `R2`, `R3` and `R4` testable as arithmetic, and because deck statistics will need the same snapshot later.

## Failure Modes And Tradeoffs

| Failure | Containment |
| --- | --- |
| Imported passcode matches no card | The rest of the deck imports and the passcode is reported unresolved (`R5.AC3`), rather than failing the import or silently shortening the deck |
| Imported file truncated or markers corrupt | Parsing fails before anything is written, so no partial deck is stored (`R5.AC7`) |
| YDKe link cut short in transit | Base64 or length validation rejects it; a section whose byte count is not a multiple of four is malformed by definition |
| A deck's format has no upstream ban list | Judged against user-recorded restrictions and reported as user-maintained (`R4.AC5`, `R4.AC6`), never presented as authoritative |
| Catalog updated while a deck holds a now-withdrawn artwork | The foreign key keeps the slot valid; a card removed upstream is not deleted from the catalog by an update, so decks do not lose cards behind the user's back |
| Version restored by mistake | The replaced state is itself stored as a version first (`R8.AC3`), so a restore is reversible |
| Deck deleted | Requires confirmation (`R1.AC6`); versions cascade with the deck they belong to |

Accepted tradeoffs:

- **Cards that share a name limit but carry no `treated_as` upstream cannot be detected.** The application is as correct as its source on this point, and `C4` says so.
- **Retro format pools come from upstream's format membership and release dates**, not from an independent record of what was legal on a given date. A pool edge case will be wrong in the same way upstream is wrong.
- **The proposed import format can be wrong** when a deck is legal in several formats. It is a suggestion, shown as one, and changing it is one action.
- **Validation is recomputed in full on every edit.** At ninety entries this is cheaper than the bookkeeping an incremental cache would need, and it cannot drift.

## Verification Plan

Tests live in a test target per module. Validation and interchange tests need no database at all. Repository tests run against an in-memory database. The user's own deck files are the golden import fixtures.

**The recorded fixture needs extending first.** `fixtures/catalog-en.json` holds four cards with a `treated_as` value and none whose value differs from its own name, so `R3.AC3` cannot be exercised against it as it stands. The fixture is regenerated to include the genuinely different cases — `Harpie Lady 1`, `2` and `3`, `A Legendary Ocean`, `Fusion Substitute` — taken from the live dataset like the rest of it.

| Check | Observation that decides it |
| --- | --- |
| Deck lifecycle | A created deck is retrievable with the chosen name, format and three empty sections; a duplicate edited afterwards leaves the original's counts unchanged |
| Deletion guard | Deleting without confirmation leaves the deck retrievable; confirming removes it and its versions and leaves the catalog untouched |
| Main size | Thirty-nine, forty, sixty and sixty-one main cards report violation, legal, legal, violation |
| Extra and side size | Fifteen is legal and sixteen is a violation for each; empty is legal for both |
| Section placement | A Fusion, Synchro, Xyz and Link card each report a violation naming them in the main section and none in the extra section; a Spell reports one in the extra section |
| Default section | A Fusion monster added with no section chosen lands in the extra section, a Spell in the main section |
| Copies across sections | Two in main plus two in side reports four copies |
| Copies across artworks | Two under a card's own passcode plus two under an alternate artwork reports four copies of one card |
| Copies across limit names | Two `Harpie Lady 1` plus two `Harpie Lady 2` reports four copies of *Harpie Lady* and a violation; one of each reports two and none |
| Ban allowance | Three copies of a Limited card report three held against one permitted; one copy reports none |
| Absolute limit | Four copies of an unrestricted card report a violation in a format with no ban list |
| Format-specific judgement | The user's own deck files report zero violations with format GOAT and report their known TCG violations with format TCG |
| Pool membership | A card outside a retro format's pool is reported by name when the deck's format is that one |
| Complete reporting | A deck with an undersized main section and two over-copy cards reports three violations |
| User-maintained restrictions | A user-recorded Edison limit produces a violation at two copies and none once cleared, and the report is marked user-maintained |
| `.ydk` import | `LR-Chaos Turbo.ydk` imports to forty main, fifteen extra, fifteen side |
| Alias resolution on import | `Lockdown Burn.ydk` imports to forty main cards including *Ring of Destruction*, whose passcode in that file is an alternate artwork |
| Unresolved passcode | A file holding one unknown passcode among known ones yields the known cards plus a report naming the unknown one |
| Import naming | `Lockdown Burn.ydk` yields a deck named "Lockdown Burn" |
| Format proposal | Importing either of the user's files proposes GOAT |
| Malformed input | A truncated link and a file with a corrupt marker each leave the stored deck count unchanged |
| `.ydk` round trip | An imported deck exported and re-imported is identical section by section |
| YDKe round trip | A link exported from a deck decodes to its passcodes in order and re-imports unchanged; standard base64 with padding, as the published format uses |
| Artwork fidelity on export | A deck holding an alternate artwork exports that artwork's passcode |
| Export of an illegal deck | A thirty-card deck exports and re-imports intact |
| Folders and tags | A deck moved into a folder lists under it and not at the top level; a deck with two tags lists under each; deleting a folder of three decks leaves all three retrievable |
| Deck search | A search naming one deck returns it and not the others |
| Version round trip | A version saved before an edit reports pre-edit counts afterwards; restoring returns exactly those counts and stores the replaced state as a version |
| Version durability | Versions survive unrelated deletions and a restart |
| Edit latency | Measured re-evaluation after an add or remove on a sixty-card deck stays under 50 ms |
| Accessibility | Every reported violation renders as a sentence naming the card and the rule; sections, card list and report are reachable by keyboard alone |
| Concurrency | The new modules build under Swift 6 strict concurrency with no data-race diagnostics |
| Catalog still sound | `card-catalog`'s own proofs pass after `CatalogWriter` gains the limit-name column |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `deck` and `deck_slot` tables with `SQLiteDeckRepository`; deck lifecycle and deletion-guard checks |
| `R2` | `DeckValidator` size and placement passes over `DeckCardIndex`; main, extra, side, placement and default-section checks |
| `R3` | `card.limit_name` plus artwork-keyed slots; the three copy-counting checks and both allowance checks |
| `R4` | `DeckValidator` judging against the deck's own format and the `ban_status` source column; format-specific, pool, complete-reporting and user-maintained checks |
| `R5` | `YDKFileReader` and `YDKeCodec` feeding one shared resolver; import, alias, unresolved, naming, proposal and malformed-input checks |
| `R6` | The same codecs in reverse, reading `deck_slot.artwork_id`; both round-trip checks, artwork fidelity and illegal-deck export |
| `R7` | `folder`, `tag` and `deck_tag` with `ON DELETE SET NULL`; folder, tag, folder-deletion and search checks |
| `R8` | `deck_version` with JSON snapshots; version round trip and durability checks |
| `NFR1` | Pure validation over a ninety-entry snapshot; measured edit latency |
| `NFR2` | Confirmation before deletion, parse-before-write on import, pre-restore versioning; deletion-guard, malformed-input and version round-trip checks |
| `NFR3` | Every rule and query resolved from the stored catalog; the format-specific and import checks run with no network available |
| `NFR4` | Artwork-keyed slots and the shared decoded form; both round-trip checks and artwork fidelity |
| `NFR5` | Violations carrying card name, held count and permitted count; accessibility check |
| `NFR6` | Value types and pure functions in `YGOValidation` and `YGODeckIO`; strict-concurrency build check |
