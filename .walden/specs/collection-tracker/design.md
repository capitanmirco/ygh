---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-20T10:38:13Z
last_modified: 2026-09-20T10:38:13Z
approved_fingerprint: sha256:e61e3e7943ba8e1d773c0a91236e8ad8f42160ba421a603a544f2bf5d5a0631b
source_requirements_approved_at: 2026-09-20T10:35:09Z
source_requirements_fingerprint: sha256:6c524234a6b8ec40e469976a4a3b2a078b8b8b0cbf16b5e5e8286a31c860aa25
---

# Feature Design

## Architecture

The collection lives in the same database as the catalog and the decks, so a recorded copy holds a real foreign key to the printing it is a copy of, and answering what a deck needs is one query rather than a join across two stores.

### Module graph

```
App ─▶ YGOFeatureCollection ─┐
                             ├─▶ YGOCore   (entry types, shortfall arithmetic)
YGOPersistence (schema, repo)┘
```

One new feature module. The shortfall calculation is a pure function in `YGOCore` beside the other domain arithmetic, so it is tested without a database and reused by both the collection view and the deck editor.

### An entry is a lot, not a copy

A row records **a group of identical copies acquired together**: one printing, one condition, one location, a count, and what each of them cost.

Recording copies one at a time and recording a purchase of four are the same operation at different counts, and a collector who bought three commons in one go has no interest in three rows. Storing one row per physical card would multiply a ten-thousand-copy collection into ten thousand rows for no question anyone asks of it.

The price is **per copy**, so `R2.AC6` sums `price × quantity` and a lot bought at a different price is simply a different lot. Adding a copy without stating a price increments the matching unpriced lot; recording a purchase always creates its own.

<!-- assumed: purchase price is per copy rather than per lot (source: R2.AC6 requires a collection total, which is only well defined if the two can be multiplied) -->

### The shortfall counts cards, not limit names

Deck validation groups copies by limit name, because `Harpie Lady 1`, `2` and `3` share one allowance. **The shortfall must not.** Owning three copies of `Harpie Lady 2` does not let anyone play a deck that lists `Harpie Lady 1`: those are different pieces of cardboard.

So the two counts serve different questions and are deliberately computed differently: the deck builder asks *how many copies of this limit does the deck hold*, and the collection asks *how many copies of this card do I physically have*. What `NFR4` requires them to agree on is the part that is genuinely shared — that copies are summed across every section of a deck and across every printing in a collection.

## Data Model

Migration `v004_collection`, appended to the existing chain.

```sql
storage_location(id INTEGER PRIMARY KEY, name TEXT NOT NULL, notes TEXT)

collection_entry(
    id INTEGER PRIMARY KEY,
    card_id INTEGER NOT NULL REFERENCES card(id),
    -- Null for the 552 cards the catalog lists no printing for, thirty of
    -- which are legal in TCG and would otherwise be unrecordable.
    print_id INTEGER REFERENCES card_print(id),
    condition TEXT NOT NULL
        CHECK(condition IN ('near_mint','lightly_played','moderately_played',
                            'heavily_played','damaged')),
    quantity INTEGER NOT NULL CHECK(quantity > 0),
    -- Per copy, so a collection total is quantity × price. Null means the
    -- price is unrecorded, which is not the same as free.
    purchase_price REAL,
    acquired_at TEXT,
    -- Null means unfiled. A deleted location releases its copies rather than
    -- taking them with it.
    location_id INTEGER REFERENCES storage_location(id) ON DELETE SET NULL,
    notes TEXT
)

CREATE INDEX collection_entry_card_idx ON collection_entry(card_id)
CREATE INDEX collection_entry_print_idx ON collection_entry(print_id)
CREATE INDEX collection_entry_location_idx ON collection_entry(location_id)
```

Three choices carry weight:

- **`print_id` is nullable.** 552 cards have no printing in the catalog. Forcing one would make thirty TCG-legal cards impossible to own, so a copy may be recorded against its card alone (`R1.AC4`).
- **No unique constraint on the lot's shape.** Two lots of the same printing and condition bought at different prices are two facts, not a conflict. Merging them would have to discard one of the prices. Finding the lot to increment is therefore a query, not a key.
- **`ON DELETE SET NULL` on the location.** `R3.AC3` requires a deleted binder to release its copies, and the database is the right place for a guarantee about irreplaceable data rather than code that must remember.

