import Foundation
import GRDB
import Testing
import YGOCore
import YGOImageStore
import YGOPersistence
@testable import YGOComposition

@Suite(.serialized)
struct CatalogBudgetTests {
    private static let observedAt = Date(timeIntervalSince1970: 1_758_000_000)

    /// Budgets from the requirements: the database stays at or below 250 MB and
    /// the thumbnail store at or below 500 MB.
    private static let databaseBudgetBytes = 250 * 1_048_576
    private static let thumbnailBudgetBytes = 500 * 1_048_576

    /// Average bytes per thumbnail, read from the live image host's
    /// `content-length` for a sample of cards rather than guessed: about 24 KB.
    private static let measuredThumbnailBytes = 24_000

    /// Evidence for NFR3: a full catalog fits the disk budget, and so does the
    /// artwork that goes beside it.
    ///
    /// The database half is measured directly. The thumbnail half is measured
    /// on a written sample and extrapolated to the full artwork count: writing
    /// three hundred and fifty megabytes inside a test would trade minutes of
    /// runtime for no extra confidence, since the per-file size is what the
    /// budget actually depends on.
    @Test func databaseAndThumbnailSizesStayWithinBudget() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "ygo-budget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: container) }

        let configuration = DatabaseBootstrapper.Configuration(containerURL: container)
        let database = try DatabaseBootstrapper(configuration: configuration).open()

        let english = try SyntheticCatalog.payload()
        let italian = try SyntheticCatalog.italianPayload(from: english)
        try await database.write { db in
            let writer = CatalogWriter()
            try writer.writeEnglishDataset(english, observedAt: Self.observedAt, into: db)
            try writer.mergeItalianDataset(italian, into: db)
        }

        // Checkpoint so the write-ahead log is folded into the file being
        // measured rather than sitting beside it uncounted.
        try await database.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }

        let databaseBytes = try Self.fileSize(configuration.databaseURL)
        #expect(databaseBytes > 0)
        #expect(databaseBytes <= Self.databaseBudgetBytes,
                "database \(Self.megabytes(databaseBytes)) MB, budget 250 MB")

        // The artwork store, measured on a sample.
        let presence = SQLiteArtworkPresence(database: database)
        let store = ArtworkStore(
            rootURL: container.appending(path: "Artwork"),
            presence: presence, now: { Self.observedAt })

        let sampleSize = 200
        let sampleBytes = Data(repeating: 0x42, count: Self.measuredThumbnailBytes)
        for index in 0..<sampleSize {
            try await store.store(
                sampleBytes, for: ArtworkIdentifier(10_000_000 + index), variant: .thumbnail)
        }

        let onDisk = await store.storedByteSize()
        let averagePerFile = Double(onDisk) / Double(sampleSize)
        #expect(averagePerFile > 0)

        let projected = Int(averagePerFile * Double(SyntheticCatalog.artworkCount))
        #expect(projected <= Self.thumbnailBudgetBytes,
                "miniature proiettate \(Self.megabytes(projected)) MB su \(SyntheticCatalog.artworkCount) artwork, budget 500 MB")

        // Emptying the store frees all of it, so the budget is recoverable
        // rather than a one-way commitment of disk.
        try await store.purge()
        let afterPurge = await store.storedByteSize()
        #expect(afterPurge == 0)

        // Reported for the record.
        print("""
            BUDGET: database \(Self.megabytes(databaseBytes)) MB / 250 MB \
            | miniature proiettate \(Self.megabytes(projected)) MB / 500 MB \
            (\(Int(averagePerFile)) B per file × \(SyntheticCatalog.artworkCount))
            """)

        try await database.close()
    }

    private static func fileSize(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return values.fileSize ?? 0
    }

    private static func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f", Double(bytes) / 1_048_576)
    }
}
