import GRDB

/// The authoritative schema history for the catalog database.
///
/// Migrations are append-only: an identifier that has shipped is never edited,
/// because the applied set recorded in the database is what decides which ones
/// still need to run.
public enum CatalogSchema {
    /// Every migration identifier this build knows about, in order.
    public static let migrationIdentifiers = [
        "v001_initial_catalog",
        "v002_card_limit_names",
        "v003_decks",
        "v004_collection",
    ]

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v001_initial_catalog") { db in
            try createCardTables(db)
            try createFullTextIndex(db)
            try createClassificationTables(db)
            try createPrintingAndPriceTables(db)
            try createArtworkCacheTable(db)
            try createSyncStateTable(db)
            try createFilterIndexes(db)
        }

        migrator.registerMigration("v002_card_limit_names") { db in
            try addCardLimitNames(db)
        }

        migrator.registerMigration("v003_decks") { db in
            try createDeckTables(db)
        }

        migrator.registerMigration("v004_collection") { db in
            try createCollectionTables(db)
        }

        return migrator
    }

    // MARK: - Collection

    /// What the user physically owns, beside the catalog that describes it.
    private static func createCollectionTables(_ db: Database) throws {
        try db.create(table: "storage_location") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("notes", .text)
        }

        // A row is a lot: identical copies acquired together. One row per
        // physical card would turn a ten-thousand-copy collection into ten
        // thousand rows to answer questions that are all aggregates.
        try db.create(table: "collection_entry") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("card_id", .integer).notNull().references("card")
            // Null for the 552 cards the catalog lists no printing for, thirty
            // of them legal in TCG and otherwise impossible to own.
            t.column("print_id", .integer).references("card_print")
            t.column("condition", .text).notNull()
                .check { ["near_mint", "lightly_played", "moderately_played",
                          "heavily_played", "damaged"].contains($0) }
            t.column("quantity", .integer).notNull().check { $0 > 0 }
            // Per copy. Null means unrecorded, which is not free.
            t.column("purchase_price", .double)
            t.column("acquired_at", .text)
            // Null means unfiled. A deleted location releases its copies.
            t.column("location_id", .integer)
                .references("storage_location", onDelete: .setNull)
            t.column("notes", .text)
        }

        try db.create(index: "collection_entry_card_idx", on: "collection_entry",
                      columns: ["card_id"])
        try db.create(index: "collection_entry_print_idx", on: "collection_entry",
                      columns: ["print_id"])
        try db.create(index: "collection_entry_location_idx", on: "collection_entry",
                      columns: ["location_id"])
    }

    // MARK: - Decks

    /// Decks live beside the catalog so that a slot holds a real foreign key to
    /// a card, and so the two can be queried together when reporting why a deck
    /// is illegal.
    private static func createDeckTables(_ db: Database) throws {
        try db.create(table: "folder") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            // A deleted folder releases what it holds rather than taking it
            // with it; the database is the right place for that guarantee.
            t.column("parent_id", .integer).references("folder", onDelete: .setNull)
        }

        try db.create(table: "deck") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("format_code", .text).notNull()
            t.column("folder_id", .integer).references("folder", onDelete: .setNull)
            t.column("notes", .text)
            t.column("created_at", .text).notNull()
            t.column("updated_at", .text).notNull()
        }

        // Keyed by artwork, not by card: a deck may hold two copies of one card
        // under two printings, and an export has to return the printing the
        // user actually holds.
        try db.create(table: "deck_slot") { t in
            t.column("deck_id", .integer).notNull()
                .references("deck", onDelete: .cascade)
            t.column("section", .text).notNull()
                .check { ["main", "extra", "side"].contains($0) }
            t.column("artwork_id", .integer).notNull()
                .references("card_artwork", column: "artwork_id")
            t.column("card_id", .integer).notNull().references("card")
            t.column("quantity", .integer).notNull().check { $0 > 0 }
            t.primaryKey(["deck_id", "section", "artwork_id"])
        }

        // A version is a historical record that must still read correctly after
        // deck_slot gains a column, so it is stored as its own document.
        try db.create(table: "deck_version") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("deck_id", .integer).notNull()
                .references("deck", onDelete: .cascade)
            t.column("label", .text)
            t.column("created_at", .text).notNull()
            t.column("snapshot", .text).notNull()
        }

        try db.create(table: "tag") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull().unique()
        }

        try db.create(table: "deck_tag") { t in
            t.column("deck_id", .integer).notNull()
                .references("deck", onDelete: .cascade)
            t.column("tag_id", .integer).notNull()
                .references("tag", onDelete: .cascade)
            t.primaryKey(["deck_id", "tag_id"])
        }

        try db.create(index: "deck_slot_card_idx", on: "deck_slot", columns: ["card_id"])
        try db.create(index: "deck_folder_idx", on: "deck", columns: ["folder_id"])
        try db.create(index: "deck_version_deck_idx", on: "deck_version", columns: ["deck_id"])
        try db.create(index: "deck_name_idx", on: "deck", columns: ["name"])
    }

    // MARK: - Limit names

    /// The name a card's copies are counted against.
    ///
    /// Most cards count against their own name, but a few count against
    /// another card's: `Harpie Lady 1`, `2` and `3` share one limit, and
    /// `Fusion Substitute` counts as `Polymerization`. Grouping on one stored
    /// column keeps that out of the rules entirely.
    ///
    /// Existing rows are backfilled with the card's own name, which is correct
    /// for all but a handful. The next catalog write replaces every card and
    /// corrects those, so the window in which a shared limit reads as its own
    /// is one synchronisation long.
    private static func addCardLimitNames(_ db: Database) throws {
        try db.alter(table: "card") { t in
            t.add(column: "limit_name", .text)
        }
        try db.execute(sql: "UPDATE card SET limit_name = name_en WHERE limit_name IS NULL")
        try db.create(index: "card_limit_name_idx", on: "card", columns: ["limit_name"])
    }

    // MARK: - Cards

    private static func createCardTables(_ db: Database) throws {
        // `id` must be an INTEGER PRIMARY KEY so that it aliases the rowid; the
        // full-text index below joins to the card table on exactly that rowid.
        try db.create(table: "card") { t in
            t.primaryKey("id", .integer)
            t.column("name_en", .text).notNull()
            t.column("desc_en", .text).notNull()
            t.column("name_it", .text)
            t.column("desc_it", .text)
            t.column("type", .text).notNull()
            t.column("frame_type", .text).notNull()
            t.column("human_readable_type", .text).notNull()
            t.column("race", .text)
            t.column("attribute", .text)
            t.column("level", .integer)
            t.column("atk", .integer)
            t.column("def", .integer)
            t.column("link_value", .integer)
            t.column("link_markers", .text)
            t.column("pendulum_scale", .integer)
            t.column("archetype", .text)
            t.column("has_effect", .boolean).notNull().defaults(to: false)
            t.column("tcg_date", .text)
            t.column("ocg_date", .text)
            t.column("konami_id", .integer)
            t.column("md_rarity", .text)
        }

        // One row per printed artwork. Deck files reference these identifiers,
        // not card identifiers, so this table is what makes an import resolve.
        try db.create(table: "card_artwork") { t in
            t.primaryKey("artwork_id", .integer)
            t.column("card_id", .integer)
                .notNull()
                .references("card", onDelete: .cascade)
            t.column("ordinal", .integer).notNull()
        }
    }

    // MARK: - Full-text index

    private static func createFullTextIndex(_ db: Database) throws {
        try db.create(virtualTable: "card_fts", using: FTS5()) { t in
            // External content: the text lives in `card` only, and GRDB
            // installs the triggers that keep the index in step with it.
            t.synchronize(withTable: "card")
            t.column("name_en")
            t.column("desc_en")
            t.column("name_it")
            t.column("desc_it")
            // `remove_diacritics 2` is what lets "avidita" match "Avidità";
            // level 1 does not fold every sequence Italian card names use.
            t.tokenizer = FTS5TokenizerDescriptor(
                components: ["unicode61", "remove_diacritics", "2"])
        }
    }

    // MARK: - Formats and restrictions

    private static func createClassificationTables(_ db: Database) throws {
        try db.create(table: "card_format") { t in
            t.column("card_id", .integer)
                .notNull()
                .references("card", onDelete: .cascade)
            t.column("format_code", .text).notNull()
            t.primaryKey(["card_id", "format_code"])
        }

        // `source` is what lets an update replace upstream restrictions while
        // leaving the user's Edison and Master Duel entries untouched.
        try db.create(table: "ban_status") { t in
            t.column("card_id", .integer)
                .notNull()
                .references("card", onDelete: .cascade)
            t.column("format_code", .text).notNull()
            t.column("status", .text).notNull()
                .check { ["forbidden", "limited", "semi_limited"].contains($0) }
            t.column("source", .text).notNull()
                .check { ["upstream", "user"].contains($0) }
            t.primaryKey(["card_id", "format_code"])
        }
    }

    // MARK: - Printings and prices

    private static func createPrintingAndPriceTables(_ db: Database) throws {
        try db.create(table: "card_print") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("card_id", .integer)
                .notNull()
                .references("card", onDelete: .cascade)
            t.column("set_code", .text).notNull()
            t.column("set_name", .text).notNull()
            t.column("rarity", .text)
            t.column("rarity_code", .text)
            t.column("set_price", .double)
        }

        // Upstream publishes prices per card, not per printing. Storing them
        // that way keeps the approximation visible rather than implied.
        try db.create(table: "card_price") { t in
            t.column("card_id", .integer)
                .notNull()
                .references("card", onDelete: .cascade)
            t.column("source", .text).notNull()
            t.column("value", .double).notNull()
            t.column("observed_at", .text).notNull()
            t.primaryKey(["card_id", "source"])
        }
    }

    // MARK: - Artwork presence

    private static func createArtworkCacheTable(_ db: Database) throws {
        // Presence lives here so that resuming an interrupted prefetch is an
        // anti-join rather than fourteen thousand filesystem probes.
        try db.create(table: "artwork_cache") { t in
            t.column("artwork_id", .integer).notNull()
            t.column("variant", .text).notNull()
                .check { ["thumb", "full"].contains($0) }
            t.column("byte_size", .integer).notNull()
            t.column("stored_at", .text).notNull()
            t.primaryKey(["artwork_id", "variant"])
        }
    }

    // MARK: - Sync state

    private static func createSyncStateTable(_ db: Database) throws {
        try db.create(table: "sync_state") { t in
            t.primaryKey("id", .integer).check { $0 == 1 }
            t.column("catalog_version", .text)
            t.column("upstream_updated_at", .text)
            t.column("last_sync_at", .text)
        }
    }

    // MARK: - Indexes

    private static func createFilterIndexes(_ db: Database) throws {
        try db.create(index: "card_frame_type_idx", on: "card", columns: ["frame_type"])
        try db.create(index: "card_type_idx", on: "card", columns: ["type"])
        try db.create(index: "card_attribute_idx", on: "card", columns: ["attribute"])
        try db.create(index: "card_race_idx", on: "card", columns: ["race"])
        try db.create(index: "card_level_idx", on: "card", columns: ["level"])
        try db.create(index: "card_atk_idx", on: "card", columns: ["atk"])
        try db.create(index: "card_def_idx", on: "card", columns: ["def"])
        try db.create(index: "card_link_value_idx", on: "card", columns: ["link_value"])
        try db.create(index: "card_pendulum_scale_idx", on: "card", columns: ["pendulum_scale"])
        try db.create(index: "card_archetype_idx", on: "card", columns: ["archetype"])
        try db.create(index: "card_artwork_card_id_idx", on: "card_artwork", columns: ["card_id"])
        try db.create(index: "card_format_code_idx", on: "card_format", columns: ["format_code"])
        try db.create(index: "ban_status_format_source_idx", on: "ban_status", columns: ["format_code", "source"])
        try db.create(index: "card_print_card_id_idx", on: "card_print", columns: ["card_id"])
    }
}
