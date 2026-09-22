import Foundation
import GRDB
import Testing
import YGOCore
@testable import YGOPersistence

@Suite("Deck tag storage")
struct DeckTagStorageTests {
    /// Counts the statements that touch `deck_tag`, so "one read for the whole
    /// list" is a number rather than an impression.
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
        let repository: SQLiteDeckRepository
        let log: StatementLog
    }

    private func makeRig() throws -> Rig {
        let log = StatementLog()
        var configuration = GRDB.Configuration()
        configuration.prepareDatabase { db in
            db.trace { event in log.record(String(describing: event)) }
        }
        let queue = try DatabaseQueue(configuration: configuration)
        try CatalogSchema.migrator.migrate(queue)
        return Rig(database: queue, repository: SQLiteDeckRepository(database: queue), log: log)
    }

    /// Evidence for R2.AC1: what was written is what comes back.
    @Test func aDeckReadFromStorageCarriesItsTags() async throws {
        let rig = try makeRig()
        let deck = try await rig.repository.createDeck(name: "Tuning", format: .goat)

        try await rig.repository.addTag("da testare", to: deck.id)
        try await rig.repository.addTag("goat", to: deck.id)

        let stored = try #require(try await rig.repository.deck(with: deck.id))
        #expect(stored.tags == ["da testare", "goat"], "ordinati per nome")

        let listed = try #require(try await rig.repository.allDecks().first)
        #expect(listed.tags == ["da testare", "goat"])
    }

    /// Evidence for NFR4: the whole list's tags arrive in one statement, not
    /// one per deck. Loading a deck already costs a query for its slots.
    @Test func theWholeListsTagsArriveWithoutAQueryPerDeck() async throws {
        let rig = try makeRig()
        for name in ["Uno", "Due", "Tre"] {
            let deck = try await rig.repository.createDeck(name: name, format: .tcg)
            try await rig.repository.addTag("comune", to: deck.id)
        }

        rig.log.reset()
        let decks = try await rig.repository.allDecks()
        #expect(decks.count == 3)
        #expect(decks.allSatisfy { $0.tags == ["comune"] })

        let reads = rig.log.count(mentioning: "deck_tag")
        #expect(reads == 1, "una lettura per l'intera lista, non una per mazzo")
    }

    /// Evidence for R2.AC1: no tags is an empty list, not a missing one.
    @Test func aDeckWithNoTagsCarriesAnEmptyList() async throws {
        let rig = try makeRig()
        let deck = try await rig.repository.createDeck(name: "Nudo", format: .tcg)

        let stored = try #require(try await rig.repository.deck(with: deck.id))
        #expect(stored.tags.isEmpty)

        let listed = try #require(try await rig.repository.allDecks().first)
        #expect(listed.tags.isEmpty)
    }
    /// Evidence for R2.AC4: one tag, however it is typed, spelled as it was
    /// first typed.
    @Test func spellingAndSpacesMakeOneTagKeepingTheFirstSpelling() async throws {
        let rig = try makeRig()
        let deck = try await rig.repository.createDeck(name: "Tuning", format: .goat)

        try await rig.repository.addTag("Goat", to: deck.id)
        try await rig.repository.addTag("goat", to: deck.id)
        try await rig.repository.addTag("  goat  ", to: deck.id)
        try await rig.repository.addTag("GOAT", to: deck.id)

        let stored = try #require(try await rig.repository.deck(with: deck.id))
        #expect(stored.tags == ["Goat"], "una sola etichetta, con la prima grafia")

        let rows = try await rig.database.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM tag") ?? -1
        }
        #expect(rows == 1, "e una sola riga in tag")

        // A second deck typing it differently joins the same tag.
        let other = try await rig.repository.createDeck(name: "Altro", format: .goat)
        try await rig.repository.addTag("GOAT", to: other.id)
        let secondStored = try #require(try await rig.repository.deck(with: other.id))
        #expect(secondStored.tags == ["Goat"])
        #expect(try await rig.repository.allTags() == ["Goat"])
    }

    /// Evidence for R2.AC5: a name that is nothing once trimmed writes nothing.
    @Test func anEmptyTagIsRefusedBeforeAnythingIsWritten() async throws {
        let rig = try makeRig()
        let deck = try await rig.repository.createDeck(name: "Tuning", format: .goat)

        try await rig.repository.addTag("   ", to: deck.id)
        try await rig.repository.addTag("", to: deck.id)
        try await rig.repository.addTag("\n\t", to: deck.id)

        let stored = try #require(try await rig.repository.deck(with: deck.id))
        #expect(stored.tags.isEmpty)

        let rows = try await rig.database.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM tag") ?? -1
        }
        #expect(rows == 0, "nemmeno una riga orfana in tag")
    }

    /// Evidence for R2.AC3: a removal reaches one deck and no other.
    @Test func removingATagFromOneDeckLeavesItOnTheOthers() async throws {
        let rig = try makeRig()
        let mine = try await rig.repository.createDeck(name: "Mio", format: .goat)
        let theirs = try await rig.repository.createDeck(name: "Altrui", format: .goat)

        try await rig.repository.addTag("da testare", to: mine.id)
        try await rig.repository.addTag("da testare", to: theirs.id)
        try await rig.repository.addTag("goat", to: mine.id)

        try await rig.repository.removeTag("DA TESTARE", from: mine.id)

        let mineStored = try #require(try await rig.repository.deck(with: mine.id))
        let theirsStored = try #require(try await rig.repository.deck(with: theirs.id))
        #expect(mineStored.tags == ["goat"])
        #expect(theirsStored.tags == ["da testare"], "l'altro mazzo la porta ancora")

        // The tag survives its own removal from a deck.
        #expect(try await rig.repository.allTags() == ["da testare", "goat"])
    }

    /// Evidence for R2.AC6: what to offer is what is in use, once each.
    @Test func everyTagInUseIsListedOnceInOrder() async throws {
        let rig = try makeRig()
        let first = try await rig.repository.createDeck(name: "Uno", format: .goat)
        let second = try await rig.repository.createDeck(name: "Due", format: .edison)

        try await rig.repository.addTag("zoodiac", to: first.id)
        try await rig.repository.addTag("aggro", to: first.id)
        try await rig.repository.addTag("aggro", to: second.id)

        #expect(try await rig.repository.allTags() == ["aggro", "zoodiac"])

        // A tag no deck carries any more is not offered.
        try await rig.repository.removeTag("zoodiac", from: first.id)
        #expect(try await rig.repository.allTags() == ["aggro"])
    }
    /// Evidence for R1.AC1: the repository answers the port a feature module
    /// holds, rather than a feature module reaching for the concrete type.
    @Test func theRepositoryAnswersTheLabellingPort() async throws {
        let rig = try makeRig()
        let labels: any DeckLabelling = rig.repository
        let deck = try await rig.repository.createDeck(name: "Tuning", format: .goat)

        try await labels.addTag("edison", to: deck.id)
        #expect(try await labels.allTags() == ["edison"])

        try await labels.changeFormat(deck.id, to: .edison)
        let stored = try #require(try await rig.repository.deck(with: deck.id))
        #expect(stored.format == .edison)
        #expect(stored.tags == ["edison"])

        try await labels.removeTag("edison", from: deck.id)
        let afterRemoval = try #require(try await rig.repository.deck(with: deck.id))
        #expect(afterRemoval.tags.isEmpty)
        #expect(afterRemoval.format == .edison, "togliere un'etichetta non tocca il formato")
    }

    /// Evidence for R1.AC1: the format survives a second read, which is what
    /// "still reads Edison after a restart" means without restarting anything.
    @Test func aFormatChangeThroughThePortIsStored() async throws {
        let rig = try makeRig()
        let deck = try await rig.repository.createDeck(name: "Tuning", format: .goat)
        let before = try #require(try await rig.repository.deck(with: deck.id))
        #expect(before.format == .goat)

        let labels: any DeckLabelling = rig.repository
        for format in [CardFormat.edison, .tcg, .masterDuel, .goat] {
            try await labels.changeFormat(deck.id, to: format)
            let reread = try #require(try await SQLiteDeckRepository(database: rig.database)
                .deck(with: deck.id))
            #expect(reread.format == format)
        }

        // And the deck's cards were never in the conversation.
        let stored = try #require(try await rig.repository.deck(with: deck.id))
        #expect(stored.slots.isEmpty)
    }
}
