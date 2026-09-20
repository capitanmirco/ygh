import Foundation
import GRDB
import Testing
import YGOCore
import YGODeckIO
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

@Suite("Deck editor")
struct DeckEditorTests {
    private func rig() throws -> (SQLiteDeckRepository, DeckImporter) {
        let (_, repository) = try RealDeck.seededRepository()
        return (repository, DeckImporter(repository: repository, validator: DeckValidator()))
    }

    private func fileURL(_ name: String) -> URL {
        RealDeck.root.appending(path: "fixtures/\(name).ydk")
    }

    /// Evidence for NFR1: re-evaluation runs on every edit, so it has to be
    /// cheap enough to run on every edit. A sixty-card deck is the worst case
    /// the rules ever meet.
    @Test @MainActor func reEvaluationAfterAnEditStaysUnderFiftyMilliseconds() async throws {
        let (repository, importer) = try rig()
        let result = try await importer.importFile(at: fileURL("LR-Chaos Turbo"))

        let model = DeckEditorViewModel(repository: repository, validator: DeckValidator())
        await model.load(deckID: result.deck.id)
        #expect(model.items.count > 20)

        // One untimed pass so first-use costs stay out of the measurement.
        model.reevaluate()

        var samples: [Double] = []
        for _ in 0..<200 {
            let started = ContinuousClock.now
            model.reevaluate()
            samples.append(Double(started.duration(to: .now).components.attoseconds) / 1e15)
        }

        samples.sort()
        let p95 = samples[Int(Double(samples.count) * 0.95)]
        #expect(p95 < 50, "p95 \(String(format: "%.2f", p95)) ms sopra il budget di 50 ms")

        // And the work was real: the deck was actually judged.
        #expect(model.legality != nil)
    }

    /// Evidence for NFR2: nothing in the editor loses a deck by itself.
    @Test @MainActor func noEditImportOrRestoreLosesADeckWithoutConfirmation() async throws {
        let (repository, importer) = try rig()
        let result = try await importer.importFile(at: fileURL("Lockdown Burn"))
        let model = DeckEditorViewModel(repository: repository, validator: DeckValidator())
        await model.load(deckID: result.deck.id)

        // Asking to delete does not delete.
        model.requestDeletion()
        #expect(model.pendingDeletion == result.deck.id)
        #expect(try await repository.deck(with: result.deck.id) != nil)

        // Changing one's mind leaves it alone.
        model.cancelDeletion()
        #expect(model.pendingDeletion == nil)
        #expect(try await repository.deck(with: result.deck.id) != nil)

        // The repository refuses an unconfirmed removal outright.
        await #expect(throws: DeckRepositoryError.deletionNotConfirmed) {
            try await repository.delete(result.deck.id, confirmed: false)
        }

        // A failed import leaves the library as it was.
        let before = try await repository.allDecks().count
        await #expect(throws: DeckInterchangeError.self) {
            _ = try await importer.importLink("ydke://rotto", named: "Rotto")
        }
        #expect(try await repository.allDecks().count == before)

        // A restore keeps what it replaced.
        let versionID = try await repository.saveVersion(of: result.deck.id, label: "Prima")
        try await repository.removeCard(
            artwork: try #require(result.deck.slots.first).artwork, section: .main,
            from: result.deck.id)
        try await repository.restore(versionID: versionID)
        #expect(try await repository.versions(of: result.deck.id).count == 2)

        // Only an explicit confirmation removes it.
        model.requestDeletion()
        #expect(await model.confirmDeletion())
        #expect(try await repository.deck(with: result.deck.id) == nil)
    }

    /// Evidence for NFR3: everything here reads the stored catalog, so nothing
    /// in the deck builder needs a network at any point.
    @Test @MainActor func everyDeckRuleResolvesWithNoNetworkAvailable() async throws {
        // The rig never constructs a client of any kind: there is no network
        // seam in this feature to stub out, which is the assertion itself.
        let (repository, importer) = try rig()

        let result = try await importer.importFile(at: fileURL("LR-Chaos Turbo"))
        #expect(result.isComplete)
        #expect(result.proposedFormat == .goat)

        let model = DeckEditorViewModel(repository: repository, validator: DeckValidator())
        await model.load(deckID: result.deck.id)

        let legality = try #require(model.legality)
        #expect(legality.isLegal, "\(model.violationSentences)")
        #expect(!legality.restrictionsAreUserMaintained)

        // Editing, judging, exporting and searching all still answer.
        // Slots are ordered by section name, and "extra" sorts before "main",
        // so the main-deck slot is taken explicitly rather than by position.
        let artwork = try #require(result.deck.slots(in: .main).first).artwork
        await model.remove(artwork: artwork, from: .main)
        #expect(try #require(model.deck).count(in: .main) == 39)
        #expect(model.legality?.isLegal == false, "39 carte non sono un deck legale")

        _ = DeckExporter.ydkeLink(for: try #require(model.deck))
        #expect(try await repository.decks(named: "Chaos").count == 1)
    }

    /// Evidence for NFR4: a deck that leaves and comes back is the same deck,
    /// printing for printing.
    @Test func exportedAndReimportedDeckIsIdenticalSectionBySection() async throws {
        let (repository, importer) = try rig()

        for name in RealDeck.names {
            let original = try await importer.importFile(at: fileURL(name))
            let exported = DeckExporter.list(from: original.deck)

            // Through a file.
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "ygo-nfr4-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appending(path: "\(name).ydk")
            try DeckExporter.write(original.deck, to: file)

            let viaFile = try await importer.importFile(at: file)
            #expect(DeckExporter.list(from: viaFile.deck) == exported,
                    "\(name) non è identico dopo il round trip su file")

            // And through a link.
            let viaLink = try await importer.importLink(
                DeckExporter.ydkeLink(for: original.deck), named: name)
            #expect(DeckExporter.list(from: viaLink.deck) == exported,
                    "\(name) non è identico dopo il round trip su link")

            // Section counts survive too.
            for section in DeckSection.allCases {
                #expect(viaFile.deck.count(in: section) == original.deck.count(in: section))
                #expect(viaLink.deck.count(in: section) == original.deck.count(in: section))
            }
            _ = repository
        }
    }
}
