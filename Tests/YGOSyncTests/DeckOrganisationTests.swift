import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOSync

@Suite("Deck organisation")
struct DeckOrganisationTests {
    private func rig() throws -> SQLiteDeckRepository {
        try RealDeck.seededRepository().1
    }

    /// Evidence for R7.AC1: a deck is in one place, not two.
    @Test func deckMovedIntoAFolderListsUnderItAndNotAtTopLevel() async throws {
        let repository = try rig()
        let deck = try await repository.createDeck(name: "Burn", format: .goat)
        let folder = try await repository.createFolder(named: "Retro")

        #expect(try await repository.decks(inFolder: nil).contains { $0.id == deck.id })

        try await repository.move(deck.id, toFolder: folder)

        let inFolder = try await repository.decks(inFolder: folder)
        let atTopLevel = try await repository.decks(inFolder: nil)
        #expect(inFolder.map(\.id) == [deck.id])
        #expect(!atTopLevel.contains { $0.id == deck.id })

        // And back out again.
        try await repository.move(deck.id, toFolder: nil)
        #expect(try await repository.decks(inFolder: folder).isEmpty)
        #expect(try await repository.decks(inFolder: nil).contains { $0.id == deck.id })
    }

    /// Evidence for R7.AC2: tags are not folders; a deck can carry several.
    @Test func taggedDeckListsUnderEachOfItsTags() async throws {
        let repository = try rig()
        let deck = try await repository.createDeck(name: "Chaos Turbo", format: .goat)
        let other = try await repository.createDeck(name: "Altro", format: .tcg)

        try await repository.addTag("competitivo", to: deck.id)
        try await repository.addTag("goat", to: deck.id)
        try await repository.addTag("goat", to: other.id)

        #expect(try await repository.decks(withTag: "competitivo").map(\.id) == [deck.id])
        let goat = try await repository.decks(withTag: "goat").map(\.id).sorted()
        #expect(goat == [deck.id, other.id].sorted())

        // Applying the same tag twice is not two tags.
        try await repository.addTag("goat", to: deck.id)
        #expect(try await repository.decks(withTag: "goat").count == 2)

        #expect(try await repository.decks(withTag: "inesistente").isEmpty)
    }

    /// Evidence for R7.AC3: a folder is a label, not an owner. Deleting one
    /// must never take irreplaceable decks with it.
    @Test func deletingAFolderKeepsItsDecks() async throws {
        let repository = try rig()
        let folder = try await repository.createFolder(named: "Da cancellare")

        var ids: [Int64] = []
        for index in 1...3 {
            let deck = try await repository.createDeck(name: "Deck \(index)", format: .tcg)
            try await repository.move(deck.id, toFolder: folder)
            ids.append(deck.id)
        }
        #expect(try await repository.decks(inFolder: folder).count == 3)

        try await repository.deleteFolder(folder)

        for id in ids {
            let survived = try await repository.deck(with: id)
            #expect(survived != nil, "il mazzo \(id) è sparito con la cartella")
            #expect(survived?.folderID == nil, "e deve essere tornato al livello superiore")
        }
        #expect(try await repository.decks(inFolder: nil).count == 3)
    }

    /// Evidence for R7.AC4: search returns the match and only the match.
    @Test func searchingDecksByNameReturnsOnlyTheMatch() async throws {
        let repository = try rig()
        _ = try await repository.createDeck(name: "Lockdown Burn", format: .goat)
        _ = try await repository.createDeck(name: "LR-Chaos Turbo", format: .goat)
        _ = try await repository.createDeck(name: "Sky Striker", format: .tcg)

        #expect(try await repository.decks(named: "Chaos").map(\.name) == ["LR-Chaos Turbo"])
        #expect(try await repository.decks(named: "burn").map(\.name) == ["Lockdown Burn"],
                "la ricerca non distingue maiuscole")
        #expect(try await repository.decks(named: "inesistente").isEmpty)
        #expect(try await repository.decks(named: "   ").count == 3, "una ricerca vuota è tutto")

        // A name full of wildcards must not match everything.
        _ = try await repository.createDeck(name: "100%", format: .tcg)
        #expect(try await repository.decks(named: "%").map(\.name) == ["100%"])
    }
}
