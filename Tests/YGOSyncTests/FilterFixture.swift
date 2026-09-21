import Foundation
import GRDB
import YGOCore
import YGOPersistence

/// A catalog holding one card of every shape the filters have to tell apart,
/// including the ones that trip them: a card printing "?", a card with no
/// release date, and a card with no Konami identifier.
enum FilterFixture {
    struct Row {
        let id: Int
        let name: String
        let frame: String
        let attribute: String?
        let level: Int?
        let race: String?
        let archetype: String?
        let atk: Int?
        let def: Int?
        let tcgDate: String?
        let konamiID: Int?
        let formats: [String]
    }

    static let rows: [Row] = [
        Row(id: 1, name: "Blue-Eyes White Dragon", frame: "normal", attribute: "LIGHT",
            level: 8, race: "Dragon", archetype: "Blue-Eyes", atk: 3000, def: 2500,
            tcgDate: "2002-03-08", konamiID: 4007, formats: ["TCG", "GOAT", "Edison"]),
        Row(id: 2, name: "Dark Magician", frame: "normal", attribute: "DARK",
            level: 7, race: "Spellcaster", archetype: "Dark Magician", atk: 2500, def: 2100,
            tcgDate: "2002-03-08", konamiID: 4008, formats: ["TCG", "GOAT"]),
        Row(id: 3, name: "Chaos Emperor Dragon", frame: "effect", attribute: "DARK",
            level: 8, race: "Dragon", archetype: nil, atk: 3000, def: 2500,
            tcgDate: "2004-06-01", konamiID: 4009, formats: ["TCG", "GOAT"]),
        Row(id: 4, name: "Goblin Attack Force", frame: "effect", attribute: "EARTH",
            level: 4, race: "Warrior", archetype: nil, atk: 2300, def: 0,
            tcgDate: "2004-03-01", konamiID: 4010, formats: ["TCG", "GOAT"]),
        Row(id: 5, name: "Slifer the Sky Dragon", frame: "effect", attribute: "DIVINE",
            level: 10, race: "Divine-Beast", archetype: nil, atk: -1, def: -1,
            tcgDate: "2015-01-01", konamiID: 4011, formats: ["TCG"]),
        Row(id: 6, name: "Pot of Greed", frame: "spell", attribute: nil,
            level: nil, race: nil, archetype: nil, atk: nil, def: nil,
            tcgDate: "2002-06-01", konamiID: 4012, formats: ["TCG", "GOAT", "Edison"]),
        Row(id: 7, name: "Graceful Charity", frame: "spell", attribute: nil,
            level: nil, race: nil, archetype: nil, atk: nil, def: nil,
            tcgDate: "2003-06-01", konamiID: 4013, formats: ["TCG", "GOAT"]),
        Row(id: 8, name: "Mirror Force", frame: "trap", attribute: nil,
            level: nil, race: nil, archetype: nil, atk: nil, def: nil,
            tcgDate: "2002-09-01", konamiID: 4014, formats: ["TCG", "GOAT", "Edison"]),
        Row(id: 9, name: "Undated Card", frame: "effect", attribute: "WATER",
            level: 4, race: "Fish", archetype: nil, atk: 1200, def: 800,
            tcgDate: nil, konamiID: 4015, formats: ["TCG"]),
        Row(id: 10, name: "Unlinkable Card", frame: "effect", attribute: "FIRE",
            level: 3, race: "Pyro", archetype: nil, atk: 900, def: 900,
            tcgDate: "2020-01-01", konamiID: nil, formats: ["TCG"]),
        Row(id: 11, name: "Blue-Eyes Alternative", frame: "effect", attribute: "LIGHT",
            level: 8, race: "Dragon", archetype: "Blue-Eyes", atk: 3000, def: 2500,
            tcgDate: "2016-05-01", konamiID: 4016, formats: ["TCG"]),
        Row(id: 12, name: "A Fusion Monster", frame: "fusion", attribute: "LIGHT",
            level: 9, race: "Dragon", archetype: "Blue-Eyes", atk: 3000, def: 2500,
            tcgDate: "2005-03-01", konamiID: 4017, formats: ["TCG", "GOAT"]),
    ]

    static func database() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)

        try queue.write { db in
            for row in rows {
                try db.execute(sql: """
                    INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                      human_readable_type, attribute, level, race,
                                      archetype, atk, def, tcg_date, konami_id)
                    VALUES (?, ?, 'effect text', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [row.id, row.name, row.frame, row.frame, row.frame,
                                     row.attribute, row.level, row.race, row.archetype,
                                     row.atk, row.def, row.tcgDate, row.konamiID])
                try db.execute(sql: """
                    INSERT INTO card_artwork (artwork_id, card_id, ordinal)
                    VALUES (?, ?, 0)
                    """, arguments: [row.id, row.id])
                for format in row.formats {
                    try db.execute(sql: """
                        INSERT INTO card_format (card_id, format_code) VALUES (?, ?)
                        """, arguments: [row.id, format])
                }
            }
            // Chaos Emperor Dragon is forbidden in GOAT today.
            try db.execute(sql: """
                INSERT INTO ban_status (card_id, format_code, status, source)
                VALUES (3, 'GOAT', 'forbidden', 'upstream')
                """)
        }
        return queue
    }
}
