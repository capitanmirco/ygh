import Testing
@testable import YGOCore

/// The opening hand is not always five cards, and the difference is not
/// cosmetic: one card is 5.7 percentage points on three copies in forty.
@Suite("Opening hand")
struct OpeningHandTests {
    /// Evidence for R3.AC1: the formats that predate the modern rule deal six
    /// to the player going first. Edison looks modern but is a 2010 event
    /// played under the 2008 rules, so it draws.
    @Test func retroFormatsDealSixCardsOnThePlay() {
        for format in [CardFormat.goat, .ocgGoat, .edison] {
            #expect(format.firstPlayerDraws, "\(format.rawValue) fa pescare chi va primo")
            #expect(OpeningHand.size(format: format, playingFirst: true) == 6)
        }
    }

    /// Evidence for R3.AC2: the modern rule withholds that draw.
    @Test func modernFormatsDealFiveCardsOnThePlay() {
        for format in [CardFormat.tcg, .ocg, .masterDuel] {
            #expect(!format.firstPlayerDraws)
            #expect(OpeningHand.size(format: format, playingFirst: true) == 5)
        }

        // The two rules really do disagree for the same deck.
        #expect(OpeningHand.size(format: .goat, playingFirst: true)
                != OpeningHand.size(format: .tcg, playingFirst: true))
    }

    /// Evidence for R3.AC3: the player going second draws in every format.
    @Test func everyFormatDealsSixCardsOnTheDraw() {
        for format in CardFormat.allCases {
            #expect(OpeningHand.size(format: format, playingFirst: false) == 6,
                    "\(format.rawValue) deve dare 6 carte a chi va secondo")
        }
    }

    /// The hand describes itself, which is what lets a figure state its
    /// assumption without the reader knowing their format's rule.
    @Test func handDescribesWhatItAssumed() {
        let goat = OpeningHand(format: .goat, playingFirst: true)
        #expect(goat.size == 6)
        #expect(goat.description.contains("6"))
        #expect(goat.description.contains("GOAT"))
        #expect(goat.description.contains("primo"))

        let tcgSecond = OpeningHand(format: .tcg, playingFirst: false)
        #expect(tcgSecond.description.contains("secondo"))
        #expect(tcgSecond.description.contains("6"))
    }
}
