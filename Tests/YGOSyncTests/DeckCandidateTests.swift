import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

@MainActor
@Suite("Deck candidates")
struct DeckCandidateTests {
    private func rig() throws -> (DatabaseQueue, SQLiteDeckRepository, SQLiteCardRepository) {
        let (database, repository) = try RealDeck.seededRepository()
        return (database, repository, SQLiteCardRepository(database: database))
    }

    private func editor(
        _ repository: SQLiteDeckRepository, _ catalogue: SQLiteCardRepository
    ) -> DeckEditorViewModel {
        DeckEditorViewModel(
            repository: repository, validator: DeckValidator(), catalogue: catalogue)
    }

    /// Evidence for R1.AC1: the editor opened on an empty candidate list until
    /// something was typed, which is the wrong way round — you search the
    /// catalogue to find out what to add, not to confirm what you knew.
    @Test func offersCardsWithoutBeingAskedOnOpening() async throws {
        let (_, repository, catalogue) = try rig()
        let deck = try await repository.createDeck(name: "Nuovo", format: .tcg)

        let model = editor(repository, catalogue)
        #expect(model.candidates.isEmpty)

        await model.load(deckID: deck.id)

        #expect(!model.candidates.isEmpty)
        #expect(model.catalogueQuery.isEmpty)
        #expect(model.candidates.count <= DeckEditorViewModel.candidateLimit)
        #expect(model.canAddCards)
    }

    /// Evidence for R1.AC2: candidates follow the text without a submit, and
    /// emptying the field goes back to offering the pool.
    @Test func narrowsCandidatesOnEveryChangeWithoutSubmitting() async throws {
        let (_, repository, catalogue) = try rig()
        let deck = try await repository.createDeck(name: "Nuovo", format: .tcg)
        let model = editor(repository, catalogue)
        await model.load(deckID: deck.id)

        let unnarrowed = model.candidates.count
        #expect(unnarrowed > 0)

        model.catalogueQuery = "dragon"
        await model.searchCatalogue()
        let narrowed = model.candidates
        #expect(narrowed.allSatisfy {
            $0.englishName.lowercased().contains("dragon")
                || $0.englishEffect.lowercased().contains("dragon")
        })

        // A narrower query narrows further rather than starting over.
        model.catalogueQuery = "zzzzzz"
        await model.searchCatalogue()
        #expect(model.candidates.isEmpty)

        // Clearing returns to the pool, not to nothing.
        model.catalogueQuery = ""
        await model.searchCatalogue()
        #expect(model.candidates.count == unnarrowed)
    }

    /// Evidence for R1.AC3: a GOAT deck cannot hold a card printed after 2005.
    /// Offering one would be inviting a violation the editor would then report.
    @Test func offersOnlyCardsLegalInTheDecksFormat() async throws {
        let (_, repository, catalogue) = try rig()

        let tcg = try await repository.createDeck(name: "Moderno", format: .tcg)
        let tcgModel = editor(repository, catalogue)
        await tcgModel.load(deckID: tcg.id)
        let tcgCandidates = Set(tcgModel.candidates.map(\.id))

        let goat = try await repository.createDeck(name: "Retro", format: .goat)
        let goatModel = editor(repository, catalogue)
        await goatModel.load(deckID: goat.id)

        #expect(!goatModel.candidates.isEmpty)
        #expect(goatModel.candidates.allSatisfy { $0.formats.contains(.goat) })

        // The two pools are genuinely different, so the filter is doing work.
        let goatCandidates = Set(goatModel.candidates.map(\.id))
        #expect(goatCandidates != tcgCandidates)
    }

    /// Evidence for R1.AC4: placement follows the validator's own rule, so a
    /// card the editor puts somewhere is never then reported for being there.
    @Test func placesACardInTheSectionItsTypeBelongsIn() async throws {
        let (_, repository, catalogue) = try rig()
        let deck = try await repository.createDeck(name: "Nuovo", format: .tcg)
        let model = editor(repository, catalogue)
        await model.load(deckID: deck.id)

        let extraDeckCard = try #require(
            model.candidates.first { $0.frame.belongsInExtraDeck })
        let mainDeckCard = try #require(
            model.candidates.first { !$0.frame.belongsInExtraDeck })

        await model.add(extraDeckCard)
        await model.add(mainDeckCard)

        let extraItem = try #require(model.items.first { $0.card == extraDeckCard.id })
        let mainItem = try #require(model.items.first { $0.card == mainDeckCard.id })
        #expect(extraItem.section == .extra)
        #expect(mainItem.section == .main)

        // Neither card is reported as misplaced, which is the point of using
        // the validator's rule rather than a second one.
        let misplaced = (model.legality?.violations ?? []).filter {
            if case .misplacedCard = $0 { return true }
            return false
        }
        #expect(misplaced.isEmpty)

        // An explicit section still wins over the default.
        await model.add(mainDeckCard, to: .side)
        #expect(model.items.contains { $0.card == mainDeckCard.id && $0.section == .side })
    }
}
