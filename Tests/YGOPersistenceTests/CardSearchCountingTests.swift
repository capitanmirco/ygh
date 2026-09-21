import Foundation
import GRDB
import Testing
import YGOCore
@testable import YGOPersistence

@Suite("Card search counting")
struct CardSearchCountingTests {
    /// A catalog small enough to reason about and varied enough that a filter
    /// and a text match select different subsets.
    private func seeded() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)

        let cards: [(Int, String, String?, String, String, String?, Int?)] = [
            (1, "Blue-Eyes White Dragon", "Drago Bianco Occhi Blu", "Normal Monster", "normal", "LIGHT", 8),
            (2, "Dark Magician", "Mago Nero", "Normal Monster", "normal", "DARK", 7),
            (3, "Blue-Eyes Alternative White Dragon", nil, "Effect Monster", "effect", "LIGHT", 8),
            (4, "Monster Reborn", nil, "Spell Card", "spell", nil, nil),
            (5, "Mirror Force", "Forza Specchio", "Trap Card", "trap", nil, nil),
            (6, "Pot of Greed", nil, "Spell Card", "spell", nil, nil),
        ]

        try queue.write { db in
            for (id, en, it, type, frame, attribute, level) in cards {
                try db.execute(sql: """
                    INSERT INTO card (id, name_en, desc_en, name_it, desc_it,
                                      type, frame_type, human_readable_type,
                                      attribute, level)
                    VALUES (?, ?, 'effect text', ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [id, en, it, it == nil ? nil : "testo",
                                     type, frame, type, attribute, level])
                // Everything is legal in the TCG; only the monsters in GOAT.
                try db.execute(sql: """
                    INSERT INTO card_format (card_id, format_code) VALUES (?, 'TCG')
                    """, arguments: [id])
                if frame == "normal" || frame == "effect" {
                    try db.execute(sql: """
                        INSERT INTO card_format (card_id, format_code) VALUES (?, 'GOAT')
                        """, arguments: [id])
                }
            }
        }
        return queue
    }

    /// Evidence for R1.AC4: with nothing narrowing it, the count is the whole
    /// catalog rather than the size of the page that was asked for.
    @Test func countsTheWholeCatalogWhenNothingNarrowsIt() async throws {
        let repository = SQLiteCardRepository(database: try seeded())

        let all = try await repository.matchCount(for: CardQuery())
        #expect(all == 6)

        // The page asked for is two cards. The count is still six.
        let paged = try await repository.matchCount(for: CardQuery(limit: 2))
        #expect(paged == 6)

        let shown = try await repository.search(CardQuery(limit: 2)).cards
        #expect(shown.count == 2)
    }

    /// Evidence for R1.AC4, and the reason this task comes first: the count
    /// must be the size of the set the search would return, not a number that
    /// merely looks plausible. Asserted by comparing against the search itself
    /// with the page opened wide, for every shape of query.
    @Test func theCountMatchesWhatAnUnpagedSearchWouldReturn() async throws {
        let repository = SQLiteCardRepository(database: try seeded())

        var goatOnly = CardFilters()
        goatOnly.format = .goat

        var lightMonsters = CardFilters()
        lightMonsters.format = .goat
        lightMonsters.attributes = [.light]

        var levelEight = CardFilters()
        levelEight.levels = 8...8

        let queries: [(String, CardQuery)] = [
            ("nothing", CardQuery()),
            ("text", CardQuery(text: "blue")),
            ("filter alone", CardQuery(filters: goatOnly)),
            ("filter with a join", CardQuery(filters: lightMonsters)),
            ("range", CardQuery(filters: levelEight)),
            ("text and filter together", CardQuery(text: "dragon", filters: lightMonsters)),
            ("text matching nothing", CardQuery(text: "zzzzz")),
        ]

        for (label, query) in queries {
            var wide = query
            wide.limit = 1_000
            wide.offset = 0

            let searched = try await repository.search(wide).cards
            let counted = try await repository.matchCount(for: query)
            #expect(counted == searched.count, "\(label)")
        }

        // Spot-checked against the expected sets, so a builder that returned
        // the same wrong number from both statements could not pass.
        #expect(try await repository.matchCount(for: CardQuery(text: "blue")) == 2)
        #expect(try await repository.matchCount(for: CardQuery(filters: goatOnly)) == 3)
        #expect(try await repository.matchCount(for: CardQuery(filters: lightMonsters)) == 2)
        #expect(try await repository.matchCount(for: CardQuery(text: "zzzzz")) == 0)
    }

    /// Evidence for R1.AC4: the counting statement drops the ordering and the
    /// page, and drops their bound arguments with them. The ordering carries
    /// two values when the query has text; leaving them in would shift every
    /// placeholder after them.
    @Test func countingIsUnaffectedByLimitOffsetAndOrdering() async throws {
        let repository = SQLiteCardRepository(database: try seeded())

        var filters = CardFilters()
        filters.format = .goat
        filters.attributes = [.light]

        // Text puts two values into the ordering clause and one into the
        // conditions; the format filter puts one into a join. If the counting
        // statement kept the ordering arguments, this is where it would bind
        // "blue" to the format code and quietly return nothing.
        let base = CardQuery(text: "blue", filters: filters)
        let expected = try await repository.matchCount(for: base)
        #expect(expected == 2)

        for (limit, offset) in [(1, 0), (5, 0), (200, 0), (2, 1), (1, 5), (1_000, 900)] {
            var paged = base
            paged.limit = limit
            paged.offset = offset
            #expect(try await repository.matchCount(for: paged) == expected,
                    "limit \(limit) offset \(offset)")
        }

        // The statement itself carries neither clause.
        let statement = try #require(CardQueryBuilder(query: base).makeCountStatement())
        #expect(!statement.sql.contains("ORDER BY"))
        #expect(!statement.sql.contains("LIMIT"))
        #expect(!statement.sql.contains("OFFSET"))
        #expect(statement.sql.contains("COUNT(*)"))

        // Four fewer placeholders than the search: the ordering's two and the
        // page's two. Counting them in the SQL is what proves the arguments
        // were removed along with the clauses rather than left to shift.
        let search = try #require(CardQueryBuilder(query: base).makeStatement())
        let searchPlaceholders = search.sql.filter { $0 == "?" }.count
        let countPlaceholders = statement.sql.filter { $0 == "?" }.count
        #expect(searchPlaceholders == countPlaceholders + 4)
    }
}
