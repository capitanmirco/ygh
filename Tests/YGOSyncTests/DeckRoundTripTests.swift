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
@Suite("Deck round trip")
struct DeckRoundTripTests {
    /// The only check in this specification that tests the application against
    /// another program's expectations rather than against its own. A format is
    /// a contract, and the cheapest way to be wrong about it is to write a
    /// file only this application can read.
    private func exported(_ deck: Deck) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "round-trip-\(UUID().uuidString).ydk")
        try DeckExporter.write(deck, to: url)
        return url
    }

    /// Evidence for R2.AC6, on a real deck: the user's own LR-Chaos Turbo,
    /// 40 main, 15 extra, 15 side.
    @Test func aDeckExportedAndImportedComesBackTheSame() async throws {
        let (_, decks) = try RealDeck.seededRepository()
        let importer = DeckImporter(repository: decks, validator: DeckValidator())
        let original = try await importer.importFile(
            at: RealDeck.root.appending(path: "fixtures/LR-Chaos Turbo.ydk")).deck

        #expect(original.count(in: .main) == 40)
        #expect(original.count(in: .extra) == 15)
        #expect(original.count(in: .side) == 15)

        let url = try exported(original)
        defer { try? FileManager.default.removeItem(at: url) }

        let reimported = try await importer.importFile(at: url).deck

        // Same sections, same counts.
        for section in DeckSection.allCases {
            #expect(reimported.count(in: section) == original.count(in: section),
                    "\(section.rawValue) changed")
        }

        // Same cards, with the same number of copies of each.
        func tally(_ deck: Deck) -> [String: Int] {
            var result: [String: Int] = [:]
            for slot in deck.slots {
                result["\(slot.section.rawValue)/\(slot.card.rawValue)", default: 0] += slot.quantity
            }
            return result
        }
        #expect(tally(reimported) == tally(original))
        #expect(reimported.id != original.id, "it replaced the deck instead of copying it")
    }

    /// Evidence for R2.AC6: a deck holds printings. A round trip that kept the
    /// cards and lost the artworks would be a round trip that quietly changed
    /// the deck.
    @Test func theRoundTripKeepsTheArtworksNotJustTheCards() async throws {
        let (_, decks) = try RealDeck.seededRepository()
        let importer = DeckImporter(repository: decks, validator: DeckValidator())
        let original = try await importer.importFile(
            at: RealDeck.root.appending(path: "fixtures/Lockdown Burn.ydk")).deck

        let url = try exported(original)
        defer { try? FileManager.default.removeItem(at: url) }
        let reimported = try await importer.importFile(at: url).deck

        func artworks(_ deck: Deck) -> [String: Int] {
            var result: [String: Int] = [:]
            for slot in deck.slots {
                result["\(slot.section.rawValue)/\(slot.artwork.rawValue)", default: 0] += slot.quantity
            }
            return result
        }
        #expect(artworks(reimported) == artworks(original))

        // And the flattened list the exporter produces is identical both ways.
        #expect(DeckExporter.list(from: reimported)[.main]
                == DeckExporter.list(from: original)[.main])
    }

    /// Evidence for R2.AC6: a `.ydk` carries passcodes and sections and
    /// nothing else. Asserting that a name survived would be asserting
    /// something the format does not carry.
    @Test func theNameComesFromTheFileBecauseTheFormatCarriesNone() async throws {
        let (_, decks) = try RealDeck.seededRepository()
        let library = DeckLibraryViewModel(repository: decks, listing: decks, library: decks)
        let created = try #require(
            await library.createDeck(named: "Un nome particolare", format: .goat))

        let importer = DeckImporter(repository: decks, validator: DeckValidator())
        let seeded = try await importer.importFile(
            at: RealDeck.root.appending(path: "fixtures/Lockdown Burn.ydk")).deck

        let url = FileManager.default.temporaryDirectory
            .appending(path: "Un altro nome.ydk")
        try DeckExporter.write(seeded, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let reimported = try await importer.importFile(at: url).deck

        // The name came from the file, not from the deck that was exported.
        #expect(reimported.name == "Un altro nome")
        #expect(reimported.name != seeded.name)
        #expect(created.name == "Un nome particolare")

        // The exported text itself holds no name at all.
        let text = DeckExporter.ydkText(for: seeded)
        #expect(!text.contains(seeded.name))
        #expect(!text.contains("Lockdown"))
    }
}
