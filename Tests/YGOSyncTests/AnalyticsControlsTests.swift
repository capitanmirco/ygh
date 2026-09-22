import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureAnalytics
import YGOPersistence
import YGOValidation
@testable import YGOSync

@MainActor
@Suite("Analytics controls")
struct AnalyticsControlsTests {
    private struct Rig {
        let database: DatabaseQueue
        let decks: SQLiteDeckRepository
        let goat: Deck
        let artworks: [ArtworkIdentifier]
    }

    /// A GOAT deck holding three copies of one card, which is enough for a
    /// drawing probability to be worth comparing between two hand sizes.
    private func makeRig(format: CardFormat = .goat) async throws -> Rig {
        let (database, decks) = try RealDeck.seededRepository()
        let cards = try RealDeck.cards()
        let artworks = try cards.prefix(6).map {
            ArtworkIdentifier(try #require($0.cardImages.first).id)
        }

        let deck = try await decks.createDeck(name: "Tuning", format: format)
        for artwork in artworks.prefix(3) {
            for _ in 0..<3 {
                try await decks.addCard(artwork: artwork, section: .main, to: deck.id)
            }
        }
        // Two era lists: the first names nothing this deck holds, the second
        // forbids one of its cards.
        let konami = try await database.read { db in
            try artworks.prefix(3).map { artwork in
                try Int.fetchOne(db, sql: """
                    SELECT card.konami_id FROM card
                    JOIN card_artwork ON card_artwork.card_id = card.id
                    WHERE card_artwork.artwork_id = ?
                    """, arguments: [artwork.rawValue]) ?? 0
            }
        }
        let history = SQLiteBanlistHistory(database: database)
        try history.store(
            PublishedBanlist(effectiveDate: "2005-03-01", statuses: [konami[0]: .semiLimited]),
            format: .tcg, source: "fixture", fetchedAt: .now)
        try history.store(
            PublishedBanlist(effectiveDate: "2010-03-01", statuses: [konami[0]: .forbidden]),
            format: .tcg, source: "fixture", fetchedAt: .now)

        return Rig(
            database: database, decks: decks,
            goat: try #require(try await decks.deck(with: deck.id)),
            artworks: Array(artworks))
    }

    private func measuring(_ rig: Rig) -> AnalyticsViewModel {
        AnalyticsViewModel(
            library: rig.decks,
            judging: SQLiteBanlistHistory(database: rig.database),
            lists: SQLiteBanlistHistory(database: rig.database))
    }

    private func loaded(_ rig: Rig) async throws -> AnalyticsViewModel {
        let model = AnalyticsViewModel()
        let deck = try #require(try await rig.decks.deck(with: rig.goat.id))
        let index = try await rig.decks.cardIndex(for: deck)
        model.load(deck: deck, index: index)
        return model
    }

    /// Evidence for R2.AC1: the same deck, read elsewhere.
    @Test func aDeckCanBeReadAsThoughItWerePlayedInAnotherFormat() async throws {
        let model = try await loaded(try await makeRig())
        #expect(model.readingFormat == .goat)
        #expect(!model.isReadingAnotherFormat)

        model.assume(format: .tcg)
        #expect(model.readingFormat == .tcg)
        #expect(model.deck?.format == .goat, "il mazzo resta quello che è")

        model.assume(format: nil)
        #expect(model.readingFormat == .goat)
        #expect(!model.isReadingAnotherFormat)
    }

    /// Evidence for R2.AC2: the opening hand is where the format reaches the
    /// arithmetic, so the figures have to move with it. GOAT lets the player
    /// going first draw; TCG does not.
    @Test func theAssumedFormatChangesTheOpeningHandAndEveryFigureWithIt() async throws {
        let model = try await loaded(try await makeRig())
        #expect(model.playingFirst)

        let goatHand = try #require(model.hand)
        #expect(goatHand.size == 6)
        let goatOdds = try #require(model.odds.first?.atLeastOne)

        model.assume(format: .tcg)
        let tcgHand = try #require(model.hand)
        #expect(tcgHand.size == 5, "in TCG chi inizia non pesca")
        let tcgOdds = try #require(model.odds.first?.atLeastOne)

        #expect(tcgOdds < goatOdds, "una carta in meno in mano, meno probabilità di aprirla")
        #expect(model.odds.count == 3, "le stesse tre carte distinte")

        // Going second both formats deal six, so the two readings agree again
        // — which is the proof that the hand size is what moved the figures,
        // and not the format by some other route.
        model.setPlayingFirst(false)
        #expect(model.hand?.size == 6)
        let tcgSecondOdds = try #require(model.odds.first?.atLeastOne)

        model.assume(format: .goat)
        #expect(model.hand?.size == 6)
        let goatSecondOdds = try #require(model.odds.first?.atLeastOne)
        #expect(goatSecondOdds == tcgSecondOdds)
        #expect(goatSecondOdds == goatOdds, "sei carte danno la stessa cifra di prima")
    }

    /// Evidence for R2.AC3: a figure that does not state its assumption is a
    /// figure nobody can check.
    @Test func theScreenNamesTheFormatItsFiguresAssume() async throws {
        let model = try await loaded(try await makeRig())

        #expect(model.readingFormat == .goat)
        #expect(!model.isReadingAnotherFormat, "il formato del mazzo non è un'assunzione")

        model.assume(format: .tcg)
        #expect(model.isReadingAnotherFormat)
        #expect(model.readingFormat == .tcg)

        // Assuming the deck's own format is not reading it as another.
        model.assume(format: .goat)
        #expect(!model.isReadingAnotherFormat)
        #expect(model.readingFormat == .goat)
    }

    /// Evidence for R2.AC4: structural, not promised — the only mutated deck
    /// is a local copy.
    @Test func readingADeckInFourFormatsNeverWritesTheDeck() async throws {
        let rig = try await makeRig()
        let model = try await loaded(rig)
        let before = try #require(try await rig.decks.deck(with: rig.goat.id))

        for format in [CardFormat.tcg, .edison, .masterDuel, .ocg] {
            model.assume(format: format)
            #expect(model.readingFormat == format)
        }

        let after = try #require(try await rig.decks.deck(with: rig.goat.id))
        #expect(after.format == .goat)
        #expect(Set(after.slots) == Set(before.slots))
        #expect(model.deck?.format == .goat, "nemmeno la copia in memoria del mazzo")
    }
    // MARK: - Which deck

    /// Evidence for R1.AC1: the chooser holds the library, in its order.
    @Test func everyStoredDeckIsOfferedInTheOrderTheLibraryUses() async throws {
        let rig = try await makeRig()
        _ = try await rig.decks.createDeck(name: "Aggro", format: .tcg)

        let model = AnalyticsViewModel(library: rig.decks)
        #expect(model.canChooseDeck)
        await model.loadDecks()

        #expect(model.decks.map(\.name) == ["Aggro", "Tuning"], "ordinata per nome")
        #expect(!model.libraryIsEmpty)
    }

    /// Evidence for R1.AC2: the figures become about the deck now chosen.
    @Test func choosingAnotherDeckReportsThatDecksFigures() async throws {
        let rig = try await makeRig()
        let small = try await rig.decks.createDeck(name: "Piccolo", format: .goat)
        try await rig.decks.addCard(artwork: rig.artworks[4], section: .main, to: small.id)

        let model = AnalyticsViewModel(library: rig.decks)
        await model.loadDecks()

        await model.choose(deckID: rig.goat.id)
        #expect(model.deck?.totalCount == 9)
        #expect(model.odds.count == 3)

        await model.choose(deckID: small.id)
        #expect(model.deck?.id == small.id)
        #expect(model.deck?.totalCount == 1)
        #expect(model.odds.count == 1, "le cifre sono di questo mazzo, non del precedente")
    }

    /// Evidence for R1.AC3: numbers without a subject are not an answer.
    @Test func theFiguresNameTheDeckTheyDescribe() async throws {
        let rig = try await makeRig()
        let model = AnalyticsViewModel(library: rig.decks)
        await model.start(on: rig.goat.id)

        #expect(model.deck?.name == "Tuning")
        #expect(model.deck?.format == .goat)
    }

    /// Evidence for R1.AC4: nothing to analyse is something to say.
    @Test func anEmptyLibrarySaysSoRatherThanOfferingAnEmptyChooser() async throws {
        let (_, decks) = try RealDeck.seededRepository()
        let model = AnalyticsViewModel(library: decks)

        #expect(!model.libraryIsEmpty, "prima di leggere non si sa")
        await model.loadDecks()

        #expect(model.libraryIsEmpty)
        #expect(model.decks.isEmpty)
        #expect(model.deck == nil)
        #expect(model.odds.isEmpty)
    }

    /// Evidence for R1.AC5: the screen opens on the deck chosen elsewhere.
    @Test func theStatisticsStartOnTheDeckChosenElsewhere() async throws {
        let rig = try await makeRig()
        _ = try await rig.decks.createDeck(name: "Aggro", format: .tcg)

        let model = AnalyticsViewModel(library: rig.decks)
        await model.start(on: rig.goat.id)
        #expect(model.deck?.id == rig.goat.id)
        #expect(model.decks.count == 2, "e la scelta resta possibile")

        // With nothing chosen elsewhere, the library is still read.
        let fresh = AnalyticsViewModel(library: rig.decks)
        await fresh.start(on: nil)
        #expect(fresh.deck == nil)
        #expect(fresh.decks.count == 2)
        #expect(!fresh.libraryIsEmpty)
    }
    // MARK: - Measured against a list

    /// Evidence for R3.AC1: whether the deck can be played there, beside the
    /// odds that say whether it works.
    @Test func theScreenReportsWhetherTheDeckIsWithinTheChosenList() async throws {
        let rig = try await makeRig()
        let model = measuring(rig)
        #expect(model.canMeasure)
        await model.start(on: rig.goat.id)
        await model.measureAgainstImpliedList()

        let verdict = try #require(model.verdict)
        #expect(verdict.list.effectiveDate == "2005-03-01", "GOAT si gioca con quella lista")
        #expect(verdict.semiLimited == 1)
        #expect(!verdict.isWithinList, "tre copie di una semi-limitata sono una di troppo")
        #expect(verdict.overAllowance.count == 1)
    }

    /// Evidence for R3.AC2: a verdict that does not name its list is a claim
    /// about nothing in particular.
    @Test func theVerdictNamesTheListAndItsDate() async throws {
        let rig = try await makeRig()
        let model = measuring(rig)
        await model.start(on: rig.goat.id)
        await model.measureAgainstImpliedList()

        let verdict = try #require(model.verdict)
        #expect(verdict.listName == "TCG 2005-03-01")
        #expect(verdict.list.format == .tcg)
    }

    /// Evidence for R3.AC3: same deck, another list, another answer.
    @Test func changingTheListChangesTheVerdictForTheSameDeck() async throws {
        let rig = try await makeRig()
        let model = measuring(rig)
        await model.start(on: rig.goat.id)
        await model.measureAgainstImpliedList()
        #expect(model.verdict?.forbidden == 0)

        let edison = try #require(
            BanlistRevision.implied(for: .edison, in: model.availableLists))
        await model.measure(against: edison)

        let verdict = try #require(model.verdict)
        #expect(verdict.list.effectiveDate == "2010-03-01")
        #expect(verdict.forbidden == 1, "la stessa carta, vietata")
        #expect(!verdict.isWithinList)
    }

