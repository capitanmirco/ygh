import Testing
import YGOCore
@testable import YGOAnalytics

@Suite("Deck breakdown")
struct DeckBreakdownTests {
    /// A deck with a known shape: monsters at three levels, spells, traps,
    /// and an extra section that must stay out of the main figures.
    private func shapedDeck() -> (Deck, DeckCardIndex) {
        var slots: [DeckSlot] = []
        var entries: [DeckCardIndex.Entry] = []

        func add(_ id: Int, _ slot: DeckSlot, _ entry: DeckCardIndex.Entry) {
            slots.append(slot); entries.append(entry)
        }

        // 12 monsters: 3 at level 4, 3 at level 4 again, 3 at level 6, 3 at level 8.
        add(1, Sample.slot(1, quantity: 3),
            Sample.entry(1, frame: .effect, type: "Effect Monster",
                         level: 4, attribute: .dark, race: "Spellcaster"))
        add(2, Sample.slot(2, quantity: 3),
            Sample.entry(2, frame: .normal, type: "Normal Monster",
                         level: 4, attribute: .light, race: "Warrior"))
        add(3, Sample.slot(3, quantity: 3),
            Sample.entry(3, frame: .effect, type: "Effect Monster",
                         level: 6, attribute: .dark, race: "Dragon"))
        add(4, Sample.slot(4, quantity: 3),
            Sample.entry(4, frame: .effect, type: "Effect Monster",
                         level: 8, attribute: .light, race: "Dragon"))

        // 6 spells and 4 traps, none of which has a level.
        add(5, Sample.slot(5, quantity: 6),
            Sample.entry(5, frame: .spell, type: "Normal Spell",
                         level: nil, attribute: nil, race: "Normal"))
        add(6, Sample.slot(6, quantity: 4),
            Sample.entry(6, frame: .trap, type: "Normal Trap",
                         level: nil, attribute: nil, race: "Normal"))

        // 5 fusion monsters in the extra section.
        add(7, Sample.slot(7, section: .extra, quantity: 5),
            Sample.entry(7, frame: .fusion, type: "Fusion Monster",
                         level: 10, attribute: .wind, race: "Machine"))

        return (
            Deck(id: 1, name: "Forma nota", format: .tcg, slots: slots,
                 createdAt: Sample.at, updatedAt: Sample.at),
            DeckCardIndex(entries: entries))
    }

    /// Evidence for R4.AC1: the kinds account for the whole section.
    @Test func typeCountsSumToTheMainSectionSize() {
        let (deck, index) = shapedDeck()
        let main = deck.breakdown(of: .main, using: index)

        #expect(main.totalCards == 22)
        #expect(main.totalCards == deck.count(in: .main))
        #expect(main.monsterCount == 12)
        #expect(main.spellCount == 6)
        #expect(main.trapCount == 4)
        #expect(main.byKind.values.reduce(0, +) == main.totalCards,
                "le categorie devono sommare al totale della sezione")
    }

    /// Evidence for R4.AC2: a curve is about monsters, and a spell has no
    /// level to be counted under.
    @Test func levelCountsCoverOnlyMonstersThatHaveALevel() {
        let (deck, index) = shapedDeck()
        let main = deck.breakdown(of: .main, using: index)

        #expect(main.byLevel[4] == 6, "due carte di livello 4 da tre copie ciascuna")
        #expect(main.byLevel[6] == 3)
        #expect(main.byLevel[8] == 3)
        #expect(main.byLevel.values.reduce(0, +) == main.monsterCount)

        // Spells and traps are nowhere in it, not even under zero.
        #expect(main.byLevel[0] == nil)
        #expect(!main.byLevel.keys.contains(0))

        // The curve reads lowest first.
        #expect(main.levelCurve.map(\.level) == [4, 6, 8])
    }

    /// Evidence for R4.AC3.
    @Test func attributeAndRaceCountsSumToTheCardsCarryingThem() {
        let (deck, index) = shapedDeck()
        let main = deck.breakdown(of: .main, using: index)

        #expect(main.byAttribute[.dark] == 6)
        #expect(main.byAttribute[.light] == 6)
        #expect(main.byAttribute.values.reduce(0, +) == main.monsterCount,
                "gli attributi devono sommare ai mostri che ne hanno uno")

        #expect(main.byRace["Dragon"] == 6)
        #expect(main.byRace["Spellcaster"] == 3)
        #expect(main.byRace["Warrior"] == 3)
        // Spells and traps carry "Normal" as their race, so races span more
        // than monsters alone.
        #expect(main.byRace.values.reduce(0, +) == main.totalCards)
    }

    /// Evidence for R4.AC4: a curve built from distinct cards would be a
    /// different and far less useful chart.
    @Test func countsCopiesRatherThanDistinctCards() {
        let (deck, index) = shapedDeck()
        let main = deck.breakdown(of: .main, using: index)

        // Two distinct level-4 monsters, six copies between them.
        let levelFourCards = deck.slots(in: .main).filter { index[$0.card]?.level == 4 }
        #expect(levelFourCards.count == 2, "due carte distinte")
        #expect(main.byLevel[4] == 6, "ma sei copie")
        #expect(main.byLevel[4] != levelFourCards.count)
    }

    /// Evidence for R4.AC5: the extra deck is never drawn from and never
    /// belongs in a main-section figure.
    @Test func reportsTheExtraSectionApartFromTheMainOne() {
        let (deck, index) = shapedDeck()
        let main = deck.breakdown(of: .main, using: index)
        let extra = deck.breakdown(of: .extra, using: index)

        #expect(extra.totalCards == 5)
        #expect(extra.monsterCount == 5)
        #expect(extra.byLevel[10] == 5)
        #expect(extra.byAttribute[.wind] == 5)

        // And none of it leaked into the main figures.
        #expect(main.byLevel[10] == nil)
        #expect(main.byAttribute[.wind] == nil)
        #expect(main.byRace["Machine"] == nil)
        #expect(main.totalCards + extra.totalCards == deck.totalCount)

        // The side section is empty and reports as such rather than failing.
        let side = deck.breakdown(of: .side, using: index)
        #expect(side.totalCards == 0)
        #expect(side.byKind.isEmpty)
    }
}