Rarity and set are not copied into the entry: they belong to `card_print`, which the entry references. Storing them again would let the two drift when a catalog update corrects a rarity.

## Options Considered

1. **A lot per row, rather than a row per physical card.** One row per card would let every copy carry its own price and history. It would also turn a ten-thousand-copy collection into ten thousand rows to answer questions that are all aggregates, and would make "I own three of these" a three-step entry. The lot keeps the aggregate cheap and still separates copies that genuinely differ, which `R2.AC5` requires only for condition.
2. **Rarity by reference, not by copy.** Denormalising set and rarity onto the entry would make filtering one table instead of two. It would also freeze a value the catalog owns: upstream corrects rarities, and a collection that had copied them would quietly disagree with the card it points at.
3. **Shortfall counted per card, not per limit name.** Reusing the deck validator's tally would have been less code and would have been wrong: it would report a deck as buildable when the user owns three of a different card that merely shares an allowance.
4. **CSV for the backup, not the application's own format.** A backup nobody can open is a backup nobody checks. CSV opens in any spreadsheet, so the user can see that their collection is really in there, which is the only property that matters for data that exists nowhere else. The cost is quoting rules, which are tested.
5. **Copies recorded against printings, not against cards alone.** Recording only "three of this card" would be simpler to enter and would lose which printing was owned, which is the point of tracking a collection rather than a checklist.

## Simplicity And Elegance Review

What keeps this small:

- The shortfall is one pure function over two dictionaries. It has no database, no protocol and no cache, and the deck editor and the collection view call the same one.
- Locations are a table and a nullable column. There is no hierarchy, no folder tree and no move operation beyond setting that column.
- The export is the same rows the table holds, in the same order, with one header line. Import is that read backwards. There is no schema version inside the file, because the file is not a migration path — it is a copy of what is on screen.
- Condition is a closed enumeration checked by the database, so an unknown grade cannot be stored by any path.

Challenged once: the shortfall could live in the deck builder, since that is where a duelist asks the question. Rejected because the collection view asks it too, and because a pure function in `YGOCore` is reachable from both without either feature depending on the other.

## Failure Modes And Tradeoffs

| Failure | Containment |
| --- | --- |
| A printing is recorded that the catalog does not hold | The foreign key refuses it and nothing is stored (`R1.AC6`) |
| A catalog update removes a printing a copy points at | Catalog updates upsert rather than delete, so a referenced printing is not withdrawn behind the user's back |
| A location is deleted while holding copies | The copies survive and become unfiled (`R3.AC3`) |
| A backup file is truncated or corrupt | Parsing completes before anything is written, so the existing collection is untouched (`R6.AC3`) |
| A backup names a printing that no longer exists | The rest imports and that row is reported unresolved (`R6.AC4`), rather than the import failing whole |
| A price is absent | Stored as absent, not as zero, and excluded from totals rather than dragging them down (`R2.AC3`) |
| Two lots of the same printing and condition | Kept as two, because they record two purchases |

Accepted tradeoffs:

- **A lot's copies share a price and a date.** A collector who wants per-copy provenance records separate lots. This is the trade for not storing ten thousand rows.
- **Condition is per lot, so upgrading one copy's grade means splitting the lot.** That is the same operation as recording a lot, so no new machinery, but it is a manual step.
- **The collection cannot describe which region a copy is from.** The catalog publishes only English printings and the user has chosen not to track language (`C2`). A copy identifies a set and a rarity, not a country.
- **Total spend is only as complete as what was entered.** Most collections are partly inherited or traded, so the figure is a sum of what is recorded and must be presented as that rather than as a valuation.

## Verification Plan

Tests live in a test target per module. The shortfall is tested as arithmetic with no database. Repository tests run against an in-memory database seeded from the recorded fixtures. Deck fixtures are the user's own files, as in the deck builder.

