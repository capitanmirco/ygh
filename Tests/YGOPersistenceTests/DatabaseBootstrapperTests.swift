import Foundation
import GRDB
import Testing
@testable import YGOPersistence

@Suite("Database bootstrapper")
struct DatabaseBootstrapperTests {
    // MARK: - Fixtures

    /// A throwaway directory holding a database and its backup slot.
    private struct Workspace: ~Copyable {
        let directory: URL
        let configuration: DatabaseBootstrapper.Configuration

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appending(path: "ygo-bootstrap-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            configuration = .init(containerURL: directory)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// The shipped chain plus one more migration, standing in for a later
    /// release that the stored database has not seen yet.
    private func migratorAddingSecondVersion(failing: Bool) -> DatabaseMigrator {
        var migrator = CatalogSchema.migrator
        migrator.registerMigration("v002_later_release") { db in
            try db.create(table: "added_by_v002") { $0.primaryKey("id", .integer) }
            if failing {
                throw DatabaseError(resultCode: .SQLITE_ERROR, message: "migrazione v002 fallita")
            }
        }
        return migrator
    }

    private func seedOneCard(_ configuration: DatabaseBootstrapper.Configuration) throws {
        let pool = try DatabaseBootstrapper(configuration: configuration).open()
        try pool.write { db in
            try db.execute(sql: """
                INSERT INTO card (id, name_en, desc_en, type, frame_type,
                                  human_readable_type, has_effect)
                VALUES (55144522, 'Pot of Greed', 'Draw 2 cards.',
                        'Spell Card', 'spell', 'Normal Spell', 0)
                """)
        }
        try pool.close()
    }

    // MARK: - Tests

    /// Evidence for R8.AC1: a start that has migrations to apply copies the
    /// database first, and that copy holds the pre-migration contents.
    @Test func writesBackupBeforeApplyingMigrations() throws {
        let workspace = try Workspace()
        let configuration = workspace.configuration
        try seedOneCard(configuration)

        #expect(!FileManager.default.fileExists(
            atPath: configuration.backupURL.path(percentEncoded: false)),
            "nessun backup deve esistere prima di una migrazione in sospeso")

        let pool = try DatabaseBootstrapper(
            configuration: configuration,
            migrator: migratorAddingSecondVersion(failing: false)).open()
        try pool.close()

        #expect(FileManager.default.fileExists(
            atPath: configuration.backupURL.path(percentEncoded: false)))

        // The backup must predate the migration: it holds the card that was
        // already stored, and not the table v002 introduces.
        let backup = try DatabaseQueue(path: configuration.backupURL.path(percentEncoded: false))
        try backup.read { db in
            let storedCards = try Int.fetchOne(db, sql: "SELECT count(*) FROM card")
            let hasLaterTable = try db.tableExists("added_by_v002")
            #expect(storedCards == 1)
            #expect(!hasLaterTable)
        }

        // The live database did move forward.
        let migrated = try DatabaseQueue(path: configuration.databaseURL.path(percentEncoded: false))
        try migrated.read { db in
            let hasLaterTable = try db.tableExists("added_by_v002")
            #expect(hasLaterTable)
        }
    }

    /// Evidence for R8.AC3: a failing migration leaves the database byte for
    /// byte equal to the backup, and reports the failure rather than starting
    /// against a half-migrated file.
    @Test func restoresBackupWhenMigrationFails() throws {
        let workspace = try Workspace()
        let configuration = workspace.configuration
        try seedOneCard(configuration)

        var raised: (any Error)?
        do {
            _ = try DatabaseBootstrapper(
                configuration: configuration,
                migrator: migratorAddingSecondVersion(failing: true)).open()
        } catch {
            raised = error
        }

        guard case .migrationFailed? = raised as? DatabaseBootstrapError else {
            Issue.record("atteso migrationFailed, ricevuto \(String(describing: raised))")
            return
        }

        let databaseBytes = try Data(contentsOf: configuration.databaseURL)
        let backupBytes = try Data(contentsOf: configuration.backupURL)
        #expect(databaseBytes == backupBytes)

        // The write-ahead log of the discarded attempt must not survive, or
        // SQLite would replay it over the restored file.
        let databasePath = configuration.databaseURL.path(percentEncoded: false)
        #expect(!FileManager.default.fileExists(atPath: databasePath + "-wal"))

        let restored = try DatabaseQueue(path: databasePath)
        try restored.read { db in
            let storedCards = try Int.fetchOne(db, sql: "SELECT count(*) FROM card")
            let hasLaterTable = try db.tableExists("added_by_v002")
            #expect(storedCards == 1)
            #expect(!hasLaterTable)
        }
    }

    /// A first run has nothing to protect, so it must not leave a backup of an
    /// empty database behind.
    @Test func skipsBackupOnFirstRun() throws {
        let workspace = try Workspace()
        let configuration = workspace.configuration

        let pool = try DatabaseBootstrapper(configuration: configuration).open()
        try pool.close()

        #expect(!FileManager.default.fileExists(
            atPath: configuration.backupURL.path(percentEncoded: false)))
    }
}
