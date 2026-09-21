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
@Suite("Deck authoring budgets")
struct DeckAuthoringBudgetTests {
    /// A seventy-card deck, because duplicating one is the operation with the
    /// most rows to move and the one a user would notice.
    private func fullDeck() async throws -> (DatabaseQueue, SQLiteDeckRepository, Deck) {
        let (database, decks) = try RealDeck.seededRepository()
        let importer = DeckImporter(repository: decks, validator: DeckValidator())
        let deck = try await importer.importFile(
            at: RealDeck.root.appending(path: "fixtures/LR-Chaos Turbo.ydk")).deck
        return (database, decks, deck)
    }

    private func library(_ decks: SQLiteDeckRepository) -> DeckLibraryViewModel {
        DeckLibraryViewModel(repository: decks, listing: decks, library: decks)
    }

    /// Evidence for NFR1: seventy cards is the size that decides whether these
    /// operations feel instant.
    @Test func creatingDuplicatingAndExportingStayUnderTwoHundredMilliseconds() async throws {
        let (_, decks, deck) = try await fullDeck()
        let model = library(decks)
        await model.load()
        #expect(deck.slots.count > 30)

        // One untimed pass so first-use costs stay out of the measurement.
        await model.createDeck(named: "Riscaldamento", format: .tcg)

        var worst: Double = 0

        let createdAt = DispatchTime.now().uptimeNanoseconds
        let created = await model.createDeck(named: "Nuovo", format: .tcg)
        worst = max(worst, Double(DispatchTime.now().uptimeNanoseconds - createdAt) / 1_000_000)
        #expect(created != nil)

        let duplicatedAt = DispatchTime.now().uptimeNanoseconds
        let copy = await model.duplicate(deck.id)
        worst = max(worst, Double(DispatchTime.now().uptimeNanoseconds - duplicatedAt) / 1_000_000)
        #expect(copy != nil)

        let url = FileManager.default.temporaryDirectory
            .appending(path: "budget-\(UUID().uuidString).ydk")
        defer { try? FileManager.default.removeItem(at: url) }
        let exportedAt = DispatchTime.now().uptimeNanoseconds
        #expect(await model.export(deck.id, to: url))
        worst = max(worst, Double(DispatchTime.now().uptimeNanoseconds - exportedAt) / 1_000_000)

        #expect(worst < 200, "worst operation \(worst) ms")
    }

    /// Evidence for NFR2: read back from storage at the moment the view model
    /// reports the write done, rather than trusting it happened first.
    @Test func aWriteIsStoredBeforeItIsReportedDone() async throws {
        let (_, decks, deck) = try await fullDeck()
        let model = library(decks)
        await model.load()

        let created = try #require(await model.createDeck(named: "Durevole", format: .goat))
        // At this instant, with nothing flushed or waited for.
        let storedNow = try #require(try await decks.deck(with: created.id))
        #expect(storedNow.name == "Durevole")
        #expect(storedNow.format == .goat)

        await model.rename(created.id, to: "Rinominato")
        #expect(try await decks.deck(with: created.id)?.name == "Rinominato")

        let copy = try #require(await model.duplicate(deck.id))
        let storedCopy = try #require(try await decks.deck(with: copy.id))
        #expect(storedCopy.slots.count == deck.slots.count)
    }

    /// Evidence for NFR3: after a refusal the list shown must not be ahead of
    /// the list stored, which is the failure that makes a user recreate work
    /// they already have.
    @Test func theListShownIsTheListStoredEvenAfterAFailure() async throws {
        let (_, decks, _) = try await fullDeck()
        let model = library(decks)
        await model.load()

        func storedNames() async throws -> [String] {
            try await decks.allDecks().map(\.name).sorted()
        }

        #expect(model.decks.map(\.name).sorted() == (try await storedNames()))

        // A rename with no name is refused; the list must not change.
        let deck = try #require(model.decks.first)
        await model.rename(deck.id, to: "  ")
        #expect(model.lastFailure != nil)
        #expect(model.decks.map(\.name).sorted() == (try await storedNames()))

        // A refused creation, likewise.
        let refusing = DeckLibraryViewModel(
            repository: RefusingDeckBuilder(inner: decks), listing: decks, library: decks)
        await refusing.load()
        await refusing.createDeck(named: "Mai creato", format: .tcg)
        #expect(refusing.lastFailure != nil)
        #expect(refusing.decks.map(\.name).sorted() == (try await storedNames()))
    }

    /// Evidence for NFR4: local SQL and a local file. Nothing here has an
    /// outbound seam at all.
    @Test func everyOperationCompletesWithNoNetwork() async throws {
        let (_, decks, deck) = try await fullDeck()
        let model = library(decks)
        await model.load()

        let created = try #require(await model.createDeck(named: "Offline", format: .tcg))
        await model.rename(created.id, to: "Ancora offline")
        let copy = try #require(await model.duplicate(deck.id))
        await model.changeFormat(copy.id, to: .goat)

        let url = FileManager.default.temporaryDirectory
            .appending(path: "offline-\(UUID().uuidString).ydk")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(await model.export(created.id, to: url))
        #expect(await model.ydkeLink(for: copy.id) != nil)

        model.requestDeletion(created.id)
        #expect(await model.confirmDeletion())

        #expect(model.lastFailure == nil)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    /// Evidence for NFR5: an operation that reports "true" tells a listener
    /// nothing. Each says what happened.
    @Test func everyOperationReadsAsASentence() async throws {
        let (_, decks, _) = try await fullDeck()
        let model = library(decks)
        await model.load()

        // Failures are sentences naming what failed.
        await model.rename(model.decks[0].id, to: "")
        let renameFailure = try #require(model.lastFailure)
        #expect(renameFailure.count > 15)
        #expect(!renameFailure.hasPrefix("Error"))

        let bare = DeckLibraryViewModel(repository: decks, listing: decks, library: nil)
        await bare.load()
        _ = await bare.duplicate(model.decks[0].id)
        let duplicateFailure = try #require(bare.lastFailure)
        #expect(duplicateFailure.contains("duplicare"))

        // And the default name is a name rather than a placeholder.
        #expect(DeckLibraryViewModel.defaultName == "Nuovo mazzo")
        #expect(!DeckLibraryViewModel.defaultName.isEmpty)
    }
}
