import Foundation
import Testing
@testable import YGOCore

@Suite("Shortfall")
struct ShortfallTests {
    private static let at = Date(timeIntervalSince1970: 1_758_000_000)

    private func deck(_ slots: [DeckSlot]) -> Deck {
        Deck(id: 1, name: "Prova", format: .goat, slots: slots,
             createdAt: Self.at, updatedAt: Self.at)
    }

    private func slot(_ card: Int, section: DeckSection = .main,
                      quantity: Int = 1, artwork: Int? = nil) -> DeckSlot {
        DeckSlot(artwork: ArtworkIdentifier(artwork ?? card), card: CardIdentifier(card),
                 section: section, quantity: quantity)
    }

    private let names: [CardIdentifier: String] = [
        CardIdentifier(1): "Ash Blossom & Joyous Spring",
        CardIdentifier(2): "Harpie Lady 1",
        CardIdentifier(3): "Harpie Lady 2",
        CardIdentifier(4): "Pot of Greed",
    ]

    /// Evidence for R5.AC1: the answer is a number to act on, not a flag.
    @Test func reportsHowManyMoreCopiesADeckNeeds() {
        let result = ShortfallCalculator.shortfall(
            deck: deck([slot(1, quantity: 3)]),
            names: names,
            owned: [CardIdentifier(1): 1])

        #expect(result.count == 1)
        let entry = result[0]
        #expect(entry.card == CardIdentifier(1))
        #expect(entry.required == 3)
        #expect(entry.owned == 1)
        #expect(entry.missing == 2)
        #expect(entry.sentence.contains("Ash Blossom"))
        #expect(entry.sentence.contains("2"))
    }

    /// Evidence for R5.AC2: a card is a card, whichever printing it came in.
    @Test func countsOwnedCopiesAcrossEveryPrinting() {
        // Two printings, one copy each, already summed per card by the caller.
        let satisfied = ShortfallCalculator.shortfall(
            deck: deck([slot(1, quantity: 2)]),
            names: names,
            owned: [CardIdentifier(1): 2])
        #expect(satisfied.isEmpty,
                "due copie su due stampe diverse soddisfano una richiesta di due")

