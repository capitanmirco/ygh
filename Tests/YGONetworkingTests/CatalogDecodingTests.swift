import Foundation
import Testing
import YGOCore
@testable import YGONetworking

@Suite("Catalog decoding")
struct CatalogDecodingTests {
    /// A card carrying every field the upstream source ever sends, plus one it
    /// does not, so both halves of tolerance are exercised at once.
    private let generousCard = Data("""
    {"data":[{
      "id": 55144522,
      "name": "Pot of Greed",
      "type": "Spell Card",
      "humanReadableCardType": "Normal Spell",
      "frameType": "spell",
      "desc": "Draw 2 cards.",
      "race": "Normal",
      "ygoprodeck_url": "https://ygoprodeck.com/card/pot-of-greed-4698",
      "a_field_added_next_year": {"nested": [1, 2, 3]},
      "card_images": [{"id": 55144522, "image_url": "x", "image_url_small": "y"}],
      "card_prices": [{"cardmarket_price": "0.15", "tcgplayer_price": "0.00"}],
      "banlist_info": {"ban_tcg": "Forbidden", "ban_goat": "Limited"},
      "misc_info": [{"formats": ["TCG", "GOAT"], "has_effect": 0, "treated_as": "Something"}]
    }]}
    """.utf8)

    /// Evidence for R2.AC1's failure containment: an upstream addition must not
    /// break ingestion, while an upstream removal of something the catalog
    /// depends on must fail loudly rather than store a half-built card.
    @Test func ignoresUnknownFieldsAndThrowsOnMissingRequiredField() throws {
        let decoded = try YGOProDeckCatalogClient.decodeDataset(generousCard)

        #expect(decoded.count == 1)
        let card = try #require(decoded.first)
        #expect(card.id == 55144522)
        #expect(card.name == "Pot of Greed")
        #expect(card.misc?.treatedAs == "Something")

        // Now remove a field the catalog cannot do without.
        let withoutName = Data("""
        {"data":[{
          "id": 55144522,
          "type": "Spell Card",
          "humanReadableCardType": "Normal Spell",
          "frameType": "spell",
          "desc": "Draw 2 cards.",
          "race": "Normal",
          "card_images": [{"id": 55144522}],
          "card_prices": [{}]
        }]}
        """.utf8)

        #expect(throws: (any Error).self) {
            try YGOProDeckCatalogClient.decodeDataset(withoutName)
        }
    }

    /// Two thirds of the pool has no ATK, DEF, level or attribute, and only two
    /// per cent carries a ban entry. Absence is the normal case, not an error.
    @Test func treatsFieldsAbsentForMostCardsAsOptional() throws {
        let minimal = Data("""
        {"data":[{
          "id": 1, "name": "A", "type": "Spell Card",
          "humanReadableCardType": "Normal Spell", "frameType": "spell",
          "desc": "B", "race": "Normal",
          "card_images": [{"id": 1}], "card_prices": [{}]
        }]}
        """.utf8)

        let card = try #require(try YGOProDeckCatalogClient.decodeDataset(minimal).first)

        #expect(card.atk == nil)
        #expect(card.def == nil)
        #expect(card.level == nil)
        #expect(card.attribute == nil)
        #expect(card.cardSets == nil)
        #expect(card.banlistInfo == nil)
        #expect(card.miscInfo == nil)
        #expect(card.misc == nil)
    }

    /// Upstream writes "0" for a marketplace that has no price, which is not a
    /// free card. Storing it as zero would poison any collection valuation.
    @Test func discardsZeroAndUnparseablePrices() throws {
        let decoded = try YGOProDeckCatalogClient.decodeDataset(generousCard)
        let prices = try #require(decoded.first?.cardPrices.first?.bySource)

        #expect(prices.count == 1)
        #expect(prices[0].source == "cardmarket")
        #expect(prices[0].value == 0.15)
    }

    /// The whole recorded dataset must decode, not just a hand-written card.
    @Test func decodesEveryCardInBothRecordedDatasets() throws {
        let english = try YGOProDeckCatalogClient.decodeDataset(Fixture.data("catalog-en.json"))
        let italian = try YGOProDeckCatalogClient.decodeDataset(Fixture.data("catalog-it.json"))

        #expect(english.count == 35)
        #expect(italian.count == 22)
        // The localised response is what carries the English name alongside the
        // translation; without it a translated row cannot be matched back.
        #expect(italian.allSatisfy { $0.nameEn != nil })
        #expect(english.allSatisfy { $0.nameEn == nil })
    }
}
