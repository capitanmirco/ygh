import Foundation
import GRDB
import Testing
import YGOCore
import YGOImageStore
@testable import YGOPersistence

@Suite("Storage inventory")
struct StorageInventoryTests {
    /// A container laid out the way the application lays one out: a migrated
    /// database, an `Artwork/` tree beside it, and optionally the
    /// pre-migration backup a past upgrade would have left behind.
    private struct Rig {
        let directory: URL
        let configuration: DatabaseBootstrapper.Configuration
        let database: DatabasePool
        let store: ArtworkStore
        let inventory: FileStorageInventory
    }

    private func makeRig(withBackup backupBytes: Int? = nil) throws -> Rig {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ygo-container-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let configuration = DatabaseBootstrapper.Configuration(containerURL: directory)
        let database = try DatabaseBootstrapper(configuration: configuration).open()

        if let backupBytes {
            try Data(repeating: 0x44, count: backupBytes)
                .write(to: configuration.backupURL)
        }

        let presence = SQLiteArtworkPresence(database: database)
        let store = ArtworkStore(
            rootURL: directory.appending(path: "Artwork"),
            presence: presence,
            now: { Date(timeIntervalSince1970: 1_758_000_000) })

        return Rig(
            directory: directory,
            configuration: configuration,
            database: database,
            store: store,
            inventory: FileStorageInventory(configuration: configuration, artwork: store))
    }

