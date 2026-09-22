import Foundation
import GRDB
import Testing
import YGOCore
@testable import YGOPersistence

@Suite("Deck list judgement")
struct DeckListJudgementTests {
    /// Counts the statements that touch `banlist_entry`, so "one read for a
    /// whole deck" is a number rather than an impression.
    private final class StatementLog: @unchecked Sendable {
        private let lock = NSLock()
        private var statements: [String] = []
        func record(_ sql: String) { lock.withLock { statements.append(sql) } }
        func reset() { lock.withLock { statements.removeAll() } }
        func count(mentioning fragment: String) -> Int {
            lock.withLock { statements.filter { $0.contains(fragment) }.count }
        }
    }

    private struct Rig {
        let database: DatabaseQueue
        let decks: SQLiteDeckRepository
        let history: SQLiteBanlistHistory
        let deckID: Int64
        let log: StatementLog
    }

    /// A catalog of four cards, a list naming three of them, and a deck.
    /// The fourth card carries no `konami_id`, which is the case 203 of the
    /// catalog's cards are in.
    private func makeRig(cards: Int = 4) async throws -> Rig {
        let log = StatementLog()
        var configuration = GRDB.Configuration()
        configuration.prepareDatabase { db in
            db.trace { event in log.record(String(describing: event)) }
        }
        let queue = try DatabaseQueue(configuration: configuration)
        try CatalogSchema.migrator.migrate(queue)

        try await queue.write { db in
            for id in stride(from: 1, through: cards, by: 1) {
                // The last card has no konami identifier at all.
                let konami: Int? = id == cards ? nil : 4000 + id
                try db.execute(sql: """
                    INSERT INTO card (id, name_en, name_it, desc_en, type, frame_type,
                                      human_readable_type, konami_id)
                    VALUES (?, ?, ?, 'testo', 'Spell Card', 'spell', 'Spell Card', ?)
                    """, arguments: [id, "Card \(id)", "Carta \(id)", konami])
                try db.execute(sql: """
                    INSERT INTO card_artwork (artwork_id, card_id, ordinal) VALUES (?, ?, 0)
                    """, arguments: [id, id])
            }

            try db.execute(sql: """
                INSERT INTO banlist_revision (id, format_code, effective_date, source, fetched_at)
                VALUES (1, 'tcg', '2010-03-01', 'fixture', '2026-09-22T00:00:00Z')
                """)
            // Card 1 forbidden, card 2 limited, card 3 not named at all.
            try db.execute(sql: """
                INSERT INTO banlist_entry (revision_id, konami_id, status)
                VALUES (1, 4001, 'forbidden'), (1, 4002, 'limited')
                """)
        }

        let decks = SQLiteDeckRepository(database: queue)
        let deck = try await decks.createDeck(name: "Giudicato", format: .edison)
        return Rig(
            database: queue, decks: decks,
            history: SQLiteBanlistHistory(database: queue),
            deckID: deck.id, log: log)
    }

    private func judged(_ rig: Rig) async throws -> [ListedDeckCard] {
        try await rig.history.judge(rig.deckID, against: .tcg, effectiveDate: "2010-03-01")
    }

    /// Evidence for R2.AC1: what the list says about each card of the deck.
    @Test func aDeckIsJudgedCardByCardAgainstTheChosenList() async throws {
        let rig = try await makeRig()
        try await rig.decks.addCard(artwork: ArtworkIdentifier(1), section: .main, to: rig.deckID)
        try await rig.decks.addCard(artwork: ArtworkIdentifier(2), section: .main, to: rig.deckID)

        let cards = try await judged(rig)
        #expect(cards.count == 2)

        let byName = Dictionary(uniqueKeysWithValues: cards.map { ($0.name, $0) })
        #expect(byName["Carta 1"]?.status == .forbidden)
        #expect(byName["Carta 1"]?.permitted == 0)
        #expect(byName["Carta 2"]?.status == .limited)
        #expect(byName["Carta 2"]?.permitted == 1)
        #expect(cards.allSatisfy { $0.isMatched })

        // A list nobody stored judges nothing rather than lying.
        let missing = try await rig.history.judge(
            rig.deckID, against: .tcg, effectiveDate: "1999-01-01")
        #expect(missing.isEmpty)
    }

    /// Evidence for R2.AC2: a card the list ignores is unrestricted, and it
    /// must still come back — a card that fell out of the join would make the
    /// deck look smaller than it is.
    @Test func aCardTheListDoesNotNameIsUnrestricted() async throws {
        let rig = try await makeRig()
        try await rig.decks.addCard(artwork: ArtworkIdentifier(3), section: .main, to: rig.deckID)

        let card = try #require(try await judged(rig).first)
        #expect(card.name == "Carta 3")
        #expect(card.status == nil)
        #expect(card.permitted == 3)
        #expect(card.isMatched)
        #expect(!card.isOverAllowance)
        #expect(card.announcement.contains("non elencata"))
    }

    /// Evidence for R2.AC5: unmatched is its own answer.
    @Test func aCardWithNoKonamiIdentifierIsUnmatchedNotUnrestricted() async throws {
        let rig = try await makeRig()
        try await rig.decks.addCard(artwork: ArtworkIdentifier(4), section: .main, to: rig.deckID)

        let card = try #require(try await judged(rig).first)
        #expect(!card.isMatched)
        #expect(card.status == nil)
        #expect(!card.isOverAllowance, "senza abbinamento non c'è un limite da superare")
        #expect(card.announcement.contains("non abbinabile"))
        #expect(!card.announcement.contains("consentite"))
    }

    /// Evidence for R2.AC3 and R3.AC3: copies, not entries.
    @Test func copiesAreSummedPerCardRatherThanCountedPerEntry() async throws {
        let rig = try await makeRig()
        for _ in 0..<3 {
            try await rig.decks.addCard(
                artwork: ArtworkIdentifier(2), section: .main, to: rig.deckID)
        }
        // The same card in another section counts towards the same total.
        try await rig.decks.addCard(artwork: ArtworkIdentifier(2), section: .side, to: rig.deckID)

        let cards = try await judged(rig)
        #expect(cards.count == 1, "una riga per carta, non una per copia")

        let card = try #require(cards.first)
        #expect(card.held == 4)
        #expect(card.permitted == 1)
        #expect(card.isOverAllowance)
        #expect(card.announcement.contains("4 in mazzo, 1 consentite"))
    }

    /// Evidence for NFR1: one read for the whole deck.
    @Test func judgingAWholeDeckIsOneReadOfTheList() async throws {
        let rig = try await makeRig()
        for id in 1...3 {
            try await rig.decks.addCard(
                artwork: ArtworkIdentifier(id), section: .main, to: rig.deckID)
        }

        rig.log.reset()
        let cards = try await judged(rig)
        #expect(cards.count == 3)
        #expect(rig.log.count(mentioning: "banlist_entry") == 1,
                "una lettura della lista, non una per carta")
    }
}
