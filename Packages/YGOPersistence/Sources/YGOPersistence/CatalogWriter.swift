import Foundation
import GRDB
import YGOCore

/// Writes a decoded upstream dataset into the catalog tables.
///
/// Every method takes a `Database` rather than a pool, so the caller owns the
/// transaction boundary. That is deliberate: seeding an empty catalog and
/// updating a populated one then share one rollback story instead of two, and a
/// failure anywhere leaves the previous contents intact.
///
/// Statements are prepared once and reused across the fourteen and a half
/// thousand cards; re-parsing the SQL per row turns seconds into minutes.
public struct CatalogWriter: Sendable {
    public init() {}

    /// Replaces the catalog's English-language contents with `cards`.
    ///
    /// Rows a card no longer has — a printing withdrawn, a restriction lifted —
    /// are removed, but only for the cards present in this dataset and only for
    /// upstream-sourced restrictions.
    public func writeEnglishDataset(
        _ cards: [CatalogCardPayload],
        observedAt: Date,
        into db: Database,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws {
        let statements = try Statements(db)
        let observedAtText = ISO8601DateFormatter().string(from: observedAt)
        let total = cards.count

        for (index, card) in cards.enumerated() {
            try write(card, observedAtText: observedAtText, using: statements, in: db)
            progress?(index + 1, total)
        }
    }

    // MARK: - One card

    private func write(
        _ card: CatalogCardPayload,
        observedAtText: String,
        using statements: Statements,
        in db: Database
    ) throws {
        try statements.upsertCard.execute(arguments: [
            card.id, card.name, card.desc, card.type, card.frameType,
            card.humanReadableCardType, card.race, card.attribute, card.level,
            card.atk, card.def, card.linkValue,
            card.linkMarkers?.joined(separator: ","), card.pendulumScale,
            card.archetype, Self.limitName(for: card), (card.misc?.hasEffect ?? 0) != 0,
            card.misc?.tcgDate, card.misc?.ocgDate, card.misc?.konamiId,
            card.misc?.mdRarity,
        ])

        try writeArtworks(card, using: statements)
        try writeFormats(card, using: statements)
        try writeBanStatuses(card, using: statements)
        try writePrintings(card, using: statements)
        try writePrices(card, observedAtText: observedAtText, using: statements)
    }

    private func writeArtworks(_ card: CatalogCardPayload, using statements: Statements) throws {
        try statements.deleteArtworks.execute(arguments: [card.id])
        for (ordinal, image) in card.cardImages.enumerated() {
            try statements.insertArtwork.execute(arguments: [image.id, card.id, ordinal])
        }
    }

    private func writeFormats(_ card: CatalogCardPayload, using statements: Statements) throws {
        try statements.deleteFormats.execute(arguments: [card.id])

        // Upstream repeats a format name for a handful of cards - eight of the
        // fourteen and a half thousand, Blue-Eyes White Dragon among them,
        // which lists "Speed Duel" twice - so the names are deduplicated before
        // they reach a table whose primary key forbids the repeat.
        //
        // An unrecognised format name is skipped rather than stored: a new
        // upstream format must not become a filter nothing can interpret.
        var written: Set<CardFormat> = []
        for name in card.misc?.formats ?? [] {
            guard let format = CardFormat(rawValue: name), written.insert(format).inserted
            else { continue }
            try statements.insertFormat.execute(arguments: [card.id, format.rawValue])
        }
    }

    /// Only upstream rows are cleared. The user's Edison and Master Duel
    /// entries are `source = 'user'` and are left exactly where they are.
    private func writeBanStatuses(_ card: CatalogCardPayload, using statements: Statements) throws {
        try statements.deleteUpstreamBans.execute(arguments: [card.id])

        let upstream: [(CardFormat, String?)] = [
            (.tcg, card.banlistInfo?.banTcg),
            (.ocg, card.banlistInfo?.banOcg),
            (.goat, card.banlistInfo?.banGoat),
        ]

        for (format, text) in upstream {
            guard let status = Self.banStatus(fromUpstream: text),
                  let stored = status.storedValue else { continue }
            try statements.insertBan.execute(
                arguments: [card.id, format.rawValue, stored, "upstream"])
        }
    }

    private func writePrintings(_ card: CatalogCardPayload, using statements: Statements) throws {
        try statements.deletePrintings.execute(arguments: [card.id])
        for set in card.cardSets ?? [] {
            // "0" means unpriced rather than free, so it is stored as absent.
            let price = set.setPrice.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
            try statements.insertPrinting.execute(arguments: [
                card.id, set.setCode, set.setName, set.setRarity, set.setRarityCode, price,
            ])
        }
    }

    private func writePrices(
        _ card: CatalogCardPayload,
        observedAtText: String,
        using statements: Statements
    ) throws {
        try statements.deletePrices.execute(arguments: [card.id])
        for price in card.cardPrices {
            for entry in price.bySource {
                try statements.insertPrice.execute(
                    arguments: [card.id, entry.source, entry.value, observedAtText])
            }
        }
    }

    // MARK: - Localised text

    /// Fills the Italian columns for the cards the localised dataset covers.
    ///
    /// Around a fifth of the pool has no translation, and the localised
    /// response can also mention identifiers the English one does not. English
    /// stays authoritative for whether a card exists at all, so a localised row
    /// with no matching card updates nothing rather than inventing one.
    ///
    /// Returns how many cards were actually translated.
    @discardableResult
    public func mergeItalianDataset(
        _ cards: [CatalogCardPayload],
        into db: Database
    ) throws -> Int {
        let update = try db.makeStatement(sql: """
            UPDATE card SET name_it = ?, desc_it = ? WHERE id = ?
            """)

        var translated = 0
        for card in cards {
            try update.execute(arguments: [card.name, card.desc, card.id])
            translated += db.changesCount
        }
        return translated
    }

    /// The name this card's copies count against.
    ///
    /// Upstream marks 142 cards with a `treated_as` name, but only 13 of them
    /// name a card other than themselves; for the rest the value repeats the
    /// card's own name and changes nothing. Taking it whenever it is present
    /// is therefore both correct and free of a special case.
    static func limitName(for card: CatalogCardPayload) -> String {
        card.misc?.treatedAs ?? card.name
    }

    /// Upstream spells the statuses in title case; the catalog stores them in
    /// the form `BanStatus` round-trips.
    static func banStatus(fromUpstream text: String?) -> BanStatus? {
        switch text {
        case "Forbidden": .forbidden
        case "Limited": .limited
        case "Semi-Limited": .semiLimited
        default: nil
        }
    }

    // MARK: - Prepared statements

    private struct Statements {
        let upsertCard: GRDB.Statement
        let deleteArtworks: GRDB.Statement
        let insertArtwork: GRDB.Statement
        let deleteFormats: GRDB.Statement
        let insertFormat: GRDB.Statement
        let deleteUpstreamBans: GRDB.Statement
        let insertBan: GRDB.Statement
        let deletePrintings: GRDB.Statement
        let insertPrinting: GRDB.Statement
        let deletePrices: GRDB.Statement
        let insertPrice: GRDB.Statement

        init(_ db: Database) throws {
            upsertCard = try db.makeStatement(sql: """
                INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                  human_readable_type, race, attribute, level, atk, def,
                                  link_value, link_markers, pendulum_scale, archetype,
                                  limit_name, has_effect, tcg_date, ocg_date, konami_id, md_rarity)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name_en = excluded.name_en, desc_en = excluded.desc_en,
                    -- Cleared here and refilled by the Italian merge inside the
                    -- same transaction, so a withdrawn translation disappears
                    -- instead of lingering as stale text.
                    name_it = NULL, desc_it = NULL,
                    type = excluded.type, frame_type = excluded.frame_type,
                    human_readable_type = excluded.human_readable_type,
                    race = excluded.race, attribute = excluded.attribute,
                    level = excluded.level, atk = excluded.atk, def = excluded.def,
                    link_value = excluded.link_value, link_markers = excluded.link_markers,
                    pendulum_scale = excluded.pendulum_scale, archetype = excluded.archetype,
                    limit_name = excluded.limit_name,
                    has_effect = excluded.has_effect, tcg_date = excluded.tcg_date,
                    ocg_date = excluded.ocg_date, konami_id = excluded.konami_id,
                    md_rarity = excluded.md_rarity
                """)
            deleteArtworks = try db.makeStatement(sql: "DELETE FROM card_artwork WHERE card_id = ?")
            insertArtwork = try db.makeStatement(sql:
                "INSERT INTO card_artwork (artwork_id, card_id, ordinal) VALUES (?, ?, ?)")
            deleteFormats = try db.makeStatement(sql: "DELETE FROM card_format WHERE card_id = ?")
            insertFormat = try db.makeStatement(sql:
                "INSERT INTO card_format (card_id, format_code) VALUES (?, ?)")
            deleteUpstreamBans = try db.makeStatement(sql:
                "DELETE FROM ban_status WHERE card_id = ? AND source = 'upstream'")
            insertBan = try db.makeStatement(sql:
                "INSERT INTO ban_status (card_id, format_code, status, source) VALUES (?, ?, ?, ?)")
            deletePrintings = try db.makeStatement(sql: "DELETE FROM card_print WHERE card_id = ?")
            insertPrinting = try db.makeStatement(sql: """
                INSERT INTO card_print (card_id, set_code, set_name, rarity, rarity_code, set_price)
                VALUES (?, ?, ?, ?, ?, ?)
                """)
            deletePrices = try db.makeStatement(sql: "DELETE FROM card_price WHERE card_id = ?")
            insertPrice = try db.makeStatement(sql:
                "INSERT INTO card_price (card_id, source, value, observed_at) VALUES (?, ?, ?, ?)")
        }
    }
}
