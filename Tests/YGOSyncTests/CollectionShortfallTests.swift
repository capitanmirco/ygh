import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureCollection
import YGOPersistence
@testable import YGOSync

/// A collection reader whose every read fails, for the case the panel used to
/// answer anyway.
private struct FailingCollectionReader: CollectionReading {
    struct Unreadable: Error {}

    func ownedCardItems(matching query: String) async throws -> [OwnedCardItem] { throw Unreadable() }
    func collectionTotals() async throws -> CollectionTotals { throw Unreadable() }
    func ownedCopiesByCard() async throws -> [CardIdentifier: Int] { throw Unreadable() }
}

/// The "Cosa manca" panel given its subject: which deck, and only what is
/// known about it. These assert the model the panel draws from; the drawn
/// panel is checked by hand.
@MainActor
@Suite("Collection shortfall")
struct CollectionShortfallTests {
    private typealias Rig = CollectionFixture.Rig

    private func model(_ rig: Rig, reader: (any CollectionReading)? = nil) -> CollectionViewModel {
        CollectionViewModel(
            reader: reader ?? rig.collection, writer: rig.collection,
            library: rig.decks, naming: rig.collection)
    }

    /// A deck holding `copies` of each card, by its first artwork, in the main section.
    private func deck(
        _ name: String,
        holding cards: [(CatalogCardPayload, Int)],
        in rig: Rig
    ) async throws -> Deck {
        let created = try await rig.decks.createDeck(name: name, format: .tcg)
        for (card, copies) in cards {
            let image = try #require(card.cardImages.first)
            for _ in 0..<copies {
                try await rig.decks.addCard(
                    artwork: ArtworkIdentifier(image.id), section: .main, to: created.id)
            }
        }
        return try #require(try await rig.decks.deck(with: created.id))
    }

    private func record(_ copies: Int, of card: CatalogCardPayload, in rig: Rig) async throws {
        for _ in 0..<copies {
            try await rig.collection.addCopy(
                cardID: CardIdentifier(card.id), printID: nil, condition: .nearMint, locationID: nil)
        }
    }

    /// Everything the user authored, as text, for asserting nothing changed.
    private func userRows(_ rig: Rig) async throws -> [String] {
        try await rig.database.read { db in
            try String.fetchAll(db, sql: """
                SELECT id || '|' || name || '|' || format_code || '|' || updated_at FROM deck ORDER BY id
                """)
            + String.fetchAll(db, sql: """
                SELECT deck_id || '|' || section || '|' || artwork_id || '|' || quantity
                FROM deck_slot ORDER BY deck_id, section, artwork_id
                """)
            + String.fetchAll(db, sql: """
                SELECT id || '|' || card_id || '|' || coalesce(print_id, '-') || '|' || quantity
                FROM collection_entry ORDER BY id
                """)
        }
    }

    private func entry(for card: CatalogCardPayload, in model: CollectionViewModel) -> ShortfallEntry? {
        model.shortfall.first { $0.card == CardIdentifier(card.id) }
    }

    // MARK: - R1 Choosing the deck

    /// Evidence for R1.AC1.
    @Test func everyStoredDeckIsOfferedInLibraryOrder() async throws {
        let rig = try CollectionFixture.seeded()
        _ = try await deck("Zeta", holding: [(rig.cards[0], 1)], in: rig)
        _ = try await deck("Alfa", holding: [(rig.cards[1], 1)], in: rig)
        _ = try await deck("Mu", holding: [(rig.cards[2], 1)], in: rig)
        let model = model(rig)

        await model.startShortfall(on: nil)

        #expect(model.canChooseShortfallDeck)
        let stored = try await rig.decks.allDecks()
        #expect(model.decks.map(\.id) == stored.map(\.id))
        #expect(model.decks.map(\.name) == ["Alfa", "Mu", "Zeta"])
    }

