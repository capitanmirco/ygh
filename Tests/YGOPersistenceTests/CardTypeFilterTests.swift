import Foundation
import GRDB
import Testing
import YGOCore
@testable import YGOPersistence

@Suite("Card type and unknown stats")
struct CardTypeFilterTests {
    /// A pool holding the shapes that matter: the three card types, a monster
    /// printing "?" for attack, and one with a real value either side of it.
    private func seeded() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)

        let rows: [(Int, String, String, Int?, Int?)] = [
            (1, "Weak Monster", "normal", 300, 200),
            (2, "Strong Monster", "effect", 2500, 2100),
            (3, "Question Mark Monster", "effect", -1, -1),
            (4, "Half Unknown", "effect", 1000, -1),
            (5, "A Spell", "spell", nil, nil),
            (6, "Another Spell", "spell", nil, nil),
            (7, "A Trap", "trap", nil, nil),
            (8, "A Token", "token", 0, 0),
            (9, "A Skill", "skill", nil, nil),
            (10, "A Fusion", "fusion", 2800, 2100),
        ]

        try queue.write { db in
            for (id, name, frame, atk, def) in rows {
                try db.execute(sql: """
                    INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                      human_readable_type, atk, def)
                    VALUES (?, ?, 'text', ?, ?, ?, ?, ?)
                    """, arguments: [id, name, frame, frame, frame, atk, def])
            }
        }
        return queue
    }

    private func names(_ queue: DatabaseQueue, _ filters: CardFilters) async throws -> Set<String> {
        let repository = SQLiteCardRepository(database: queue)
        var query = CardQuery(filters: filters)
        query.limit = 100
        return Set(try await repository.search(query).cards.map(\.englishName))
    }

    /// Evidence for R1.AC1: the catalog stores seventeen frames and no card
    /// type. Asking for spells has to mean asking for the frames that are
    /// spells.
    @Test func spellsAloneAdmitOnlySpells() async throws {
        let queue = try seeded()
        var filters = CardFilters()
        filters.cardTypes = [.spell]

        let spells = try await names(queue, filters)
        #expect(spells == ["A Spell", "Another Spell"])

        filters.cardTypes = [.trap]
        #expect(try await names(queue, filters) == ["A Trap"])

        // Two types together admit both, not neither.
        filters.cardTypes = [.spell, .trap]
        #expect(try await names(queue, filters).count == 3)

        // Monsters are everything that is not a spell, a trap, a token or a
        // skill - including the extra deck.
        filters.cardTypes = [.monster]
        let monsters = try await names(queue, filters)
        #expect(monsters.contains("A Fusion"))
        #expect(!monsters.contains("A Token"))
        #expect(!monsters.contains("A Skill"))

        let repository = SQLiteCardRepository(database: queue)
        #expect(try await repository.matchCount(
            for: CardQuery(filters: filters)) == monsters.count)
    }

    /// Evidence for R1.AC1: four types cover all seventeen frames, so no card
    /// falls outside the filter and no frame is claimed by two types.
    @Test func everySeventeenFramesGroupsIntoOneOfFourTypes() {
        #expect(CardFrame.allCases.count == 17)
        #expect(CardType.allCases.count == 4)

        // Every frame has exactly one type.
        let covered = CardType.allCases.flatMap(\.frames)
        #expect(Set(covered).count == 17)
        #expect(covered.count == 17, "a frame is claimed by two types")

        // And the groupings are the ones the catalog's own counts describe.
        #expect(CardType.spell.frames == [.spell])
        #expect(CardType.trap.frames == [.trap])
        #expect(Set(CardType.other.frames) == [.token, .skill])
        #expect(CardType.monster.frames.count == 13)
        #expect(CardFrame.effectPendulum.cardType == .monster)
    }

    /// Evidence for R1.AC7, and the reason this task comes first: the catalog
    /// stores `-1` where the card prints "?". A range from zero that admitted
    /// it would answer "weak monsters" with monsters nobody can measure.
    @Test func aRangeFromZeroDoesNotAdmitACardPrintingAQuestionMark() async throws {
        let queue = try seeded()
        var filters = CardFilters()
        filters.attack = 0...1000

        let weak = try await names(queue, filters)
        #expect(weak.contains("Weak Monster"))
        #expect(weak.contains("Half Unknown"))
        #expect(!weak.contains("Question Mark Monster"))

        // Even a range that literally spans -1 refuses it.
        filters.attack = -5...5000
        let everything = try await names(queue, filters)
        #expect(!everything.contains("Question Mark Monster"))
        #expect(everything.contains("Strong Monster"))

        // Defence behaves the same way.
        var byDefence = CardFilters()
        byDefence.defense = 0...3000
        let defended = try await names(queue, byDefence)
        #expect(!defended.contains("Question Mark Monster"))
        #expect(!defended.contains("Half Unknown"))

        // And the count agrees with the rows, which is what would break if
        // the exclusion happened after the query instead of inside it.
        let repository = SQLiteCardRepository(database: queue)
        var query = CardQuery(filters: byDefence)
        query.limit = 100
        #expect(try await repository.matchCount(for: query) == defended.count)
    }

    /// Evidence for R1.AC7: "how strong is it" and "is it knowable" are two
    /// questions, so they get two filters.
    @Test func theUnknownStatsFilterFindsThemInstead() async throws {
        let queue = try seeded()
        var filters = CardFilters()
        filters.unknownStatsOnly = true

        let unknown = try await names(queue, filters)
        #expect(unknown == ["Question Mark Monster", "Half Unknown"])

        // It is a filter in its own right, so an otherwise empty set of
        // filters is not empty with it on.
        #expect(!filters.isEmpty)
        #expect(CardFilters().isEmpty)

        // Combined with a type, it narrows further rather than starting over.
        filters.cardTypes = [.monster]
        #expect(try await names(queue, filters).count == 2)
    }
}