    /// A deck with slots and a collection entry: the irreplaceable part.
    private func seedUserData(_ database: DatabasePool) throws {
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO card (id, name_en, desc_en, type, frame_type, human_readable_type)
                VALUES (55144522, 'Pot of Greed', 'draw 2', 'Spell Card', 'spell', 'Spell Card')
                """)
            try db.execute(sql: """
                INSERT INTO card_artwork (artwork_id, card_id, ordinal)
                VALUES (55144522, 55144522, 0)
                """)
            try db.execute(sql: """
                INSERT INTO deck (id, name, format_code, created_at, updated_at)
                VALUES (1, 'LR-Chaos Turbo', 'GOAT', '2026-09-20T10:00:00Z', '2026-09-20T10:00:00Z')
                """)
            try db.execute(sql: """
                INSERT INTO deck_slot (deck_id, section, artwork_id, card_id, quantity)
                VALUES (1, 'main', 55144522, 55144522, 1)
                """)
            try db.execute(sql: """
                INSERT INTO collection_entry (id, card_id, condition, quantity)
                VALUES (1, 55144522, 'near_mint', 3)
                """)
        }
    }

    private func userDataCounts(_ database: DatabasePool) throws -> [Int] {
        try database.read { db in
            [
                try Int.fetchOne(db, sql: "SELECT count(*) FROM deck") ?? -1,
                try Int.fetchOne(db, sql: "SELECT count(*) FROM deck_slot") ?? -1,
                try Int.fetchOne(db, sql: "SELECT count(*) FROM collection_entry") ?? -1,
                try Int.fetchOne(db, sql: "SELECT sum(quantity) FROM collection_entry") ?? -1,
            ]
        }
    }

    /// Evidence for R3.AC2: the live database's own file, which the user's
    /// installation holds at 42 MB and nothing in the interface has ever said.
    @Test func theInventoryReportsTheDatabaseFilesSize() async throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        let footprint = await rig.inventory.footprint()
        let onDisk = try #require(
            try rig.configuration.databaseURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)

        #expect(footprint.databaseBytes == onDisk)
        #expect(footprint.databaseBytes > 0)
        #expect(footprint.artworkFiles == 0)
        #expect(footprint.artworkBytes == 0)
    }

    /// Evidence for R3.AC3: the backup is reported as its own figure rather
    /// than folded into the database's, because it is the one the user can act on.
    @Test func aPresentBackupIsReportedSeparatelyWithItsSize() async throws {
        let rig = try makeRig(withBackup: 12_345)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        let footprint = await rig.inventory.footprint()
        #expect(footprint.backupBytes == 12_345)
        #expect(footprint.databaseBytes != 12_345)
        #expect(footprint.totalBytes == footprint.databaseBytes + 12_345)
    }

    /// Evidence for R3.AC3: no backup is absence, not zero. A machine that has
    /// never migrated must not be shown a 0-byte row to act on.
    @Test func aContainerWithNoBackupReportsNone() async throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        #expect(await rig.inventory.footprint().backupBytes == nil)

        // And an emptied backup is still a present one.
        try Data().write(to: rig.configuration.backupURL)
        #expect(await rig.inventory.footprint().backupBytes == 0)
    }

    /// Evidence for R3.AC5: the files go and the records go with them, so the
    /// application's belief and the disk agree after a purge.
    @Test func purgingLeavesNoArtworkFileAndNoArtworkRow() async throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        for id in 0..<12 {
            try await rig.store.store(
                Data(repeating: 0x45, count: 128),
                for: ArtworkIdentifier(1_000_000 + id), variant: .thumbnail)
        }

        let before = await rig.inventory.footprint()
        #expect(before.artworkFiles == 12)
        #expect(before.artworkBytes == 12 * 128)
        let rowsBefore = try await rig.database.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM artwork_cache") ?? -1
        }
        #expect(rowsBefore == 12)

        try await rig.inventory.purgeArtwork()

        let after = await rig.inventory.footprint()
        #expect(after.artworkFiles == 0)
        #expect(after.artworkBytes == 0)
        let rowsAfter = try await rig.database.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM artwork_cache") ?? -1
        }
        #expect(rowsAfter == 0)
        #expect(after.databaseBytes > 0, "il database resta dov'è")
    }

    /// Evidence for R3.AC8: one file goes. The sidecars belong to the live
    /// database, and removing one of them is how SQLite is told to replay a log
    /// that belongs to a discarded file.
    @Test func deletingTheBackupLeavesTheDatabaseAndItsSidecarsIntact() async throws {
        let rig = try makeRig(withBackup: 2_048)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        try seedUserData(rig.database)
        // A write with no checkpoint leaves a write-ahead log beside the file.
        let sidecars = ["library.sqlite-wal", "library.sqlite-shm"]
            .map { rig.directory.appending(path: $0) }

        let manager = FileManager.default
        let databaseBefore = try #require(
            try rig.configuration.databaseURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let sidecarsBefore = sidecars.map { manager.fileExists(atPath: $0.path(percentEncoded: false)) }

        try await rig.inventory.deleteBackup()

        #expect(!manager.fileExists(atPath: rig.configuration.backupURL.path(percentEncoded: false)))
        #expect(manager.fileExists(atPath: rig.configuration.databaseURL.path(percentEncoded: false)))
        let databaseAfter = try #require(
            try rig.configuration.databaseURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(databaseAfter == databaseBefore)
        #expect(sidecars.map { manager.fileExists(atPath: $0.path(percentEncoded: false)) }
            == sidecarsBefore)
        #expect(await rig.inventory.footprint().backupBytes == nil)

        // Asking again when it is already gone is not an error.
        try await rig.inventory.deleteBackup()
    }

    /// Evidence for R3.AC9: the one thing here that cannot be fetched again is
    /// counted before and after both maintenance actions and compared.
    @Test func decksSlotsAndCollectionAreIdenticalAfterBothMaintenanceActions() async throws {
        let rig = try makeRig(withBackup: 1_024)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        try seedUserData(rig.database)
        try await rig.store.store(
            Data(repeating: 0x46, count: 64),
            for: ArtworkIdentifier(55144522), variant: .thumbnail)

        let before = try userDataCounts(rig.database)
        #expect(before == [1, 1, 1, 3])

        try await rig.inventory.purgeArtwork()
        try await rig.inventory.deleteBackup()

        let after = try userDataCounts(rig.database)
        #expect(after == before)

        // The deck is still readable, not merely counted.
        let deckName = try await rig.database.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM deck WHERE id = 1")
        }
        #expect(deckName == "LR-Chaos Turbo")
    }
}