    /// Evidence for R3.AC4: a format nothing covers is told, not guessed.
    @Test func aFormatNoListCoversReportsNoVerdict() async throws {
        let rig = try await makeRig(format: .speedDuel)
        let model = measuring(rig)
        await model.start(on: rig.goat.id)
        await model.measureAgainstImpliedList()

        #expect(model.formatHasNoList)
        #expect(model.verdict == nil, "nessun verdetto inventato")
        #expect(model.chosenList == nil)
    }

    /// Evidence for R3.AC5: measuring is a question.
    @Test func measuringAgainstSeveralListsNeverWritesTheDeck() async throws {
        let rig = try await makeRig()
        let model = measuring(rig)
        await model.start(on: rig.goat.id)
        let before = try #require(try await rig.decks.deck(with: rig.goat.id))

        for list in model.availableLists + model.availableLists.reversed() {
            await model.measure(against: list)
        }

        let after = try #require(try await rig.decks.deck(with: rig.goat.id))
        #expect(after.format == .goat)
        #expect(Set(after.slots) == Set(before.slots))
        #expect(after.totalCount == before.totalCount)
    }
    // MARK: - The dealt hand

    /// Evidence for R4.AC1: the hand comes from the deck now chosen.
    @Test func theHandIsDealtFromTheDeckNowChosen() async throws {
        let rig = try await makeRig()
        let other = try await rig.decks.createDeck(name: "Altro", format: .goat)
        for _ in 0..<5 {
            try await rig.decks.addCard(artwork: rig.artworks[5], section: .main, to: other.id)
        }

        let model = AnalyticsViewModel(library: rig.decks)
        await model.start(on: rig.goat.id)
        model.dealHand(seed: 7)
        let fromFirst = Set(model.dealtHand)
        #expect(!fromFirst.isEmpty)

        await model.choose(deckID: other.id)
        model.dealHand(seed: 7)
        let fromSecond = Set(model.dealtHand)

        #expect(!fromSecond.isEmpty)
        #expect(fromSecond.isDisjoint(with: fromFirst),
                "i due mazzi non condividono carte, e nemmeno le mani")
    }

    /// Evidence for R4.AC2: a stale hand is worse than no hand, because it
    /// looks like evidence.
    @Test func everyChoiceClearsAHandDealtUnderThePreviousOne() async throws {
        let rig = try await makeRig()
        let other = try await rig.decks.createDeck(name: "Altro", format: .goat)
        try await rig.decks.addCard(artwork: rig.artworks[5], section: .main, to: other.id)

        let model = AnalyticsViewModel(library: rig.decks)
        await model.start(on: rig.goat.id)

        model.dealHand(seed: 1)
        #expect(!model.dealtHand.isEmpty)
        model.assume(format: .tcg)
        #expect(model.dealtHand.isEmpty, "cambiare formato azzera la mano")

        model.dealHand(seed: 1)
        #expect(!model.dealtHand.isEmpty)
        model.setPlayingFirst(false)
        #expect(model.dealtHand.isEmpty, "e cambiare ordine di gioco pure")

        model.dealHand(seed: 1)
        #expect(!model.dealtHand.isEmpty)
        await model.choose(deckID: other.id)
        #expect(model.dealtHand.isEmpty, "e cambiare mazzo")
    }

    /// Evidence for R4.AC3: the hand is the size the assumption implies, not
    /// the stored deck's.
    @Test func theHandHoldsWhatTheAssumedFormatAndPlayOrderImply() async throws {
        let rig = try await makeRig()
        let model = try await loaded(rig)

        model.dealHand(seed: 3)
        #expect(model.dealtHand.count == 6, "GOAT, chi inizia pesca")

        model.assume(format: .tcg)
        model.dealHand(seed: 3)
        #expect(model.dealtHand.count == 5, "TCG, chi inizia non pesca")

        model.setPlayingFirst(false)
        model.dealHand(seed: 3)
        #expect(model.dealtHand.count == 6, "chi va secondo pesca sempre")

        model.assume(format: .goat)
        model.dealHand(seed: 3)
        #expect(model.dealtHand.count == 6)
    }

    /// Evidence for NFR1: every figure states what it was computed under.
    @Test func everyFigureStatesTheDeckTheFormatAndThePlayOrder() async throws {
        let rig = try await makeRig()
        let model = measuring(rig)
        await model.start(on: rig.goat.id)
        await model.measureAgainstImpliedList()

        #expect(model.deck?.name == "Tuning")
        #expect(model.readingFormat == .goat)
        #expect(model.playingFirst)
        let hand = try #require(model.hand)
        #expect(hand.size == 6)
        #expect(hand.format == .goat)
        #expect(hand.playingFirst)
        #expect(model.verdict?.listName == "TCG 2005-03-01")

        // Read elsewhere, every one of those statements follows.
        model.assume(format: .tcg)
        #expect(model.isReadingAnotherFormat)
        #expect(model.hand?.format == .tcg)
        #expect(model.hand?.size == 5)
        #expect(model.deck?.format == .goat, "il mazzo resta GOAT")
    }
}
