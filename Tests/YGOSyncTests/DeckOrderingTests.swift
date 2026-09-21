import Foundation
import GRDB
import Testing
import YGOCore
import YGODeckIO
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

/// The order a deck list is read in: monsters, then spells, then traps.
///
/// Measured on one of the user's own decks rather than on three cards, so a
/// kind that sorts wrong has somewhere to hide and does not.
@MainActor
@Suite("Deck ordering")
struct DeckOrderingTests {
    private func editor() async throws -> DeckEditorViewModel {
        let (database, repository) = try RealDeck.seededRepository()
        let importer = DeckImporter(repository: repository, validator: DeckValidator())
        let result = try await importer.importFile(
            at: RealDeck.root.appending(path: "fixtures/LR-Chaos Turbo.ydk"))

        let model = DeckEditorViewModel(
            repository: repository, validator: DeckValidator(),
            catalogue: SQLiteCardRepository(database: database), editing: repository)
        await model.load(deckID: result.deck.id)
        return model
    }

    /// What the reader sees inside one section.
    private func kinds(_ model: DeckEditorViewModel, _ section: DeckSection) -> [CardType] {
        model.items.filter { $0.section == section }.map(\.frame.cardType)
    }

    @Test func monstersComeFirstThenSpellsThenTrapsInEverySection() async throws {
        let model = try await editor()

        // The deck has to hold all three for the claim to mean anything.
        let main = kinds(model, .main)
        #expect(main.contains(.monster))
        #expect(main.contains(.spell))
        #expect(main.contains(.trap))

        for section in DeckSection.allCases {
            let ranks = kinds(model, section).map(\.listingOrder)
            #expect(ranks == ranks.sorted(), "\(section.rawValue): \(kinds(model, section))")
        }
    }

    @Test func cardsOfOneKindAreInAlphabeticalOrder() async throws {
        let model = try await editor()
        let monsters = model.items
            .filter { $0.section == .main && $0.frame.cardType == .monster }
            .map(\.title)

        #expect(monsters.count > 5)
        #expect(monsters == monsters.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    /// Keyboard selection walks `items`, so their section order has to be the
    /// order the list draws its sections in - not the order their stored names
    /// happen to sort in, where `extra` precedes `main`.
    @Test func sectionsFollowTheOrderTheyAreDrawnIn() async throws {
        let model = try await editor()
        let order = model.items.map(\.section.listingOrder)

        #expect(order == order.sorted())
        #expect(model.items.first?.section == .main)
        #expect(model.items.last?.section == .side)
    }

    /// The order is a property of the shown list, not of how it was loaded: an
    /// edit rebuilds it and it has to come back sorted.
    @Test func theOrderSurvivesAnEdit() async throws {
        let model = try await editor()
        let trap = try #require(
            model.items.first { $0.section == .main && $0.frame.cardType == .trap })

        await model.setQuantity(3, of: trap.id, in: .main)
        #expect(model.lastFailure == nil)

        let ranks = kinds(model, .main).map(\.listingOrder)
        #expect(ranks == ranks.sorted())

        // A moved card lands among its own kind in the section it arrives in,
        // not at the end of it.
        await model.move(trap.id, from: .main, to: .side, copies: 1)
        let side = kinds(model, .side).map(\.listingOrder)
        #expect(side == side.sorted())
    }
}