    /// Evidence for R1.AC2: three asked for, one held, two needed — under the
    /// name the collection gives the card.
    @Test func choosingADeckReportsWhatItNeedsUnderTheCollectionsNames() async throws {
        let rig = try CollectionFixture.seeded()
        let card = rig.cards[0]
        let chosen = try await deck("Prova", holding: [(card, 3)], in: rig)
        try await record(1, of: card, in: rig)
        let model = model(rig)

        await model.chooseShortfallDeck(chosen.id)

        let needed = try #require(entry(for: card, in: model))
        #expect(needed.required == 3)
        #expect(needed.owned == 1)
        #expect(needed.missing == 2)
        let names = try await rig.collection.cardNames(for: [CardIdentifier(card.id)])
        #expect(needed.cardName == names[CardIdentifier(card.id)])
        #expect(model.shortfall.count == 1)
    }

    /// Evidence for R1.AC3.
    @Test func choosingAnotherDeckReplacesTheReport() async throws {
        let rig = try CollectionFixture.seeded()
        let first = try await deck("Primo", holding: [(rig.cards[0], 2)], in: rig)
        let second = try await deck("Secondo", holding: [(rig.cards[1], 2)], in: rig)
        let model = model(rig)

        await model.chooseShortfallDeck(first.id)
        #expect(entry(for: rig.cards[0], in: model) != nil)

        await model.chooseShortfallDeck(second.id)
        #expect(entry(for: rig.cards[0], in: model) == nil, "una carta del primo mazzo è rimasta")
        #expect(entry(for: rig.cards[1], in: model)?.missing == 2)
        #expect(model.chosenShortfallDeck?.id == second.id)
    }

    /// Evidence for R1.AC4.
    @Test func theReportNamesTheDeckItDescribes() async throws {
        let rig = try CollectionFixture.seeded()
        let chosen = try await deck("Lockdown di prova", holding: [(rig.cards[0], 2)], in: rig)
        let model = model(rig)

        await model.chooseShortfallDeck(chosen.id)

        #expect(model.shortfallReport.deckName == "Lockdown di prova")
        #expect(model.shortfallReport.headline.contains("Lockdown di prova"))
        #expect(model.shortfallReport.headline.contains("2 copie"))
    }

    /// Evidence for R1.AC5.
    @Test func theReportStartsFromTheDeckSelectedInTheWindow() async throws {
        let rig = try CollectionFixture.seeded()
        _ = try await deck("Alfa", holding: [(rig.cards[0], 1)], in: rig)
        let selected = try await deck("Beta", holding: [(rig.cards[1], 1)], in: rig)
        let model = model(rig)

        await model.startShortfall(on: selected.id)

        #expect(model.chosenShortfallDeck?.id == selected.id)
        #expect(model.shortfallReport.deckName == "Beta")
    }

    /// Evidence for R1.AC6: asking is not editing.
    @Test func choosingEveryDeckInTurnWritesNothing() async throws {
        let rig = try CollectionFixture.seeded()
        let first = try await deck("Primo", holding: [(rig.cards[0], 3), (rig.cards[1], 1)], in: rig)
        let second = try await deck("Secondo", holding: [(rig.cards[2], 2)], in: rig)
        try await record(1, of: rig.cards[0], in: rig)
        let before = try await userRows(rig)
        let model = model(rig)

        await model.startShortfall(on: first.id)
        await model.chooseShortfallDeck(second.id)
        await model.chooseShortfallDeck(first.id)

        let after = try await userRows(rig)
        #expect(after == before)
        #expect(!before.isEmpty)
    }

    /// Supports R1.AC2: the port answers in the collection's language —
    /// Italian where the catalog has a translation, English otherwise.
    @Test func theCollectionAnswersCardNamesInItalianWhereTranslated() async throws {
        let rig = try CollectionFixture.seeded()
        let translated = rig.cards[0]
        let untranslated = rig.cards[1]
        try await rig.database.write { db in
            try db.execute(sql: "UPDATE card SET name_it = 'Nome tradotto' WHERE id = ?",
                           arguments: [translated.id])
        }
        let naming: any CardNaming = rig.collection

        let names = try await naming.cardNames(
            for: [CardIdentifier(translated.id), CardIdentifier(untranslated.id)])

        #expect(names[CardIdentifier(translated.id)] == "Nome tradotto")
        #expect(names[CardIdentifier(untranslated.id)] == untranslated.name)
    }

    // MARK: - R2 Saying only what is known

