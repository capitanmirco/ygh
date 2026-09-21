import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

@MainActor
@Suite("Deck edit accessibility")
struct DeckEditAccessibilityTests {
    /// Evidence for NFR4: an entry that read "3×" would tell a listener
    /// nothing. Each one names the card, the section holding it and how many.
    @Test func eachEntryReadsAsASentenceNamingCardSectionAndCount() async throws {
        let (database, repository) = try RealDeck.seededRepository()
        let deck = try await repository.createDeck(name: "Nuovo", format: .tcg)
        let model = DeckEditorViewModel(
            repository: repository, validator: DeckValidator(),
            catalogue: SQLiteCardRepository(database: database), editing: repository)
        await model.load(deckID: deck.id)

        let card = try #require(model.candidates.first { !$0.frame.belongsInExtraDeck })
        await model.add(card, to: .main)
        let artwork = try #require(model.items.first?.id)
        await model.setQuantity(3, of: artwork, in: .main)

        let item = try #require(model.items.first)
        let spoken = item.accessibilityLabel

        #expect(spoken.contains(item.title))
        #expect(spoken.contains("3"))
        #expect(spoken.contains(item.section.italianName))
        #expect(spoken != "\(item.quantity)×")
        #expect(spoken.count > item.title.count)

        // Moving it changes what the entry says about where it is.
        await model.move(artwork, from: .main, to: .side, copies: 3)
        let moved = try #require(model.items.first)
        #expect(moved.accessibilityLabel.contains(DeckSection.side.italianName))
        #expect(!moved.accessibilityLabel.contains(DeckSection.main.italianName))
    }
}
