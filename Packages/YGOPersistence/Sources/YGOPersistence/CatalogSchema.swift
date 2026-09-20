import GRDB

/// The authoritative schema history for the catalog database.
///
/// Migrations are append-only: an identifier that has shipped is never edited,
/// because the applied set recorded in the database is what decides which ones
/// still need to run.
public enum CatalogSchema {
    /// Every migration identifier this build knows about, in order.
    public static let migrationIdentifiers = ["v001_initial_catalog"]

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

        return migrator
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