    /// Evidence for R2.AC1. A model with no deck chosen used to call itself
    /// satisfied, because its list was empty.
    @Test func withNoDeckChosenThePanelAsksForOneAndClaimsNothing() async throws {
        let rig = try CollectionFixture.seeded()
        _ = try await deck("Prova", holding: [(rig.cards[0], 3)], in: rig)

        let untouched = model(rig)
        #expect(untouched.shortfallReport == .chooseADeck)
        #expect(!untouched.isShortfallSatisfied)

        let started = model(rig)
        await started.startShortfall(on: nil)

        #expect(started.shortfallReport == .chooseADeck)
        #expect(!started.isShortfallSatisfied)
        #expect(started.shortfall.isEmpty)
        #expect(started.shortfallReport.deckName == nil)
        #expect(!started.shortfallReport.headline.contains("Niente da comprare"))
        #expect(started.shortfallReport.headline.contains("Scegli un mazzo"))
    }

    /// Evidence for R2.AC2.
    @Test func anEmptyLibraryIsSaidRatherThanOfferedAsAnEmptyChooser() async throws {
        let rig = try CollectionFixture.seeded()
        let model = model(rig)

        await model.startShortfall(on: nil)

        #expect(model.shortfallReport == .noDecks)
        #expect(model.decks.isEmpty)
        #expect(!model.isShortfallSatisfied)
        #expect(model.shortfallReport.headline.contains("Nessun mazzo"))
    }

    /// Evidence for R2.AC3: a failed read is neither a list nor "nothing
    /// missing". It used to become a collection owning nothing.
    @Test func aFailedReadIsReportedAsUnavailableNotAsAListOrItsAbsence() async throws {
        let rig = try CollectionFixture.seeded()
        let chosen = try await deck("Prova", holding: [(rig.cards[0], 3)], in: rig)
        let model = model(rig, reader: FailingCollectionReader())

        await model.startShortfall(on: chosen.id)

        #expect(model.shortfallReport == .unavailable(deckName: "Prova"))
        #expect(model.shortfall.isEmpty)
        #expect(!model.isShortfallSatisfied)
        #expect(model.shortfallReport.headline.contains("non è disponibile"))
        #expect(!model.shortfallReport.headline.contains("Niente da comprare"))

        // The certified entry point answers the same way.
        await model.computeShortfall(for: chosen, names: [:])
        #expect(model.shortfallReport == .unavailable(deckName: "Prova"))
    }

    /// Evidence for R2.AC4: missing while it is missing, satisfied once it is
    /// not, and named either way.
    @Test func nothingMissingIsSaidOnlyWhenTrueAndNamesTheDeck() async throws {
        let rig = try CollectionFixture.seeded()
        let card = rig.cards[0]
        let chosen = try await deck("Completo", holding: [(card, 2)], in: rig)
        try await record(1, of: card, in: rig)
        let model = model(rig)

        await model.chooseShortfallDeck(chosen.id)
        #expect(!model.isShortfallSatisfied)

        try await record(1, of: card, in: rig)
        await model.chooseShortfallDeck(chosen.id)

        #expect(model.shortfallReport == .satisfied(deckName: "Completo"))
        #expect(model.isShortfallSatisfied)
        #expect(model.shortfallReport.headline == "Niente da comprare per Completo.")
    }

    // MARK: - R3 Following the collection

    /// Evidence for R3.AC1: recording through the screen shrinks the list,
    /// with no second choice of the deck.
    @Test func recordingACopyShrinksTheReportWithoutChoosingAgain() async throws {
        let rig = try CollectionFixture.seeded()
        let card = rig.cards[0]
        let chosen = try await deck("Prova", holding: [(card, 2)], in: rig)
        let model = model(rig)
        await model.startShortfall(on: chosen.id)
        #expect(entry(for: card, in: model)?.missing == 2)

        await model.recordCopy(of: CardIdentifier(card.id))
        #expect(entry(for: card, in: model)?.missing == 1)
        #expect(model.chosenShortfallDeck?.id == chosen.id)

        await model.recordCopy(of: CardIdentifier(card.id))
        #expect(model.shortfallReport == .satisfied(deckName: "Prova"))
    }
}
