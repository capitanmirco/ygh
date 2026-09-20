import Foundation
import GRDB

/// Why opening the catalog database failed.
public enum DatabaseBootstrapError: Error {
    /// A migration threw. The database was put back to its pre-migration
    /// contents from `restoredFrom` before this error was raised.
    case migrationFailed(underlying: any Error, restoredFrom: URL)
    /// A migration threw and the database could not be put back.
    case migrationFailedWithoutRestore(underlying: any Error, restoreError: any Error)
}

/// Opens the catalog database, backing it up before it migrates and putting it
/// back if a migration throws.
///
/// A migrator chain cannot undo the migrations it already committed, so the
/// containment for a failed upgrade has to be at the file level rather than the
/// transaction level.
public struct DatabaseBootstrapper: Sendable {
    public struct Configuration: Sendable {
        public let databaseURL: URL
        public let backupURL: URL

        public init(databaseURL: URL, backupURL: URL) {
            self.databaseURL = databaseURL
            self.backupURL = backupURL
        }

        /// The layout used by the application: both files sit in the catalog
        /// directory, so a backup never lands outside the app's own storage.
        public init(containerURL: URL) {
            self.databaseURL = containerURL.appending(path: "library.sqlite")
            self.backupURL = containerURL.appending(path: "library.pre-migration.sqlite")
        }
    }

    private let configuration: Configuration
    private let migrator: DatabaseMigrator

    public init(
        configuration: Configuration,
        migrator: DatabaseMigrator = CatalogSchema.migrator
    ) {
        self.configuration = configuration
        self.migrator = migrator
    }

    /// `FileManager` is not `Sendable`, so it is reached through its shared
    /// instance rather than stored; the shared one is documented as safe to
    /// call from several threads.
    private var fileManager: FileManager { .default }

    /// Opens the database, migrating it if needed, and returns a pool whose
    /// readers may run concurrently with a synchronisation write.
    @discardableResult
    public func open() throws -> DatabasePool {
        try fileManager.createDirectory(
            at: configuration.databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        var poolConfiguration = GRDB.Configuration()
        poolConfiguration.foreignKeysEnabled = true
        let pool = try DatabasePool(
            path: configuration.databaseURL.path(percentEncoded: false),
            configuration: poolConfiguration)

        guard try hasPendingMigrations(in: pool) else { return pool }

        let backedUp = try backUpIfAlreadyPopulated(pool)

        do {
            try migrator.migrate(pool)
        } catch {
            guard backedUp else { throw error }
            try restore(pool: pool, after: error)
        }

        return pool
    }

    // MARK: - Steps

    private func hasPendingMigrations(in pool: DatabasePool) throws -> Bool {
        try pool.read { try !migrator.hasCompletedMigrations($0) }
    }

    /// A database with no migrations applied yet holds nothing worth keeping,
    /// so the backup is skipped for a first run.
    private func backUpIfAlreadyPopulated(_ pool: DatabasePool) throws -> Bool {
        let applied = try pool.read { try migrator.appliedIdentifiers($0) }
        guard !applied.isEmpty else { return false }

        if fileManager.fileExists(atPath: configuration.backupURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: configuration.backupURL)
        }

        // `VACUUM INTO` writes a consistent copy that already includes anything
        // still sitting in the write-ahead log, which a plain file copy misses.
        try pool.writeWithoutTransaction { db in
            try db.execute(
                sql: "VACUUM INTO ?",
                arguments: [configuration.backupURL.path(percentEncoded: false)])
        }
        return true
    }

    private func restore(pool: DatabasePool, after migrationError: any Error) throws {
        do {
            try pool.close()
            for url in sidecarURLs + [configuration.databaseURL] where
                fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.copyItem(at: configuration.backupURL, to: configuration.databaseURL)
        } catch {
            throw DatabaseBootstrapError.migrationFailedWithoutRestore(
                underlying: migrationError, restoreError: error)
        }
        throw DatabaseBootstrapError.migrationFailed(
            underlying: migrationError, restoredFrom: configuration.backupURL)
    }

    /// The write-ahead log and shared-memory files. They must go with the
    /// database file, or SQLite replays a log that belongs to the discarded one.
    private var sidecarURLs: [URL] {
        let path = configuration.databaseURL.path(percentEncoded: false)
        return [URL(filePath: path + "-wal"), URL(filePath: path + "-shm")]
    }
}
