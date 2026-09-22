import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

/// Refuses on demand, so "reported and left as it was" is observable.
private final class LabellingStub: DeckLabelling, @unchecked Sendable {
    private let lock = NSLock()
    private let wrapped: any DeckLabelling
    private var refuse = false

    init(wrapping wrapped: any DeckLabelling) { self.wrapped = wrapped }

    func startRefusing() { lock.withLock { refuse = true } }
    private var isRefusing: Bool { lock.withLock { refuse } }

    func changeFormat(_ deckID: Int64, to format: CardFormat) async throws {
        if isRefusing { throw DeckHistoryError.versionNotFound(-1) }
        try await wrapped.changeFormat(deckID, to: format)
    }

    func addTag(_ name: String, to deckID: Int64) async throws {
        if isRefusing { throw DeckHistoryError.versionNotFound(-1) }
        try await wrapped.addTag(name, to: deckID)
    }

    func removeTag(_ name: String, from deckID: Int64) async throws {
        if isRefusing { throw DeckHistoryError.versionNotFound(-1) }
        try await wrapped.removeTag(name, from: deckID)
    }

    func allTags() async throws -> [String] { try await wrapped.allTags() }
}

@MainActor
@Suite("Deck labels")
struct DeckLabelTests {
    private struct Rig {
        let database: DatabaseQueue
        let repository: SQLiteDeckRepository
    }

    private func makeRig() throws -> Rig {
        let (database, repository) = try RealDeck.seededRepository()
        return Rig(database: database, repository: repository)
    }

    private func library(_ rig: Rig, labels: (any DeckLabelling)? = nil) -> DeckLibraryViewModel {
        DeckLibraryViewModel(
            repository: rig.repository, listing: rig.repository,
            library: rig.repository, labels: labels ?? rig.repository)
    }

    /// Evidence for R1.AC3: every format the catalog knows, with the deck's
    /// own identifiable among them.
    @Test func everyFormatIsOfferedWithTheDecksOwnMarked() async throws {
        let rig = try makeRig()
        let model = library(rig)
        let deck = try #require(await model.createDeck(named: "Tuning", format: .goat))
        await model.load()

        #expect(model.offeredFormats == CardFormat.allCases)
        #expect(model.offeredFormats.count == 9)
        #expect(model.offeredFormats.contains(.edison))
        #expect(model.decks.first { $0.id == deck.id }?.format == .goat)
        #expect(model.canLabel)
    }

    /// Evidence for R1.AC4: a refused change costs a message, not the format.
    @Test func aFailedFormatChangeKeepsTheFormatItHad() async throws {
        let rig = try makeRig()
        let stub = LabellingStub(wrapping: rig.repository)
        let model = library(rig, labels: stub)
        let deck = try #require(await model.createDeck(named: "Tuning", format: .goat))

        stub.startRefusing()
        await model.changeFormat(deck.id, to: .edison)

        #expect(model.lastFailure != nil)
        #expect(model.decks.first { $0.id == deck.id }?.format == .goat)
        let stored = try #require(try await rig.repository.deck(with: deck.id))
        #expect(stored.format == .goat)
    }

    /// Evidence for R3.AC1: the list holds the decks carrying the tag.
    @Test func filteringByATagHoldsOnlyTheDecksCarryingIt() async throws {
        let rig = try makeRig()
        let model = library(rig)
        let first = try #require(await model.createDeck(named: "Uno", format: .goat))
        let second = try #require(await model.createDeck(named: "Due", format: .goat))
        _ = try #require(await model.createDeck(named: "Tre", format: .tcg))

        await model.addTag("da testare", to: first.id)
        await model.addTag("DA TESTARE", to: second.id)
        await model.load()

        model.filter(byTag: "da testare")
        #expect(model.visibleDecks.map(\.name).sorted() == ["Due", "Uno"])
        #expect(!model.filterMatchesNothing)

        // The filter is as case-insensitive as the tag it names.
        model.filter(byTag: "Da Testare")
        #expect(model.visibleDecks.count == 2)
    }

