import Foundation
import GRDB
import Testing
import YGOCore
import YGODeckIO
import YGOPersistence
import YGOValidation
@testable import YGOSync

@Suite("Deck export")
struct DeckExportTests {
    private func rig() throws -> (SQLiteDeckRepository, DeckImporter) {
        let (_, repository) = try RealDeck.seededRepository()
        return (repository, DeckImporter(repository: repository, validator: DeckValidator()))
    }

    private func fileURL(_ name: String) -> URL {
        RealDeck.root.appending(path: "fixtures/\(name).ydk")
    }

    /// Evidence for R6.AC3: the printing that went in is the printing that
    /// comes out. A deck round-tripped through this application must not have
    /// its artworks quietly swapped for the cards' primary ones.
    @Test func exportsTheArtworkTheDeckHoldsNotThePrimaryOne() async throws {
        let (repository, importer) = try rig()
        let result = try await importer.importFile(at: fileURL("Lockdown Burn"))

        let alternate = ArtworkIdentifier(83_555_667)
        let card = try #require(try await repository.resolveArtwork(alternate))
        #expect(alternate.rawValue != card.rawValue)

        let exported = DeckExporter.list(from: result.deck)
        #expect(exported.main.contains(alternate.rawValue),
                "l'export deve contenere la stampa posseduta")
        #expect(!exported.main.contains(card.rawValue),
                "e non deve sostituirla con l'artwork primario della carta")

        // The whole file round-trips, copies and all.
        let original = try YDKFile.read(contentsOf: fileURL("Lockdown Burn"))
        #expect(exported.main.sorted() == original.main.sorted())
        #expect(exported.totalCount == original.totalCount)

        // Through a link as well as through a file.
        let viaLink = try YDKeCodec.decode(DeckExporter.ydkeLink(for: result.deck))
        #expect(viaLink.main.sorted() == original.main.sorted())
    }

    /// Evidence for R6.AC4: an unfinished deck is exactly the kind worth
    /// carrying between machines, so legality is none of export's business.
    @Test func exportsAndReimportsAnIllegalDeckIntact() async throws {
        let (repository, importer) = try rig()
        let cards = try RealDeck.cards()

        // Thirty cards: far too few, and one card held four times over.
        let deck = try await repository.createDeck(name: "Incompiuto", format: .goat)
        for card in cards.prefix(9) {
            let artwork = ArtworkIdentifier(try #require(card.cardImages.first).id)
            for _ in 0..<3 {
                try await repository.addCard(artwork: artwork, section: .main, to: deck.id)
            }
        }
        let overCopied = ArtworkIdentifier(try #require(cards.first?.cardImages.first).id)
        try await repository.addCard(artwork: overCopied, section: .main, to: deck.id)

        let unfinished = try #require(try await repository.deck(with: deck.id))
        let violations = DeckValidator().violations(
            in: unfinished, using: try await repository.cardIndex(for: unfinished))
        #expect(!violations.isEmpty, "il mazzo di prova deve essere illegale")

        // It exports anyway, and comes back identical.
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ygo-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appending(path: "Incompiuto.ydk")
        try DeckExporter.write(unfinished, to: file)

        let reimported = try await importer.importFile(at: file)
        #expect(reimported.deck.count(in: .main) == unfinished.count(in: .main))
        #expect(reimported.isComplete)

        let before = DeckExporter.list(from: unfinished)
        let after = DeckExporter.list(from: reimported.deck)
        #expect(after == before, "il mazzo illegale deve sopravvivere al round trip immutato")
        #expect(reimported.deck.name == "Incompiuto")
    }

    /// Copies are written out one line each, the way the formats express them.
    @Test func writesEachCopyAsItsOwnEntry() async throws {
        let (repository, _) = try rig()
        let cards = try RealDeck.cards()
        let artwork = ArtworkIdentifier(try #require(cards.first?.cardImages.first).id)

        let deck = try await repository.createDeck(name: "Copie", format: .goat)
        for _ in 0..<3 {
            try await repository.addCard(artwork: artwork, section: .main, to: deck.id)
        }

        let stored = try #require(try await repository.deck(with: deck.id))
        #expect(stored.slots(in: .main).count == 1, "tre copie sono una voce in archivio")

        let exported = DeckExporter.list(from: stored)
        #expect(exported.main.count == 3, "ma tre righe nel file")
        #expect(exported.main.allSatisfy { $0 == artwork.rawValue })
    }
}
