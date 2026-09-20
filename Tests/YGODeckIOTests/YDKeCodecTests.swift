import Foundation
import Testing
@testable import YGODeckIO

@Suite("YDKe codec")
struct YDKeCodecTests {
    /// The example published with the format, which decodes to real cards:
    /// Sky Striker Ace - Raye and Roze.
    private let publishedExample = "ydke://y+iNAd3uOQI=!/rTFAw==!3e45Ag==!"

    /// Evidence for R5.AC6: the published example decodes to the passcodes it
    /// is documented to carry. Little-endian, standard base64 with padding.
    @Test func decodesThePublishedExampleIntoItsPasscodes() throws {
        let list = try YDKeCodec.decode(publishedExample)

        #expect(list.main == [26077387, 37351133])
        #expect(list.extra == [63288574])
        #expect(list.side == [37351133])
        #expect(list.totalCount == 4)
    }

    /// Evidence for R6.AC2: a link this application writes decodes back to what
    /// it was given, and matches what the published encoding produces.
    @Test func encodedLinkDecodesBackToTheSamePasscodes() throws {
        let original = try YDKeCodec.decode(publishedExample)

        // Re-encoding the published example must reproduce it byte for byte.
        #expect(YDKeCodec.encode(original) == publishedExample)

        // And an arbitrary deck survives the round trip with its order intact.
        let deck = DeckList(
            main: [55144522, 55144522, 46986414, 89631139],
            extra: [23995346],
            side: [83555667, 83555667])
        let link = YDKeCodec.encode(deck)
        #expect(link.hasPrefix("ydke://"))
        #expect(link.hasSuffix("!"))
        #expect(try YDKeCodec.decode(link) == deck)

        // An empty deck is a valid link with three empty sections.
        let empty = YDKeCodec.encode(DeckList())
        #expect(empty == "ydke://!!!")
        #expect(try YDKeCodec.decode(empty).isEmpty)
    }

    /// A link that arrived damaged must be refused rather than half-read.
    @Test func refusesLinksThatArrivedDamaged() {
        #expect(throws: DeckInterchangeError.notAYDKeLink) {
            try YDKeCodec.decode("https://example.com/deck")
        }

        // A section lost in transit leaves too few separators.
        #expect(throws: DeckInterchangeError.self) {
            try YDKeCodec.decode("ydke://y+iNAd3uOQI=!/rTFAw==!")
        }

        // Bytes that do not divide into whole passcodes.
        #expect(throws: DeckInterchangeError.self) {
            try YDKeCodec.decode("ydke://y+iN!!!")
        }

        // Not base64 at all.
        #expect(throws: DeckInterchangeError.self) {
            try YDKeCodec.decode("ydke://***!!!")
        }
    }
}
