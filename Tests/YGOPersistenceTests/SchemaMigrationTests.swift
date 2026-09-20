import Foundation
import GRDB
import Testing
@testable import YGOPersistence

@Suite("Schema migration")
struct SchemaMigrationTests {
    /// Evidence for R8.AC2: a successful migration run records the schema
    /// version it reached, and a second run against that database applies
    /// nothing further.
    @Test func recordsSchemaVersionAfterMigrating() throws {
        let queue = try DatabaseQueue()
        let migrator = CatalogSchema.migrator

        try migrator.migrate(queue)

        let applied = try queue.read { try migrator.appliedIdentifiers($0) }
        #expect(applied == Set(CatalogSchema.migrationIdentifiers))
        #expect(try queue.read { try migrator.hasCompletedMigrations($0) })

        // Re-running must be a no-op rather than a second application.
        try migrator.migrate(queue)
        let afterSecondRun = try queue.read { try migrator.appliedIdentifiers($0) }
        #expect(afterSecondRun == applied)
    }

    @Test func migrationIdentifiersAreDeclaredInOrderAndUnique() {
        let identifiers = CatalogSchema.migrationIdentifiers
        #expect(identifiers == identifiers.sorted())
        #expect(Set(identifiers).count == identifiers.count)
    }
}