    /// Evidence for R3.AC2: clearing gives back the whole list, in its order.
    @Test func clearingTheFilterRestoresTheWholeListInOrder() async throws {
        let rig = try makeRig()
        let model = library(rig)
        let first = try #require(await model.createDeck(named: "Zoodiac", format: .goat))
        _ = try #require(await model.createDeck(named: "Aggro", format: .goat))
        await model.addTag("provato", to: first.id)
        await model.load()

        let whole = model.decks.map(\.name)
        #expect(whole == ["Aggro", "Zoodiac"], "ordinata per nome")

        model.filter(byTag: "provato")
        #expect(model.visibleDecks.map(\.name) == ["Zoodiac"])

        model.filter(byTag: nil)
        #expect(model.visibleDecks.map(\.name) == whole)
    }

    /// Evidence for R3.AC3: a shorter list is not an explanation.
    @Test func theModelSaysWhichTagItIsFilteringBy() async throws {
        let rig = try makeRig()
        let model = library(rig)
        let deck = try #require(await model.createDeck(named: "Uno", format: .goat))
        await model.addTag("edison", to: deck.id)
        await model.load()
        await model.loadTags()

        #expect(model.tagFilter == nil)
        model.filter(byTag: "edison")
        #expect(model.tagFilter == "edison")
        #expect(model.availableTags == ["edison"])

        model.filter(byTag: nil)
        #expect(model.tagFilter == nil)
    }

    /// Evidence for R3.AC4: nothing matched is a different thing from nothing
    /// exists, and the interface has to be able to tell them apart.
    @Test func aFilterThatMatchesNothingIsNotAnEmptyLibrary() async throws {
        let rig = try makeRig()
        let model = library(rig)
        _ = try #require(await model.createDeck(named: "Uno", format: .goat))
        await model.load()

        model.filter(byTag: "mai usata")
        #expect(model.visibleDecks.isEmpty)
        #expect(model.filterMatchesNothing, "filtro che non trova nulla")

        model.filter(byTag: nil)
        #expect(!model.filterMatchesNothing)

        // An empty library is not a filter that matched nothing.
        let empty = DeckLibraryViewModel(
            repository: rig.repository, listing: rig.repository, labels: rig.repository)
        empty.filter(byTag: "qualsiasi")
        #expect(!empty.filterMatchesNothing)
    }
    // MARK: - From the editor

    private func editor(
        _ rig: Rig, deckID: Int64, labels: (any DeckLabelling)? = nil
    ) async -> DeckEditorViewModel {
        let model = DeckEditorViewModel(
            repository: rig.repository, validator: DeckValidator(),
            catalogue: SQLiteCardRepository(database: rig.database),
            editing: rig.repository, labels: labels ?? rig.repository)
        await model.load(deckID: deckID)
        return model
    }

    /// Evidence for R1.AC1: set in the editor, stored, and read back.
    @Test func theEditorStoresANewFormatAndShowsIt() async throws {
        let rig = try makeRig()
        let deck = try await rig.repository.createDeck(name: "Tuning", format: .goat)
        let model = await editor(rig, deckID: deck.id)
        #expect(model.canLabel)
        #expect(model.deck?.format == .goat)

        await model.changeFormat(to: .edison)
        #expect(model.deck?.format == .edison)

        let stored = try #require(try await rig.repository.deck(with: deck.id))
        #expect(stored.format == .edison)
        #expect(model.lastFailure == nil)
    }