| Check | Observation that decides it |
| --- | --- |
| Recording copies | Recording one printing three times reports three copies of it and none of any other |
| Removing copies | Removing the last copy leaves no entry; removing from a printing not held changes nothing |
| Setting a count | Setting four where one was held reports four; setting zero removes the entry |
| Cards without printings | A card the catalog lists no printing for is recorded and counts towards that card's total |
| Copies across printings | Two copies of one printing and one of another report three copies of that card |
| Unknown printing | An identifier the catalog does not hold leaves the stored count unchanged and is refused |
| Condition grades | A copy recorded Lightly Played reports that grade, and the five market grades are the ones offered |
| Price and date | Both survive a restart; a copy recorded with neither reports no price rather than zero |
| Editing a copy | Each field edited in turn reports its new value and leaves the others alone |
| Conditions as separate lots | Two Near Mint and one Damaged report three copies and three distinguishable entries |
| Total spend | The sum is quantity × price across priced lots, and unpriced lots contribute nothing |
| Locations | A named location is retrievable; a copy assigned to it lists under it and not among unfiled copies |
| Deleting a location | Five copies survive a deleted binder and report as unfiled |
| Card whereabouts | A card in two binders reports both with their counts |
| Collection totals | Three copies of one card and one of another report two distinct cards and four copies |
| Collection search | A search naming an owned card returns it; naming an unowned one returns nothing though the catalog holds it |
| Collection filters | One rarity returns only that rarity; combined with a condition returns only copies satisfying both |
| Counts per rarity | The per-rarity figures sum to the collection's total copies |
| Empty states | An empty collection and a filter matching nothing are distinguishable |
| Deck shortfall | A deck asking three of a card owned once reports two needed |
| Shortfall across printings | A deck asking two is satisfied by one copy each of two printings |
| Nothing missing | A deck built from owned cards reports an empty shortfall |
| Shortfall across sections | A card owned once and asked once in main and once in side reports one needed |
| Unowned card | A deck asking three of an unowned card reports three, not two |
| Shortfall is read-only | Deck slots and collection entries are unchanged after the report |
| Shortfall counts cards, not limits | A deck listing `Harpie Lady 1` is not satisfied by owning `Harpie Lady 2`, though the two share a deck allowance |
| Export contents | One row per entry, and every stored field present |
| Backup round trip | Export, clear, import yields the same entries with the same counts and details |
| Malformed backup | A truncated file leaves the stored entries unchanged |
| Unresolved printing on import | A file with one unknown printing restores the rest and names it |
| Edit latency | Recording a copy in a ten-thousand-copy collection updates totals within 50 ms |
| Offline | Every behaviour answers with no network available |
| Accessibility | Each shortfall entry reads as a sentence naming the card and the number needed; list, filters and report are keyboard reachable |
| Concurrency | The new module builds under Swift 6 strict concurrency with no data-race diagnostics |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `collection_entry` with a nullable `print_id` and `SQLiteCollectionRepository`; the recording, removal, count-setting, no-printing, across-printings and unknown-printing checks |
| `R2` | The lot's condition, price-per-copy, date and notes columns; the grade, price-and-date, editing, separate-lot and total-spend checks |
| `R3` | `storage_location` with `ON DELETE SET NULL`; the location, deletion and whereabouts checks |
| `R4` | Aggregate queries over `collection_entry` joined to `card` and `card_print`; the totals, search, filter, per-rarity and empty-state checks |
| `R5` | `ShortfallCalculator` in `YGOCore` as a pure function; the six shortfall checks including the limit-name one |
| `R6` | A CSV writer and reader over the same rows; the export, round-trip, malformed and unresolved checks |
| `NFR1` | Indexes on `card_id`, `print_id` and `location_id`; measured latency against a ten-thousand-copy collection |
| `NFR2` | Confirmation before removal, `ON DELETE SET NULL` on locations, parse-before-write on import; the deletion and malformed-backup checks |
| `NFR3` | Every query resolved from stored data; the offline variants of the search and shortfall checks |
| `NFR4` | One shared rule for summing across sections and printings, with the limit-name difference asserted explicitly |
| `NFR5` | Shortfall entries carrying card name and number needed; the accessibility check |
| `NFR6` | Value types and a pure calculator; the strict-concurrency build check |