        // The deck asking for the same card under two artworks is still one card.
        let acrossArtworks = ShortfallCalculator.required(in: deck([
            slot(1, quantity: 2, artwork: 1),
            slot(1, quantity: 1, artwork: 999),
        ]))
        #expect(acrossArtworks[CardIdentifier(1)] == 3,
                "due stampe della stessa carta sono tre copie di una carta sola")

        let short = ShortfallCalculator.shortfall(
            deck: deck([slot(1, quantity: 3)]), names: names, owned: [CardIdentifier(1): 2])
        #expect(short.first?.missing == 1)
    }

    /// Evidence for R5.AC3.
    @Test func reportsNothingMissingForAFullyOwnedDeck() {
        let result = ShortfallCalculator.shortfall(
            deck: deck([slot(1, quantity: 3), slot(4, quantity: 1)]),
            names: names,
            owned: [CardIdentifier(1): 3, CardIdentifier(4): 2])

        #expect(result.isEmpty)

        // Owning exactly enough is enough; owning more is not a problem either.
        let exact = ShortfallCalculator.shortfall(
            deck: deck([slot(1, quantity: 3)]), names: names, owned: [CardIdentifier(1): 3])
        #expect(exact.isEmpty)
    }

    /// Evidence for R5.AC4: a side deck copy is a copy you have to own.
    @Test func countsEverySectionOfTheDeck() {
        let result = ShortfallCalculator.shortfall(
            deck: deck([
                slot(1, section: .main, quantity: 1),
                slot(1, section: .side, quantity: 1),
            ]),
            names: names,
            owned: [CardIdentifier(1): 1])

        #expect(result.count == 1)
        #expect(result[0].required == 2, "main e side contano insieme")
        #expect(result[0].missing == 1)

        // The extra deck counts too.
        let allThree = ShortfallCalculator.shortfall(
            deck: deck([
                slot(1, section: .main, quantity: 1),
                slot(1, section: .extra, quantity: 1),
                slot(1, section: .side, quantity: 1),
            ]),
            names: names, owned: [:])
        #expect(allThree[0].required == 3)
    }

    /// Evidence for R5.AC5: owning none means needing all of them.
    @Test func reportsTheFullCountForACardOwnedNotAtAll() {
        let result = ShortfallCalculator.shortfall(
            deck: deck([slot(4, quantity: 3)]), names: names, owned: [:])

        #expect(result.count == 1)
        #expect(result[0].owned == 0)
        #expect(result[0].missing == 3, "tre, non due")
        #expect(result[0].sentence.contains("non ne hai"))

        // A collection that knows about other cards but not this one is the
        // same case as an empty one.
        let elsewhere = ShortfallCalculator.shortfall(
            deck: deck([slot(4, quantity: 3)]), names: names, owned: [CardIdentifier(1): 9])
        #expect(elsewhere[0].missing == 3)
    }

    /// Evidence for R5.AC6: asking a question does not change the answer.
    @Test func leavesTheDeckAndTheCollectionUnchanged() {
        let original = deck([slot(1, quantity: 3), slot(2, quantity: 2)])
        let owned: [CardIdentifier: Int] = [CardIdentifier(1): 1]

        let first = ShortfallCalculator.shortfall(deck: original, names: names, owned: owned)
        let second = ShortfallCalculator.shortfall(deck: original, names: names, owned: owned)

        #expect(original.slots.count == 2)
        #expect(original.count(in: .main) == 5)
        #expect(owned == [CardIdentifier(1): 1])
        #expect(first == second, "la stessa domanda deve dare la stessa risposta")
    }

    /// The assertion this whole calculation exists to make.
    ///
    /// Deck validation groups `Harpie Lady 1` and `2` under one allowance, and
    /// reusing that tally here would have been less code. It would also have
    /// told the user to go and play with a deck they cannot build: owning three
    /// of one is not owning any of the other.
    @Test func doesNotSatisfyOneCardWithAnotherSharingItsLimit() {
        let harpieOne = CardIdentifier(2)
        let harpieTwo = CardIdentifier(3)

        let result = ShortfallCalculator.shortfall(
            deck: deck([slot(2, quantity: 3)]),
            names: names,
            owned: [harpieTwo: 3])

        #expect(result.count == 1)
        #expect(result[0].card == harpieOne)
        #expect(result[0].owned == 0, "possedere Harpie Lady 2 non è possedere Harpie Lady 1")
        #expect(result[0].missing == 3)
        #expect(result[0].cardName == "Harpie Lady 1")

        // Owning the card the deck actually lists does satisfy it.
        let correct = ShortfallCalculator.shortfall(
            deck: deck([slot(2, quantity: 3)]), names: names, owned: [harpieOne: 3])
        #expect(correct.isEmpty)
    }

    /// The worst shortfall leads, so the list reads as a shopping order.
    @Test func ordersByHowManyAreMissing() {
        let result = ShortfallCalculator.shortfall(
            deck: deck([slot(1, quantity: 3), slot(4, quantity: 2), slot(2, quantity: 1)]),
            names: names,
            owned: [CardIdentifier(1): 2, CardIdentifier(4): 0, CardIdentifier(2): 0])

        #expect(result.map(\.missing) == [2, 1, 1])
        #expect(result[0].card == CardIdentifier(4))
        // Ties break by name so the order is stable between runs.
        #expect(result[1].cardName < result[2].cardName)
    }

    /// A card the collection has never heard of reads as a name, not a number.
    @Test func namesACardTheLookupDoesNotCover() {
        let result = ShortfallCalculator.shortfall(
            deck: deck([slot(99, quantity: 1)]), names: [:], owned: [:])

        #expect(result.count == 1)
        #expect(result[0].cardName == "Carta 99")
        #expect(!result[0].sentence.isEmpty)
    }
}