    /// Evidence for R1.AC2: the verdict follows the format without the deck
    /// being reopened. A GOAT-only card is outside Edison's pool.
    @Test func aFormatChangeReJudgesTheDeckWithoutReopeningIt() async throws {
        let rig = try makeRig()
        let deck = try await rig.repository.createDeck(name: "Tuning", format: .goat)
        let model = await editor(rig, deckID: deck.id)

        // Something legal where it stands.
        let card = try #require(model.candidates.first { !$0.frame.belongsInExtraDeck })
        await model.add(card, to: .main)
        let judgedInGoat = try #require(model.legality)

        // GOAT has an upstream ban list; Edison does not, so its restrictions
        // become the user's. That flag is the verdict changing, observably.
        #expect(!judgedInGoat.restrictionsAreUserMaintained)

        await model.changeFormat(to: .edison)
        let judgedAfter = try #require(model.legality)

        #expect(model.deck?.format == .edison)
        #expect(judgedAfter.restrictionsAreUserMaintained,
                "il verdetto è stato rifatto contro il nuovo formato")
        #expect(model.items.count == 1, "nessuna carta è stata rimossa")

        // And back again, so the flag follows the format rather than sticking.
        await model.changeFormat(to: .goat)
        let judgedBack = try #require(model.legality)
        #expect(!judgedBack.restrictionsAreUserMaintained)
    }

    /// Evidence for R2.AC1 and R2.AC2: the deck carries what was added and
    /// stops carrying what was removed.
    @Test func theEditorAddsAndRemovesATagAndTheDeckCarriesIt() async throws {
        let rig = try makeRig()
        let deck = try await rig.repository.createDeck(name: "Tuning", format: .goat)
        let model = await editor(rig, deckID: deck.id)
        #expect(model.tags.isEmpty)

        await model.addTag("  da testare ")
        #expect(model.tags == ["da testare"], "ripulita dagli spazi")
        await model.addTag("DA TESTARE")
        #expect(model.tags == ["da testare"], "una sola, con la prima grafia")

        await model.addTag("edison")
        #expect(model.tags == ["da testare", "edison"])
        await model.loadTags()
        #expect(model.availableTags == ["da testare", "edison"])

        await model.removeTag("da testare")
        #expect(model.tags == ["edison"])

        let stored = try #require(try await rig.repository.deck(with: deck.id))
        #expect(stored.tags == ["edison"])

        // A blank tag is refused without disturbing what is there.
        await model.addTag("   ")
        #expect(model.tags == ["edison"])
    }

    /// Evidence for NFR1: neither label is a card.
    @Test func neitherLabelEverReachesTheDecksCards() async throws {
        let rig = try makeRig()
        let deck = try await rig.repository.createDeck(name: "Tuning", format: .goat)
        let model = await editor(rig, deckID: deck.id)

        let card = try #require(model.candidates.first { !$0.frame.belongsInExtraDeck })
        await model.add(card, to: .main)
        await model.add(card, to: .main)
        let before = Set(try #require(model.deck).slots)
        #expect(!before.isEmpty)

        await model.changeFormat(to: .edison)
        await model.addTag("provato")
        await model.removeTag("provato")
        await model.changeFormat(to: .tcg)

        let after = try #require(model.deck)
        #expect(Set(after.slots) == before)
        #expect(after.totalCount == 2)
    }

    /// Evidence for NFR2: labelling is local state and touches no catalogue
    /// read and no network.
    @Test func labellingNeedsNoNetworkAndNoCatalogueRead() async throws {
        let rig = try makeRig()
        let deck = try await rig.repository.createDeck(name: "Tuning", format: .goat)

        // An editor with no catalogue at all: nothing here may need one.
        let model = DeckEditorViewModel(
            repository: rig.repository, validator: DeckValidator(),
            editing: rig.repository, labels: rig.repository)
        await model.load(deckID: deck.id)

        #expect(!model.canAddCards, "nessun catalogo collegato")
        #expect(model.canLabel)

        await model.addTag("offline")
        await model.changeFormat(to: .edison)

        #expect(model.tags == ["offline"])
        #expect(model.deck?.format == .edison)
        #expect(model.lastFailure == nil)
    }
}
