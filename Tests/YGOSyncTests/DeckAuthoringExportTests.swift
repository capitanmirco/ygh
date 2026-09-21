import Foundation
import GRDB
import Testing
import YGOCore
import YGODeckIO
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

@MainActor
@Suite("Deck authoring export")
struct DeckAuthoringExportTests {
    private func rig() throws -> (DatabaseQueue, SQLiteDeckRepository) {
        try RealDeck.seededRepository()
    }

    private func library(_ decks: SQLiteDeckRepository) -> DeckLibraryViewModel {
        DeckLibraryViewModel(repository: decks, listing: decks, library: decks)
    }

    /// Builds a deck holding known cards, returning the artworks it holds.
    private func deckWithCards(
        _ database: DatabaseQueue, _ decks: SQLiteDeckRepository,
        copies: Int = 2
    ) async throws -> (Deck, [ArtworkIdentifier]) {
        let model = library(decks)
        let deck = try #require(await model.createDeck(named: "Export", format: .tcg))

        let editor = DeckEditorViewModel(
            repository: decks, validator: DeckValidator(),
            catalogue: SQLiteCardRepository(database: database), editing: decks)
        await editor.load(deckID: deck.id)

        let main = try #require(editor.candidates.first { !$0.frame.belongsInExtraDeck })
        let extra = editor.candidates.first { $0.frame.belongsInExtraDeck }
        await editor.add(main, to: .main)
        await editor.setQuantity(
            copies, of: try #require(editor.items.first?.id), in: .main)
        if let extra { await editor.add(extra, to: .extra) }

        let stored = try #require(try await decks.deck(with: deck.id))
        return (stored, stored.slots.map(\.artwork))
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ygo-export-\(UUID().uuidString).ydk")
    }

    /// Evidence for R2.AC1: a `.ydk` lists a passcode once per copy, under the
    /// section holding it. That is the contract other programs read.
    @Test func theFileListsEachPasscodeOncePerCopyUnderItsSection() async throws {
        let (database, decks) = try rig()
        let (deck, _) = try await deckWithCards(database, decks, copies: 3)
        let model = library(decks)
        await model.load()

        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(await model.export(deck.id, to: url))
        #expect(model.lastFailure == nil)

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("#main"))
        #expect(text.contains("#extra"))
        #expect(text.contains("!side"))

        // The main section lists the card three times, once per copy.
        let mainSlot = try #require(deck.slots(in: .main).first)
        let passcode = String(mainSlot.artwork.rawValue)
        let mainLines = text
            .components(separatedBy: "#extra")[0]
            .split(separator: "\n")
            .filter { $0 == passcode }
        #expect(mainLines.count == 3)
    }

    /// Evidence for R2.AC2: a deck holds printings, not cards. Exporting a
    /// card's primary artwork instead would rewrite the user's choice, in
    /// silence, on every export.
    @Test func theArtworkTheDeckHoldsIsTheOneExported() async throws {
        let (database, decks) = try rig()
        let model = library(decks)
        let deck = try #require(await model.createDeck(named: "Alt art", format: .tcg))

        // A card the catalog holds more than one artwork for.
        let catalogue = SQLiteCardRepository(database: database)
        let outcome = try await catalogue.search(CardQuery(limit: 500))
        let multi = try #require(outcome.cards.first { $0.artworks.count > 1 })
        let secondary = multi.artworks[1]
        #expect(secondary != multi.artworks[0])

        let editor = DeckEditorViewModel(
            repository: decks, validator: DeckValidator(),
            catalogue: catalogue, editing: decks)
        await editor.load(deckID: deck.id)
        await editor.add(artwork: secondary, to: .main)

        let text = try #require(await model.ydkText(for: deck.id))

        // The chosen printing is what comes out, not the card's first.
        #expect(text.contains(String(secondary.rawValue)))
        #expect(!text.contains(String(multi.artworks[0].rawValue)))
    }

    /// Evidence for R2.AC3: an unfinished deck is exactly the kind a duelist
    /// carries between machines, so legality is not a gate on export.
    @Test func anIllegalDeckExportsAnyway() async throws {
        let (database, decks) = try rig()
        let model = library(decks)
        let deck = try #require(await model.createDeck(named: "Illegale", format: .tcg))

        let editor = DeckEditorViewModel(
            repository: decks, validator: DeckValidator(),
            catalogue: SQLiteCardRepository(database: database), editing: decks)
        await editor.load(deckID: deck.id)
        let card = try #require(editor.candidates.first { !$0.frame.belongsInExtraDeck })
        await editor.add(card, to: .main)
        // Four copies, and a main deck far below forty.
        await editor.setQuantity(4, of: try #require(editor.items.first?.id), in: .main)
        #expect(!(editor.legality?.violations.isEmpty ?? true))

        let text = try #require(await model.ydkText(for: deck.id))
        #expect(text.contains("#main"))
        #expect(model.lastFailure == nil)

        // And an empty deck exports too, as an empty list rather than a
        // refusal.
        let empty = try #require(await model.createDeck(named: "Vuoto", format: .tcg))
        let emptyText = try #require(await model.ydkText(for: empty.id))
        #expect(emptyText.contains("#main"))
    }

    /// Evidence for R2.AC5: a write that fails and says nothing leaves the
    /// user believing they have a file.
    @Test func anUnwritableDestinationIsReportedAndLeavesNoPartialFile() async throws {
        let (database, decks) = try rig()
        let (deck, _) = try await deckWithCards(database, decks)
        let model = library(decks)

        // A directory that does not exist, so the write cannot land.
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ygo-missing-\(UUID().uuidString)")
            .appending(path: "deck.ydk")

        #expect(await model.export(deck.id, to: url) == false)
        let failure = try #require(model.lastFailure)
        #expect(failure.contains("Esportazione non riuscita"))
        #expect(!FileManager.default.fileExists(atPath: url.path))

        // A good destination afterwards clears the failure.
        let good = temporaryURL()
        defer { try? FileManager.default.removeItem(at: good) }
        #expect(await model.export(deck.id, to: good))
        #expect(model.lastFailure == nil)
    }

    /// Evidence for R2.AC4: a link is how a deck is pasted into a chat rather
    /// than attached to one. It is only useful if it decodes.
    @Test func theLinkDecodesBackToTheSameCardsInTheSameSections() async throws {
        let (database, decks) = try rig()
        let (deck, _) = try await deckWithCards(database, decks, copies: 2)
        let model = library(decks)

        let link = try #require(await model.ydkeLink(for: deck.id))
        #expect(link.hasPrefix("ydke://"))

        let decoded = try YDKeCodec.decode(link)
        let exported = DeckExporter.list(from: deck)
        #expect(decoded[.main] == exported[.main])
        #expect(decoded[.extra] == exported[.extra])
        #expect(decoded[.side] == exported[.side])
        #expect(decoded[.main].count == 2)
    }

    /// Evidence for R2.AC4: an empty deck is a legitimate thing to share — it
    /// is how someone asks for help building one.
    @Test func anEmptyDeckStillProducesAValidLink() async throws {
        let (_, decks) = try rig()
        let model = library(decks)
        let deck = try #require(await model.createDeck(named: "Vuoto", format: .tcg))

        let link = try #require(await model.ydkeLink(for: deck.id))
        #expect(link.hasPrefix("ydke://"))

        let decoded = try YDKeCodec.decode(link)
        #expect(decoded[.main].isEmpty)
        #expect(decoded[.extra].isEmpty)
        #expect(decoded[.side].isEmpty)
    }
}
