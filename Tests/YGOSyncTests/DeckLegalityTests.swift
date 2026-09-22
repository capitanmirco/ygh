import Foundation
import GRDB
import Testing
import YGOCore
import YGOFeatureDeckBuilder
import YGOPersistence
import YGOValidation
@testable import YGOSync

@MainActor
@Suite("Deck legality")
struct DeckLegalityTests {
    private struct Rig {
        let database: DatabaseQueue
        let decks: SQLiteDeckRepository
        let history: SQLiteBanlistHistory
        let deck: Deck
        let artworks: [ArtworkIdentifier]
        let konamiIDs: [Int]
    }

    /// The deck fixture's catalog, plus three TCG lists: the one the GOAT era
    /// is named for, the one Edison is named for, and a current one.
    private func makeRig(format: CardFormat = .goat) async throws -> Rig {
        let (database, decks) = try RealDeck.seededRepository()
        let cards = try RealDeck.cards()
        let chosen = Array(cards.prefix(4))
        let artworks = try chosen.map { ArtworkIdentifier(try #require($0.cardImages.first).id) }

        // The identifiers the lists are keyed by, read from the catalog the
        // fixture stored rather than invented here.
        let ids = try await database.read { db in
            try artworks.map { artwork in
                try Int.fetchOne(db, sql: """
                    SELECT card.konami_id FROM card
                    JOIN card_artwork ON card_artwork.card_id = card.id
                    WHERE card_artwork.artwork_id = ?
                    """, arguments: [artwork.rawValue]) ?? 0
            }
        }

        let history = SQLiteBanlistHistory(database: database)
        // 2005: the first card is merely limited.
        try history.store(
            PublishedBanlist(effectiveDate: "2005-03-01", statuses: [ids[0]: .limited]),
            format: .tcg, source: "fixture", fetchedAt: .now)
        // 2010: the same card is forbidden, and a second is semi-limited.
        try history.store(
            PublishedBanlist(
                effectiveDate: "2010-03-01",
                statuses: [ids[0]: .forbidden, ids[1]: .semiLimited]),
            format: .tcg, source: "fixture", fetchedAt: .now)
        try history.store(
            PublishedBanlist(effectiveDate: "2026-05-18", statuses: [ids[2]: .forbidden]),
            format: .tcg, source: "fixture", fetchedAt: .now)
        try history.store(
            PublishedBanlist(effectiveDate: "2026-07-01", statuses: [ids[0]: .limited]),
            format: .ocg, source: "fixture", fetchedAt: .now)

        let deck = try await decks.createDeck(name: "Giudicato", format: format)
        return Rig(
            database: database, decks: decks, history: history,
            deck: try #require(try await decks.deck(with: deck.id)),
            artworks: artworks, konamiIDs: ids)
    }

    private func editor(_ rig: Rig) async -> DeckEditorViewModel {
        let model = DeckEditorViewModel(
            repository: rig.decks, validator: DeckValidator(),
            catalogue: SQLiteCardRepository(database: rig.database),
            editing: rig.decks, labels: rig.decks,
            judging: rig.history, lists: rig.history)
        await model.load(deckID: rig.deck.id)
        await model.loadLists()
        return model
    }

    // MARK: - Which list

    /// Evidence for R1.AC2: the era formats are named after a list, and that
    /// is the list they are played under.
    @Test func theEraFormatsImplyTheListTheyAreNamedFor() async throws {
        let rig = try await makeRig()
        let model = await editor(rig)

        #expect(model.impliedList(for: .goat)?.effectiveDate == "2005-03-01")
        #expect(model.impliedList(for: .goat)?.format == .tcg)
        #expect(model.impliedList(for: .edison)?.effectiveDate == "2010-03-01")
        #expect(model.impliedList(for: .edison)?.format == .tcg)
    }

    /// Evidence for R1.AC2: a current format is played under its newest list,
    /// whatever that turns out to be.
    @Test func theCurrentFormatsImplyTheirNewestStoredList() async throws {
        let rig = try await makeRig()
        let model = await editor(rig)

        #expect(model.impliedList(for: .tcg)?.effectiveDate == "2026-05-18")
        #expect(model.impliedList(for: .ocg)?.effectiveDate == "2026-07-01")
        #expect(model.impliedList(for: .ocg)?.format == .ocg)
    }

    /// Evidence for R1.AC3: nothing is an answer.
    @Test func aFormatWithNoPublishedListImpliesNone() async throws {
        let rig = try await makeRig()
        let model = await editor(rig)

        #expect(CardFormat.speedDuel.impliedList == nil)
        #expect(model.impliedList(for: .speedDuel) == nil)
        #expect(model.impliedList(for: .duelLinks) == nil)
        #expect(model.impliedList(for: .commonCharity) == nil)
    }

    // MARK: - The verdict

    /// Evidence for R3.AC1: the totals are counted per status, and unmatched
    /// is counted apart from everything else.
    @Test func theVerdictCountsForbiddenLimitedSemiLimitedAndUnmatched() throws {
        let list = BanlistRevision(
            format: .tcg, effectiveDate: "2010-03-01",
            source: "fixture", fetchedAt: "now", entryCount: 4)
        let verdict = DeckListVerdict(list: list, cards: [
            ListedDeckCard(card: CardIdentifier(1), name: "Uno", held: 1, status: .forbidden),
            ListedDeckCard(card: CardIdentifier(2), name: "Due", held: 1, status: .limited),
            ListedDeckCard(card: CardIdentifier(3), name: "Tre", held: 2, status: .semiLimited),
            ListedDeckCard(card: CardIdentifier(4), name: "Quattro", held: 3, status: nil),
            ListedDeckCard(card: CardIdentifier(5), name: "Cinque", held: 1,
                           status: nil, isMatched: false),
        ])

        #expect(verdict.forbidden == 1)
        #expect(verdict.limited == 1)
        #expect(verdict.semiLimited == 1)
        #expect(verdict.unmatched == 1)
        #expect(verdict.cards.count == 5, "la carta non elencata resta nel conteggio del mazzo")
    }

    /// Evidence for R3.AC2 and R2.AC4: within the list means no card over.
    @Test func aDeckIsWithinTheListOnlyWhenNoCardIsOverItsAllowance() throws {
        let list = BanlistRevision(
            format: .tcg, effectiveDate: "2010-03-01",
            source: "fixture", fetchedAt: "now", entryCount: 1)
        let forbidden = ListedDeckCard(
            card: CardIdentifier(1), name: "Uno", held: 1, status: .forbidden)
        let allowed = ListedDeckCard(
            card: CardIdentifier(2), name: "Due", held: 1, status: .limited)

        #expect(!DeckListVerdict(list: list, cards: [forbidden, allowed]).isWithinList)
        #expect(DeckListVerdict(list: list, cards: [allowed]).isWithinList)
        #expect(DeckListVerdict(list: list, cards: []).isWithinList)

        let over = DeckListVerdict(list: list, cards: [forbidden, allowed]).overAllowance
        #expect(over.map(\.name) == ["Uno"])
    }

    /// Evidence for R2.AC4: holding a forbidden card at all is already over;
    /// one copy of a limited card is exactly what it permits.
    @Test func oneCopyOfAForbiddenCardIsOverButOneCopyOfALimitedIsNot() throws {
        let forbidden = ListedDeckCard(
            card: CardIdentifier(1), name: "Uno", held: 1, status: .forbidden)
        let limited = ListedDeckCard(
            card: CardIdentifier(2), name: "Due", held: 1, status: .limited)
        let twoLimited = ListedDeckCard(
            card: CardIdentifier(3), name: "Tre", held: 2, status: .limited)
        let unmatched = ListedDeckCard(
            card: CardIdentifier(4), name: "Quattro", held: 3, status: nil, isMatched: false)

        #expect(forbidden.isOverAllowance)
        #expect(!limited.isOverAllowance)
        #expect(twoLimited.isOverAllowance)
        #expect(!unmatched.isOverAllowance, "senza abbinamento non c'è un limite da superare")
    }

    /// Evidence for R3.AC4: a verdict that does not name its list is a claim
    /// about nothing in particular.
    @Test func everyVerdictNamesTheListAndTheDateItCameFrom() async throws {
        let rig = try await makeRig()
        let model = await editor(rig)
        try await rig.decks.addCard(artwork: rig.artworks[0], section: .main, to: rig.deck.id)
        await model.load(deckID: rig.deck.id)

        await model.judgeAgainstImpliedList()
        let verdict = try #require(model.verdict)

        #expect(verdict.list.format == .tcg)
        #expect(verdict.list.effectiveDate == "2005-03-01")
        #expect(verdict.listName == "TCG 2005-03-01")
    }
    // MARK: - Judging the open deck

    /// Evidence for R1.AC1 and R1.AC2: a GOAT deck opens judged by the list
    /// GOAT is named for.
    @Test func openingAGoatDeckJudgesItAgainstTheMarch2005List() async throws {
        let rig = try await makeRig(format: .goat)
        try await rig.decks.addCard(artwork: rig.artworks[0], section: .main, to: rig.deck.id)
        try await rig.decks.addCard(artwork: rig.artworks[1], section: .main, to: rig.deck.id)

        let model = await editor(rig)
        #expect(model.canJudge)
        await model.judgeAgainstImpliedList()

        let verdict = try #require(model.verdict)
        #expect(verdict.list.effectiveDate == "2005-03-01")
        #expect(verdict.forbidden == 0, "in GOAT questa carta si gioca")
        #expect(verdict.limited == 1)
        #expect(!model.formatHasNoList)
    }

    /// Evidence for R1.AC5: the same deck, another list, another answer —
    /// which is the whole of "in GOAT si gioca, in Edison è vietata".
    @Test func choosingAnotherListReJudgesWithoutReopeningTheDeck() async throws {
        let rig = try await makeRig(format: .goat)
        try await rig.decks.addCard(artwork: rig.artworks[0], section: .main, to: rig.deck.id)
        try await rig.decks.addCard(artwork: rig.artworks[1], section: .main, to: rig.deck.id)

        let model = await editor(rig)
        await model.judgeAgainstImpliedList()
        #expect(model.verdict?.forbidden == 0)
        #expect(model.verdict?.isWithinList == true)

        let edison = try #require(model.impliedList(for: .edison))
        await model.judge(against: edison)

        let verdict = try #require(model.verdict)
        #expect(verdict.list.effectiveDate == "2010-03-01")
        #expect(verdict.forbidden == 1, "la stessa carta, vietata")
        #expect(verdict.semiLimited == 1)
        #expect(!verdict.isWithinList)
        #expect(verdict.overAllowance.count == 1)
    }

    /// Evidence for R1.AC4: every stored list, grouped and newest first.
    @Test func everyStoredListIsOfferedGroupedByFormatNewestFirst() async throws {
        let rig = try await makeRig()
        let model = await editor(rig)

        #expect(model.availableLists.count == 4)

        let tcg = model.availableLists.filter { $0.format == .tcg }
        #expect(tcg.map(\.effectiveDate) == ["2026-05-18", "2010-03-01", "2005-03-01"])

        let ocg = model.availableLists.filter { $0.format == .ocg }
        #expect(ocg.map(\.effectiveDate) == ["2026-07-01"])

        // Grouped: every list of one format sits together.
        let formats = model.availableLists.map(\.format)
        #expect(formats == formats.sorted { $0.rawValue < $1.rawValue })
    }

    /// Evidence for R1.AC6: asking a question is not an edit. Structural
    /// rather than promised — nothing here holds a writing port.
    @Test func judgingAgainstSixListsLeavesTheDeckExactlyAsItWas() async throws {
        let rig = try await makeRig(format: .goat)
        for artwork in rig.artworks {
            try await rig.decks.addCard(artwork: artwork, section: .main, to: rig.deck.id)
        }

        let model = await editor(rig)
        let before = try #require(model.deck)
        let slotsBefore = Set(before.slots)

        for list in model.availableLists + model.availableLists.reversed() {
            await model.judge(against: list)
        }

        let after = try #require(model.deck)
        #expect(after.format == .goat, "il formato memorizzato non si muove")
        #expect(Set(after.slots) == slotsBefore)
        #expect(after.totalCount == before.totalCount)

        let stored = try #require(try await rig.decks.deck(with: rig.deck.id))
        #expect(stored.format == .goat)
        #expect(Set(stored.slots) == slotsBefore)
    }

    /// Evidence for NFR2: every list judged against is already on disk.
    @Test func judgingReadsOnlyStoredListsAndNeedsNoNetwork() async throws {
        let rig = try await makeRig(format: .edison)
        try await rig.decks.addCard(artwork: rig.artworks[0], section: .main, to: rig.deck.id)

        // No catalogue, no client, no transport: only the two ports.
        let model = DeckEditorViewModel(
            repository: rig.decks, validator: DeckValidator(),
            editing: rig.decks, judging: rig.history, lists: rig.history)
        await model.load(deckID: rig.deck.id)
        await model.loadLists()

        #expect(!model.canAddCards, "nessun catalogo collegato")
        #expect(model.canJudge)

        await model.judgeAgainstImpliedList()
        #expect(model.verdict?.list.effectiveDate == "2010-03-01")
        #expect(model.verdict?.forbidden == 1)
        #expect(model.lastFailure == nil)
    }

    /// Evidence for NFR4: a format nothing covers is told, not guessed.
    @Test func aDeckWhoseFormatHasNoListSaysSoInsteadOfBeingJudged() async throws {
        let rig = try await makeRig(format: .speedDuel)
        try await rig.decks.addCard(artwork: rig.artworks[0], section: .main, to: rig.deck.id)

        let model = await editor(rig)
        await model.judgeAgainstImpliedList()

        #expect(model.formatHasNoList)
        #expect(model.verdict == nil, "nessun verdetto inventato")
        #expect(model.chosenList == nil)

        // The user can still ask a list of their own, and then there is one.
        let tcg = try #require(model.availableLists.first { $0.format == .tcg })
        await model.judge(against: tcg)
        #expect(model.verdict != nil)
        #expect(!model.formatHasNoList)
    }
    // MARK: - Reading it

    /// Evidence for R4.AC2 and NFR3: one sentence per card, carrying all four
    /// things a reader needs, and never a number on its own.
    @Test func eachJudgedCardAnnouncesNameStatusHeldAndPermitted() throws {
        let forbidden = ListedDeckCard(
            card: CardIdentifier(1), name: "Anfora dell'Avidità", held: 1, status: .forbidden)
        #expect(forbidden.announcement == "Anfora dell'Avidità, vietata, 1 in mazzo, 0 consentite")

        let limited = ListedDeckCard(
            card: CardIdentifier(2), name: "Carità Graziosa", held: 2, status: .limited)
        #expect(limited.announcement == "Carità Graziosa, limitata, 2 in mazzo, 1 consentite")

        let semi = ListedDeckCard(
            card: CardIdentifier(3), name: "Tempesta", held: 2, status: .semiLimited)
        #expect(semi.announcement.contains("semi-limitata"))
        #expect(semi.announcement.contains("2 consentite"))

        let unlisted = ListedDeckCard(
            card: CardIdentifier(4), name: "Qualunque", held: 3, status: nil)
        #expect(unlisted.announcement.contains("non elencata"))
        #expect(unlisted.announcement.contains("3 consentite"))

        // An unmatched card claims no allowance at all.
        let unmatched = ListedDeckCard(
            card: CardIdentifier(5), name: "Senza id", held: 1, status: nil, isMatched: false)
        #expect(unmatched.announcement == "Senza id, non abbinabile alla lista, 1 in mazzo")
    }

    /// Evidence for R4.AC1: the panel opens on the model and the selection
    /// walks the judged cards, stopping at both ends.
    @Test func thePanelOpensAndTheSelectionWalksTheJudgedCards() async throws {
        let rig = try await makeRig(format: .goat)
        for artwork in rig.artworks.prefix(3) {
            try await rig.decks.addCard(artwork: artwork, section: .main, to: rig.deck.id)
        }

        let model = await editor(rig)
        #expect(!model.isLegalityVisible)

        await model.showLegality()
        #expect(model.isLegalityVisible)
        let cards = try #require(model.verdict?.cards)
        #expect(cards.count == 3)
        #expect(model.selectedJudgedCard == cards.first?.card)

        model.moveJudgedSelection(by: 1)
        #expect(model.selectedJudgedCard == cards[1].card)
        model.moveJudgedSelection(by: 1)
        #expect(model.selectedJudgedCard == cards[2].card)
        model.moveJudgedSelection(by: 1)
        #expect(model.selectedJudgedCard == cards[2].card, "si ferma in fondo")
        model.moveJudgedSelection(by: -9)
        #expect(model.selectedJudgedCard == cards[0].card, "e in cima")

        model.hideLegality()
        #expect(!model.isLegalityVisible)

        // An editor that cannot judge does not open the panel.
        let portless = DeckEditorViewModel(
            repository: rig.decks, validator: DeckValidator(), editing: rig.decks)
        await portless.load(deckID: rig.deck.id)
        await portless.showLegality()
        #expect(!portless.isLegalityVisible)
    }
}
