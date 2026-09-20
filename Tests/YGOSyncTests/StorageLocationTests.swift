import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOSync

@Suite("Storage locations")
struct StorageLocationTests {
    private func rig() throws -> (CollectionFixture.Rig, CardIdentifier, [Int64]) {
        let rig = try CollectionFixture.seeded()
        let (cardID, printings) = try CollectionFixture.cardWithPrintings(2, in: rig)
        return (rig, CardIdentifier(cardID), printings)
    }

    /// Evidence for R3.AC1.
    @Test func createdLocationIsRetrievableUnderItsName() async throws {
        let (rig, _, _) = try rig()

        let id = try await rig.collection.createLocation(
            named: "Raccoglitore GOAT", notes: "scaffale alto")

        let locations = try await rig.collection.locations()
        #expect(locations.count == 1)
        #expect(locations[0].id == id)
        #expect(locations[0].name == "Raccoglitore GOAT")
        #expect(locations[0].notes == "scaffale alto")
    }

    /// Evidence for R3.AC2: a copy is in one place, not two.
    @Test func assignedCopyListsUnderItsLocationAndNotAmongUnfiled() async throws {
        let (rig, card, printings) = try rig()
        let binder = try await rig.collection.createLocation(named: "Raccoglitore")
        try await rig.collection.addCopy(cardID: card, printID: printings[0])

        let entry = try #require(try await rig.collection.entries().first)
        #expect(try await rig.collection.entries(inLocation: nil).count == 1,
                "prima di assegnarla la copia è non archiviata")

        try await rig.collection.assign(entry: entry.id, toLocation: binder)

        #expect(try await rig.collection.entries(inLocation: binder).map(\.id) == [entry.id])
        #expect(try await rig.collection.entries(inLocation: nil).isEmpty)

        // And back out again.
        try await rig.collection.assign(entry: entry.id, toLocation: nil)
        #expect(try await rig.collection.entries(inLocation: binder).isEmpty)
        #expect(try await rig.collection.entries(inLocation: nil).count == 1)
    }

    /// Evidence for R3.AC3: a binder is a label, not an owner. Deleting one
    /// must never take hand-entered copies with it.
    @Test func deletingALocationKeepsItsCopiesAsUnfiled() async throws {
        let (rig, card, printings) = try rig()
        let binder = try await rig.collection.createLocation(named: "Da cancellare")

        for _ in 0..<5 {
            try await rig.collection.addCopy(
                cardID: card, printID: printings[0], locationID: binder)
        }
        #expect(try await rig.collection.copiesHeld(ofCard: card) == 5)
        #expect(try await rig.collection.entries(inLocation: binder).count == 1)

        try await rig.collection.deleteLocation(binder)

        #expect(try await rig.collection.copiesHeld(ofCard: card) == 5,
                "le cinque copie devono sopravvivere alla cartella")
        let unfiled = try await rig.collection.entries(inLocation: nil)
        #expect(unfiled.count == 1)
        #expect(unfiled[0].quantity == 5)
        #expect(unfiled[0].locationID == nil)
        #expect(try await rig.collection.locations().isEmpty)
    }

    /// Evidence for R3.AC4: finding a card means not emptying every box.
    @Test func reportsEachLocationHoldingACardWithItsCount() async throws {
        let (rig, card, printings) = try rig()
        let first = try await rig.collection.createLocation(named: "Raccoglitore A")
        let second = try await rig.collection.createLocation(named: "Scatola B")

        try await rig.collection.addCopy(cardID: card, printID: printings[0], locationID: first)
        try await rig.collection.addCopy(cardID: card, printID: printings[0], locationID: first)
        try await rig.collection.addCopy(cardID: card, printID: printings[1], locationID: second)
        try await rig.collection.addCopy(cardID: card, printID: printings[1])

        let places = try await rig.collection.whereabouts(of: card)
        #expect(places.count == 3)

        let byName = Dictionary(uniqueKeysWithValues: places.map { ($0.locationName, $0.copies) })
        #expect(byName["Raccoglitore A"] == 2)
        #expect(byName["Scatola B"] == 1)
        #expect(byName[nil] == 1, "la copia non archiviata va comunque riportata")

        // The counts account for every copy held.
        #expect(places.reduce(0) { $0 + $1.copies } == 4)
        #expect(places.filter(\.isUnfiled).count == 1)
    }
}
