import Foundation
import GRDB
import Testing
import YGOCore
import YGONetworking
import YGOPersistence
@testable import YGOSync

@Suite("Deck repository")
struct DeckRepositoryTests {
    private static let start = Date(timeIntervalSince1970: 1_758_000_000)

    /// A ticking clock, so a modification time can be shown to move forward
    /// rather than merely to exist.
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var seconds: Double = 0
        var now: @Sendable () -> Date {
            { [self] in
                lock.lock(); defer { lock.unlock() }
                seconds += 60
                return DeckRepositoryTests.start.addingTimeInterval(seconds)
            }
        }
    }

    private struct Rig {
        let repository: SQLiteDeckRepository
        let database: DatabaseQueue
        let cards: [CatalogCardPayload]
    }

    private func seeded() throws -> Rig {
        let database = try SyncFixture.migratedDatabase()
        let cards = try SyncFixture.cards("catalog-en.json")
        try database.write { db in
            try CatalogWriter().writeEnglishDataset(
                cards, observedAt: SyncFixture.observedAt, into: db)
        }
        return Rig(
            repository: SQLiteDeckRepository(database: database, now: Clock().now),
            database: database, cards: cards)
    }

    private func artwork(_ rig: Rig, at index: Int) throws -> (ArtworkIdentifier, CatalogCardPayload) {
        let card = rig.cards[index]
        let image = try #require(card.cardImages.first)
        return (ArtworkIdentifier(image.id), card)
    }

    /// Evidence for R1.AC2: a copy lands where it was put and nowhere else.
    @Test func addingCardRaisesItsCountInThatSectionOnly() async throws {
        let rig = try seeded()
        let deck = try await rig.repository.createDeck(name: "Prova", format: .tcg)
        let (art, _) = try artwork(rig, at: 0)

        for _ in 0..<3 {
            try await rig.repository.addCard(artwork: art, section: .main, to: deck.id)
        }

        let loaded = try #require(try await rig.repository.deck(with: deck.id))
        #expect(loaded.count(in: .main) == 3)
        #expect(loaded.count(in: .side) == 0)
        #expect(loaded.count(in: .extra) == 0)
        #expect(loaded.slots(in: .main).count == 1, "tre copie sono una voce, non tre")

        // The same printing in another section is a separate entry.
        try await rig.repository.addCard(artwork: art, section: .side, to: deck.id)
        let afterSide = try #require(try await rig.repository.deck(with: deck.id))
        #expect(afterSide.count(in: .main) == 3)
        #expect(afterSide.count(in: .side) == 1)
    }

    /// Evidence for R1.AC3: removing the last copy leaves no trace of the card.
    @Test func removingLastCopyDropsTheEntryEntirely() async throws {
        let rig = try seeded()
        let deck = try await rig.repository.createDeck(name: "Prova", format: .tcg)
        let (art, _) = try artwork(rig, at: 0)

        try await rig.repository.addCard(artwork: art, section: .main, to: deck.id)
        try await rig.repository.addCard(artwork: art, section: .main, to: deck.id)
        try await rig.repository.removeCard(artwork: art, section: .main, from: deck.id)

        var loaded = try #require(try await rig.repository.deck(with: deck.id))
        #expect(loaded.count(in: .main) == 1)

        try await rig.repository.removeCard(artwork: art, section: .main, from: deck.id)
        loaded = try #require(try await rig.repository.deck(with: deck.id))
        #expect(loaded.slots.isEmpty, "l'ultima copia deve togliere la voce, non lasciarla a zero")

        // Removing from a section that holds nothing changes nothing.
        try await rig.repository.removeCard(artwork: art, section: .side, from: deck.id)
        loaded = try #require(try await rig.repository.deck(with: deck.id))
        #expect(loaded.slots.isEmpty)
    }

    /// Evidence for R1.AC4: the deck keeps its cards and changes its verdict.
    /// The same card is Forbidden in one format and unrestricted in another,
    /// which is exactly why a fixed-format builder gets real decks wrong.
    @Test func changingFormatKeepsCardsAndChangesReportedViolations() async throws {
        let rig = try seeded()
        let deck = try await rig.repository.createDeck(name: "Prova", format: .tcg)

        // A card whose restriction differs between two formats.
        let differing = try #require(rig.cards.first { card in
            let tcg = card.banlistInfo?.banTcg
            let goat = card.banlistInfo?.banGoat
            return tcg != goat
        })
        let art = ArtworkIdentifier(try #require(differing.cardImages.first).id)
        try await rig.repository.addCard(artwork: art, section: .main, to: deck.id)

        let inTCG = try #require(try await rig.repository.deck(with: deck.id))
        let tcgIndex = try await rig.repository.cardIndex(for: inTCG)
        let tcgStatus = try #require(tcgIndex[CardIdentifier(differing.id)]).banStatus

        try await rig.repository.changeFormat(deck.id, to: .goat)

        let inGOAT = try #require(try await rig.repository.deck(with: deck.id))
        #expect(inGOAT.format == .goat)
        #expect(inGOAT.slots == inTCG.slots, "cambiare formato non deve toccare le carte")

        let goatIndex = try await rig.repository.cardIndex(for: inGOAT)
        let goatStatus = try #require(goatIndex[CardIdentifier(differing.id)]).banStatus
        #expect(goatStatus != tcgStatus,
                "\(differing.name): atteso uno stato diverso fra TCG e GOAT")
    }

    /// Evidence for R1.AC5: an edit moves the recorded time forward.
    @Test func editRecordsALaterModificationTime() async throws {
        let rig = try seeded()
        let deck = try await rig.repository.createDeck(name: "Prova", format: .tcg)
        let (art, _) = try artwork(rig, at: 0)

        let before = try #require(try await rig.repository.deck(with: deck.id)).updatedAt
        try await rig.repository.addCard(artwork: art, section: .main, to: deck.id)
        let afterAdd = try #require(try await rig.repository.deck(with: deck.id)).updatedAt
        #expect(afterAdd > before)

        try await rig.repository.rename(deck.id, to: "Rinominato")
        let afterRename = try #require(try await rig.repository.deck(with: deck.id))
        #expect(afterRename.updatedAt > afterAdd)
        #expect(afterRename.name == "Rinominato")
        #expect(afterRename.createdAt == deck.createdAt, "la creazione non si sposta")
    }

    /// Evidence for R1.AC6: a deck is never lost as a side effect.
    @Test func deletionWithoutConfirmationLeavesTheDeckRetrievable() async throws {
        let rig = try seeded()
        let deck = try await rig.repository.createDeck(name: "Prova", format: .tcg)
        let (art, _) = try artwork(rig, at: 0)
        try await rig.repository.addCard(artwork: art, section: .main, to: deck.id)

        await #expect(throws: DeckRepositoryError.deletionNotConfirmed) {
            try await rig.repository.delete(deck.id, confirmed: false)
        }

        let survived = try await rig.repository.deck(with: deck.id)
        #expect(survived != nil)
        #expect(survived?.count(in: .main) == 1)

        try await rig.repository.delete(deck.id, confirmed: true)
        let gone = try await rig.repository.deck(with: deck.id)
        #expect(gone == nil)

        // The catalog is untouched by a deck being removed.
        let remainingCards = try await rig.database.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM card")
        }
        #expect(remainingCards == rig.cards.count)
    }

    /// Evidence for R1.AC7: a copy is a copy, not a second view of the same list.
    @Test func duplicateIsIndependentOfItsOriginal() async throws {
        let rig = try seeded()
        let original = try await rig.repository.createDeck(name: "Originale", format: .goat)
        let (first, _) = try artwork(rig, at: 0)
        let (second, _) = try artwork(rig, at: 1)

        try await rig.repository.addCard(artwork: first, section: .main, to: original.id)
        try await rig.repository.addCard(artwork: first, section: .main, to: original.id)
        try await rig.repository.addCard(artwork: second, section: .side, to: original.id)

        let copy = try await rig.repository.duplicate(original.id, named: "Copia")
        #expect(copy.id != original.id)
        #expect(copy.name == "Copia")
        #expect(copy.format == .goat)
        #expect(copy.count(in: .main) == 2)
        #expect(copy.count(in: .side) == 1)

        // Editing the copy must not reach the original.
        try await rig.repository.addCard(artwork: second, section: .main, to: copy.id)
        try await rig.repository.removeCard(artwork: first, section: .main, from: copy.id)

        let editedCopy = try #require(try await rig.repository.deck(with: copy.id))
        let untouched = try #require(try await rig.repository.deck(with: original.id))
        #expect(editedCopy.count(in: .main) == 2)
        #expect(untouched.count(in: .main) == 2)
        #expect(untouched.slots(in: .main).count == 1)

        // And deleting the copy leaves the original standing.
        try await rig.repository.delete(copy.id, confirmed: true)
        #expect(try await rig.repository.deck(with: original.id) != nil)
    }

    /// A printing the catalog does not hold cannot enter a deck, so a slot's
    /// foreign key can never dangle.
    @Test func refusesAPrintingTheCatalogDoesNotHold() async throws {
        let rig = try seeded()
        let deck = try await rig.repository.createDeck(name: "Prova", format: .tcg)
        let ghost = ArtworkIdentifier(999_999_999)

        await #expect(throws: DeckRepositoryError.artworkNotInCatalog(ghost)) {
            try await rig.repository.addCard(artwork: ghost, section: .main, to: deck.id)
        }

        let loaded = try #require(try await rig.repository.deck(with: deck.id))
        #expect(loaded.slots.isEmpty)
    }
}
