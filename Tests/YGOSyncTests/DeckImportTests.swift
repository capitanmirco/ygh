import Foundation
import GRDB
import Testing
import YGOCore
import YGODeckIO
import YGOPersistence
import YGOValidation
@testable import YGOSync

@Suite("Deck import")
struct DeckImportTests {
    private func importer() throws -> (SQLiteDeckRepository, DeckImporter) {
        let (_, repository) = try RealDeck.seededRepository()
        return (repository, DeckImporter(repository: repository, validator: DeckValidator()))
    }

    private func fileURL(_ name: String) -> URL {
        RealDeck.root.appending(path: "fixtures/\(name).ydk")
    }

    /// Evidence for R5.AC2: a real file references an alternate artwork, and
    /// the deck that comes back holds the card it depicts rather than a hole.
    @Test func resolvesAlternateArtworkPasscodeFromARealDeckFile() async throws {
        let (repository, importer) = try importer()

        let result = try await importer.importFile(at: fileURL("Lockdown Burn"))

        #expect(result.deck.count(in: .main) == 40)
        #expect(result.isComplete, "nessun passcode doveva restare irrisolto")

        // 83555667 is an alternate artwork of Ring of Destruction; the deck
        // must hold that card, and the slot must keep the printing the file
        // named rather than the card's primary one.
        let alternate = ArtworkIdentifier(83_555_667)
        let slot = try #require(result.deck.slots.first { $0.artwork == alternate })
        let resolved = try #require(try await repository.resolveArtwork(alternate))
        #expect(slot.card == resolved)
        #expect(slot.artwork.rawValue != slot.card.rawValue,
                "questa stampa ha un codice diverso dalla carta: è il caso che rompe un importatore ingenuo")
    }

    /// Evidence for R5.AC3: one unknown passcode costs that card, not the deck.
    @Test func importsKnownCardsAndReportsTheUnresolvedPasscode() async throws {
        let (_, importer) = try importer()
        let known = try YDKFile.read(contentsOf: fileURL("Lockdown Burn"))

        var withGhost = known
        withGhost.main.append(999_999_999)
        withGhost.side.append(999_999_998)
        let link = YDKeCodec.encode(withGhost)

        let result = try await importer.importLink(link, named: "Con fantasmi")

        #expect(result.deck.count(in: .main) == known.main.count)
        #expect(result.deck.count(in: .side) == 0)
        #expect(result.unresolvedPasscodes.sorted() == [999_999_998, 999_999_999])
        #expect(!result.isComplete)
    }

    /// Evidence for R5.AC4: the file records no name, so its own is all there is.
    @Test func namesTheDeckAfterItsFile() async throws {
        let (_, importer) = try importer()

        for name in RealDeck.names {
            let result = try await importer.importFile(at: fileURL(name))
            #expect(result.deck.name == name)
        }
    }

    /// Evidence for R5.AC5: a `.ydk` carries no format. Both of these decks are
    /// GOAT decks; proposing TCG would open them covered in violations they do
    /// not really have.
    @Test func proposesTheFormatWithFewestViolations() async throws {
        let (repository, importer) = try importer()
        let validator = DeckValidator()

        for name in RealDeck.names {
            let result = try await importer.importFile(at: fileURL(name))

            #expect(result.proposedFormat == .goat,
                    "\(name) è un mazzo GOAT, proposto \(result.proposedFormat.rawValue)")
            #expect(result.deck.format == .goat, "il mazzo deve essere salvato nel formato proposto")

            // And in that format it really is clean.
            let index = try await repository.cardIndex(for: result.deck)
            let violations = validator.violations(in: result.deck, using: index)
            #expect(violations.isEmpty, "\(name): \(violations.map(\.sentence))")
        }
    }

    /// Evidence for R5.AC7: a damaged link leaves the library exactly as it was.
    @Test func malformedInputStoresNoDeck() async throws {
        let (repository, importer) = try importer()
        let before = try await repository.allDecks().count

        let damaged = [
            "ydke://y+iNAd3uOQI=!/rTFAw==!",   // una sezione persa
            "ydke://y+iN!!!",                   // byte troncati
            "https://example.com/deck",         // non è affatto un link ydke
            "ydke://***!!!",                    // non è base64
        ]

        for link in damaged {
            await #expect(throws: DeckInterchangeError.self) {
                _ = try await importer.importLink(link, named: "Rotto")
            }
        }

        let after = try await repository.allDecks().count
        #expect(after == before, "un import fallito non deve lasciare mazzi dietro di sé")
    }
}
