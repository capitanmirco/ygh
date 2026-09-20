import Foundation
import Testing
@testable import YGOCore

@Suite("Deck model")
struct DeckModelTests {
    private static let createdAt = Date(timeIntervalSince1970: 1_758_000_000)

    /// Evidence for R1.AC1: a new deck carries what was chosen for it and
    /// nothing else.
    @Test func newDeckHasChosenNameFormatAndThreeEmptySections() {
        let deck = Deck(
            id: 1, name: "Lockdown Burn", format: .goat,
            createdAt: Self.createdAt, updatedAt: Self.createdAt)

        #expect(deck.name == "Lockdown Burn")
        #expect(deck.format == .goat)
        #expect(deck.totalCount == 0)

        for section in DeckSection.allCases {
            #expect(deck.count(in: section) == 0)
            #expect(deck.slots(in: section).isEmpty)
        }

        #expect(deck.folderID == nil)
        #expect(deck.notes == nil)
    }

    /// Evidence for NFR5: a violation carries the numbers behind it, so the
    /// interface renders a sentence and a screen reader reads one, without the
    /// rules module knowing about either.
    @Test func violationDescribesCardHeldCountAndPermittedCount() {
        let overLimit = DeckViolation.overCopyLimit(
            limitName: "Harpie Lady", held: 4, permitted: 1,
            because: .banStatus(.limited))

        let sentence = overLimit.sentence
        #expect(sentence.contains("Harpie Lady"))
        #expect(sentence.contains("4"))
        #expect(sentence.contains("1"))
        #expect(sentence.contains("limitata"))

        // The absolute ceiling reads differently: it is not a ban list at work.
        let absolute = DeckViolation.overCopyLimit(
            limitName: "Mystical Space Typhoon", held: 4, permitted: 3,
            because: .absoluteLimit)
        #expect(absolute.sentence.contains("sempre"))
        #expect(!absolute.sentence.contains("limitata"))

        // A size problem names the section and which bound it broke.
        let tooFew = DeckViolation.sectionSize(section: .main, held: 39, permitted: 40...60)
        #expect(tooFew.sentence.contains("Deck principale"))
        #expect(tooFew.sentence.contains("39"))
        #expect(tooFew.sentence.contains("minimo"))

        let tooMany = DeckViolation.sectionSize(section: .side, held: 16, permitted: 0...15)
        #expect(tooMany.sentence.contains("Side Deck"))
        #expect(tooMany.sentence.contains("massimo"))

        // A misplaced card is named, and the wording distinguishes the two
        // directions of the mistake.
        let inMain = DeckViolation.misplacedCard(
            card: CardIdentifier(1), cardName: "Blue-Eyes Ultimate Dragon", section: .main)
        #expect(inMain.sentence.contains("Blue-Eyes Ultimate Dragon"))
        #expect(inMain.sentence.contains("Extra Deck"))

        let inExtra = DeckViolation.misplacedCard(
            card: CardIdentifier(2), cardName: "Pot of Greed", section: .extra)
        #expect(inExtra.sentence.contains("Pot of Greed"))
        #expect(inExtra.sentence.contains("non può"))

        let outside = DeckViolation.outsideFormatPool(
            card: CardIdentifier(3), cardName: "Accesscode Talker", format: .goat)
        #expect(outside.sentence.contains("Accesscode Talker"))
        #expect(outside.sentence.contains("GOAT"))
    }

    /// Slots are keyed by artwork, so two printings of one card are two slots
    /// that nonetheless describe the same card.
    @Test func slotsCountCopiesPerSectionAcrossPrintings() {
        let card = CardIdentifier(46986414)
        let deck = Deck(
            id: 1, name: "Dark Magician", format: .tcg,
            slots: [
                DeckSlot(artwork: ArtworkIdentifier(46986414), card: card,
                         section: .main, quantity: 2),
                DeckSlot(artwork: ArtworkIdentifier(36996508), card: card,
                         section: .main, quantity: 1),
                DeckSlot(artwork: ArtworkIdentifier(46986414), card: card,
                         section: .side, quantity: 1),
            ],
            createdAt: Self.createdAt, updatedAt: Self.createdAt)

        #expect(deck.count(in: .main) == 3)
        #expect(deck.count(in: .side) == 1)
        #expect(deck.count(in: .extra) == 0)
        #expect(deck.totalCount == 4)
        #expect(deck.slots(in: .main).count == 2)
    }

    /// The section ranges are the rules themselves, so they are asserted rather
    /// than left implicit in the validator.
    @Test func sectionsCarryTheirOwnPermittedRange() {
        #expect(DeckSection.main.permittedRange == 40...60)
        #expect(DeckSection.extra.permittedRange == 0...15)
        #expect(DeckSection.side.permittedRange == 0...15)
    }

    /// The index answers by card and reports how many distinct cards it holds,
    /// which is what bounds the cost of validating.
    @Test func cardIndexAnswersByCardIdentifier() {
        let entry = DeckCardIndex.Entry(
            card: CardIdentifier(55144522), name: "Pot of Greed",
            limitName: "Pot of Greed", frame: .spell,
            formats: [.goat, .tcg], banStatus: .forbidden)
        let index = DeckCardIndex(entries: [entry])

        #expect(index[CardIdentifier(55144522)]?.name == "Pot of Greed")
        #expect(index[CardIdentifier(55144522)]?.banStatus == .forbidden)
        #expect(index[CardIdentifier(1)] == nil)
        #expect(index.count == 1)
    }
}
