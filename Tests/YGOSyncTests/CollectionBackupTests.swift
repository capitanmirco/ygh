import Foundation
import GRDB
import Testing
import YGOCore
@testable import YGOPersistence
@testable import YGOSync

/// The collection is hand-entered and exists nowhere else: no re-download
/// brings it back. These assertions are about that.
@Suite("Collection backup")
struct CollectionBackupTests {
    private static let bought = Date(timeIntervalSince1970: 1_700_000_000)

    /// A collection with every field populated, so a backup that drops one
    /// is caught rather than merely one that fails outright.
    private func stocked() async throws -> CollectionFixture.Rig {
        let rig = try CollectionFixture.seeded()
        let (cardID, printings) = try CollectionFixture.cardWithPrintings(2, in: rig)
        let binder = try await rig.collection.createLocation(named: "Raccoglitore A")

        try await rig.collection.recordPurchase(
            cardID: CardIdentifier(cardID), printID: printings[0], condition: .nearMint,
            quantity: 3, pricePerCopy: 2.5, acquiredAt: Self.bought,
            locationID: binder, notes: "comprate insieme")
        try await rig.collection.recordPurchase(
            cardID: CardIdentifier(cardID), printID: printings[1], condition: .damaged,
            quantity: 1, pricePerCopy: nil, acquiredAt: nil)
        try await rig.collection.addCopy(cardID: CardIdentifier(cardID), printID: nil)

        return rig
    }

    /// Evidence for R6.AC1: one row per lot, and nothing left out of it.
    @Test func exportsOneRowPerEntryWithEveryStoredField() async throws {
        let rig = try await stocked()

        let csv = try await rig.collection.exportCSV()
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)

        #expect(lines.count == 4, "una intestazione più tre lotti")
        #expect(lines[0] == CollectionBackup.header.joined(separator: ","))

        let rows = try CollectionBackup.parse(csv)
        #expect(rows.count == 3)

        // The fully populated lot carries everything it was given.
        let priced = try #require(rows.first { $0.pricePerCopy != nil })
        #expect(priced.quantity == 3)
        #expect(priced.pricePerCopy == 2.5)
        #expect(priced.condition == .nearMint)
        #expect(priced.location == "Raccoglitore A")
        #expect(priced.notes == "comprate insieme")
        #expect(priced.setCode != nil)
        #expect(priced.rarity != nil)
        #expect(priced.acquiredAt != nil)
        #expect(!priced.cardName.isEmpty)

        // The lot with no printing still exports, with an empty set code.
        let noPrinting = try #require(rows.first { $0.setCode == nil })
        #expect(noPrinting.quantity == 1)
        #expect(noPrinting.pricePerCopy == nil, "prezzo assente resta assente")
    }

    /// Evidence for R6.AC2: the round trip is the whole point.
    @Test func exportClearImportRestoresTheSameCollection() async throws {
        let rig = try await stocked()

        let before = try await rig.collection.backupRows()
        let totalsBefore = try await rig.collection.totals()
        let csv = try await rig.collection.exportCSV()

        try await rig.collection.clearCollection(confirmed: true)
        #expect(try await rig.collection.totals().isEmpty)

        let result = try await rig.collection.importCSV(csv)
        #expect(result.restored == 3)
        #expect(result.isComplete)

        let after = try await rig.collection.backupRows()
        #expect(after == before, "il round trip deve restituire le stesse righe")

        let totalsAfter = try await rig.collection.totals()
        #expect(totalsAfter == totalsBefore)

        // The location was recreated rather than silently dropped.
        #expect(try await rig.collection.locations().map(\.name) == ["Raccoglitore A"])
    }

    /// Evidence for R6.AC3: a corrupt file must cost nothing.
    @Test func malformedFileLeavesTheCollectionUntouched() async throws {
        let rig = try await stocked()
        let before = try await rig.collection.backupRows()

        let damaged = [
            "",                                            // vuoto
            "not,a,backup\n1,2,3",                         // intestazione sbagliata
            CollectionBackup.header.joined(separator: ",") + "\nnonnumerico,x,,,near_mint,1,,,,",
            CollectionBackup.header.joined(separator: ",") + "\n1,x,,,condizione_inventata,1,,,,",
            CollectionBackup.header.joined(separator: ",") + "\n1,x,,,near_mint,0,,,,",
            CollectionBackup.header.joined(separator: ",") + "\n1,troppo,pochi,campi",
        ]

        for text in damaged {
            await #expect(throws: CollectionBackupError.self) {
                _ = try await rig.collection.importCSV(text, replacingExisting: true)
            }
        }

        let after = try await rig.collection.backupRows()
        #expect(after == before, "un file rotto non deve toccare la collezione esistente")
    }

    /// Evidence for R6.AC4: one renamed set must not cost a whole collection.
    @Test func importsKnownRowsAndNamesTheUnresolvedPrinting() async throws {
        let rig = try await stocked()
        let csv = try await rig.collection.exportCSV()

        // A row naming a printing this catalog does not hold.
        let header = CollectionBackup.header.joined(separator: ",")
        let ghost = "999999999,Carta Fantasma,ZZZ-EN001,Common,near_mint,2,,,,"
        let withGhost = csv.replacingOccurrences(of: header, with: header) + ghost + "\n"

        try await rig.collection.clearCollection(confirmed: true)
        let result = try await rig.collection.importCSV(withGhost)

        #expect(result.restored == 3, "le righe valide entrano comunque")
        #expect(result.unresolved.count == 1)
        #expect(result.unresolved[0].contains("Carta Fantasma"))
        #expect(!result.isComplete)
        #expect(try await rig.collection.totals().totalCopies == 5)
    }

    /// Card names hold commas and apostrophes; set names hold quotation marks.
    /// A backup that mangles them is not a backup.
    @Test func quotesFieldsHoldingCommasAndQuotationMarks() throws {
        #expect(CollectionBackup.escape("semplice") == "semplice")
        #expect(CollectionBackup.escape("Ash Blossom, Joyous Spring")
                == "\"Ash Blossom, Joyous Spring\"")
        #expect(CollectionBackup.escape("\"C\" Volante") == "\"\"\"C\"\" Volante\"")

        // And they survive the round trip through a whole row.
        let row = BackupRow(
            cardID: 1, cardName: "\"C\" Volante, la Seconda", setCode: "JOTL-EN039",
            rarity: "Super Rare", condition: .lightlyPlayed, quantity: 2,
            pricePerCopy: 1.25, acquiredAt: "2026-01-01T00:00:00Z",
            location: "Scatola \"grande\"", notes: "nota con, virgola")

        let parsed = try CollectionBackup.parse(CollectionBackup.csv(rows: [row]))
        #expect(parsed.count == 1)
        #expect(parsed[0] == row, "i campi con virgole e virgolette devono tornare identici")
        #expect(parsed[0].cardName == "\"C\" Volante, la Seconda")
        #expect(parsed[0].location == "Scatola \"grande\"")
        #expect(parsed[0].notes == "nota con, virgola")
    }
}
