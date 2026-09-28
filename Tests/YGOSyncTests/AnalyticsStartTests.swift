import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureAnalytics
import YGOPersistence
@testable import YGOSync

/// How the statistics screen opens.
///
/// Opening it before choosing a deck anywhere else reported "Il mazzo non è
/// stato letto" and hid the chooser: the composition root read "no deck" as a
/// failed read. `analytics-controls` asks for the choice to be made from within
/// the screen, and for an empty library to be said rather than shown empty.
@MainActor
@Suite("Analytics start")
struct AnalyticsStartTests {
    private func library(holdingADeck: Bool) async throws -> (SQLiteDeckRepository, Deck?) {
        let (_, decks) = try RealDeck.seededRepository()
        guard holdingADeck else { return (decks, nil) }
        let card = try #require(try RealDeck.cards().first)
        let deck = try await decks.createDeck(name: "Tuning", format: .goat)
        try await decks.addCard(
            artwork: ArtworkIdentifier(try #require(card.cardImages.first).id),
            section: .main, to: deck.id)
        return (decks, deck)
    }

    /// Nothing selected is a request to choose, not a failure.
    @Test func openingWithNothingSelectedOffersTheChooserRatherThanAFailure() async throws {
        let (decks, _) = try await library(holdingADeck: true)
        let model = AnalyticsViewModel(library: decks)

        await model.start(on: nil)

        #expect(model.unreadableStartingDeck == nil)
        #expect(model.deck == nil)
        #expect(model.decks.count == 1)
        #expect(model.canChooseDeck)
        #expect(model.noDeckMessage?.contains("Scegli un mazzo") == true)
    }

    /// A deck chosen elsewhere opens with its figures and no message.
    @Test func openingOnADeckChosenElsewhereShowsItsFigures() async throws {
        let (decks, deck) = try await library(holdingADeck: true)
        let chosen = try #require(deck)
        let model = AnalyticsViewModel(library: decks)

        await model.start(on: chosen.id)

        #expect(model.deck?.id == chosen.id)
        #expect(model.unreadableStartingDeck == nil)
        #expect(model.noDeckMessage == nil)
    }

    /// A deck that was asked for and cannot be read is still reported.
    @Test func aRequestedDeckThatCannotBeReadIsReportedAsSuch() async throws {
        let (decks, _) = try await library(holdingADeck: true)
        let model = AnalyticsViewModel(library: decks)

        await model.start(on: 999_999)

        #expect(model.unreadableStartingDeck == 999_999)
        #expect(model.deck == nil)
    }

    /// An empty library says so instead of offering an empty chooser.
    @Test func anEmptyLibrarySaysThereIsNothingToAnalyse() async throws {
        let (decks, _) = try await library(holdingADeck: false)
        let model = AnalyticsViewModel(library: decks)

        await model.start(on: nil)

        #expect(model.libraryIsEmpty)
        #expect(model.unreadableStartingDeck == nil)
        #expect(model.noDeckMessage?.contains("Nessun mazzo salvato") == true)
    }
}
