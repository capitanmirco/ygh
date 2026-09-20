import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOSync

@Suite("Collection filters")
struct CollectionFilterTests {
    /// Records a spread of copies across printings and conditions, and hands
    /// back the rarities that ended up in the collection.
    private func stocked() async throws -> (CollectionFixture.Rig, [Int64: String?]) {
        let rig = try CollectionFixture.seeded()
        var rarityByPrint: [Int64: String?] = [:]

        // Take printings from several cards so more than one rarity appears.
        var recorded = 0
        for card in rig.cards where recorded < 12 {
            let printings = try CollectionFixture.printings(of: card.id, in: rig.database)
            for printID in printings.prefix(2) where recorded < 12 {
                let condition: CardCondition = recorded % 3 == 0 ? .damaged : .nearMint
                try await rig.collection.addCopy(
                    cardID: CardIdentifier(card.id), printID: printID, condition: condition)
                try await rig.collection.addCopy(
                    cardID: CardIdentifier(card.id), printID: printID, condition: condition)
                rarityByPrint[printID] = try await rig.database.read { db in
                    try String.fetchOne(db, sql: "SELECT rarity FROM card_print WHERE id = ?",
                                        arguments: [printID])
                }
                recorded += 1
            }
        }
        return (rig, rarityByPrint)
    }

    /// Evidence for R4.AC3: filters narrow together, not alternatively.
    @Test func everyResultSatisfiesEveryAppliedFilter() async throws {
        let (rig, rarityByPrint) = try await stocked()
        let rarities = Set(rarityByPrint.values.compactMap { $0 })
        let rarity = try #require(rarities.sorted().first)

        var filters = CollectionFilters()
        filters.rarities = [rarity]
        let byRarity = try await rig.collection.listing(matching: filters).entries
        #expect(!byRarity.isEmpty)
        for entry in byRarity {
            let printID = try #require(entry.printID)
            #expect(rarityByPrint[printID] == rarity)
        }

        // Add a condition: every result must satisfy both, not either.
        filters.conditions = [.nearMint]
        let both = try await rig.collection.listing(matching: filters).entries
        for entry in both {
            let printID = try #require(entry.printID)
            #expect(rarityByPrint[printID] == rarity)
            #expect(entry.condition == .nearMint)
        }
        #expect(both.count <= byRarity.count, "aggiungere un filtro non può allargare il risultato")

        // A combination nothing satisfies returns no matches, not everything.
        filters.rarities = ["Rarità Inesistente"]
        #expect(try await rig.collection.listing(matching: filters) == .noMatches)
    }

    /// Evidence for R4.AC4: the breakdown has to account for every copy, or it
    /// quietly misleads. Copies recorded against no printing have no rarity and
    /// are reported under their own key rather than dropped.
    @Test func perRarityCountsSumToTheCollectionTotal() async throws {
        let (rig, _) = try await stocked()

        // A copy with no printing, and therefore no rarity.
        let cardID = try #require(rig.cards.first?.id)
        try await rig.collection.addCopy(cardID: CardIdentifier(cardID), printID: nil)

        let byRarity = try await rig.collection.copiesByRarity()
        let totals = try await rig.collection.totals()

        #expect(byRarity.values.reduce(0, +) == totals.totalCopies,
                "le cifre per rarità devono sommare al totale, \(byRarity.values.reduce(0, +)) contro \(totals.totalCopies)")
        #expect(byRarity.keys.contains(nil), "le copie senza stampa vanno riportate, non scartate")
        #expect(byRarity[nil] == 1)
        #expect(byRarity.count > 1, "la fixture deve produrre più di una rarità")
    }
}
