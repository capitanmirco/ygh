import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOImageStore

@Suite("Artwork footprint")
struct ArtworkFootprintTests {
    private func makeStore() throws -> (ArtworkStore, SQLiteArtworkPresence, URL) {
        let (database, directory) = try ArtworkFixture.seededDatabase()
        let presence = SQLiteArtworkPresence(database: database)
        let store = ArtworkStore(
            rootURL: directory, presence: presence, now: { ArtworkFixture.storedAt })
        return (store, presence, directory)
    }

    /// Evidence for R3.AC1: both figures come from one walk of the tree, so
    /// the count and the byte total describe the same moment. The user's own
    /// installation holds 14,730 files; the shape is what is asserted here.
    @Test func theFootprintCountsEveryStoredFileAndItsBytes() async throws {
        let (store, _, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Deliberately spread across shards: the store puts a file in a
        // directory named after the low byte of its identifier, so a count
        // that stopped at the first directory would be wrong.
        let written: [(Int, Int)] = [(55144522, 120), (46986414, 3_000), (1_000_001, 7)]
        for (id, size) in written {
            try await store.store(
                Data(repeating: 0x41, count: size),
                for: ArtworkIdentifier(id), variant: .thumbnail)
        }

        let footprint = await store.storedFootprint()
        #expect(footprint.files == 3)
        #expect(footprint.bytes == 120 + 3_000 + 7)

        // A full image beside a thumbnail is another file, not a replacement.
        try await store.store(
            Data(repeating: 0x42, count: 50),
            for: ArtworkIdentifier(55144522), variant: .full)
        let grown = await store.storedFootprint()
        #expect(grown.files == 4)
        #expect(grown.bytes == 120 + 3_000 + 7 + 50)
    }

    /// Evidence for R3.AC1: nothing cached reads as nothing, including before
    /// the directory has ever been created.
    @Test func anEmptyStoreReportsNoFilesAndNoBytes() async throws {
        let (store, _, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let beforeAnything = await store.storedFootprint()
        #expect(beforeAnything.files == 0)
        #expect(beforeAnything.bytes == 0)

        try await store.store(
            ArtworkFixture.imageBytes("thumb"),
            for: ArtworkIdentifier(55144522), variant: .thumbnail)
        #expect(await store.storedFootprint().files == 1)

        try await store.purge()
        let afterPurge = await store.storedFootprint()
        #expect(afterPurge.files == 0)
        #expect(afterPurge.bytes == 0)
    }

    /// Evidence for R3.AC1: the older reading is now expressed in terms of the
    /// new one, so there is a single definition of what counts as stored.
    @Test func theByteTotalAgreesWithTheOlderByteSizeReading() async throws {
        let (store, _, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        for id in 0..<20 {
            try await store.store(
                Data(repeating: 0x43, count: 64),
                for: ArtworkIdentifier(1_000_000 + id), variant: .thumbnail)
        }

        let footprint = await store.storedFootprint()
        let legacy = await store.storedByteSize()
        #expect(footprint.bytes == legacy)
        #expect(footprint.files == 20)
        #expect(legacy == 20 * 64)
    }

    /// Evidence for R3.AC6: artwork is the one part of the catalog that can
    /// always be fetched again, which is what makes purging it safe.
    @Test func artworkStoredAfterAPurgeIsOnDiskAndRecordedAgain() async throws {
        let (store, presence, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let identifier = ArtworkIdentifier(55144522)
        try await store.store(
            ArtworkFixture.imageBytes("before"), for: identifier, variant: .thumbnail)
        #expect(try await presence.isStored(identifier, variant: .thumbnail))

        try await store.purge()
        #expect(await store.storedArtworkPath(for: identifier, variant: .thumbnail) == nil)
        #expect(try await presence.isStored(identifier, variant: .thumbnail) == false)

        // Fetching it again is an ordinary store, and it lands in both places.
        try await store.store(
            ArtworkFixture.imageBytes("after"), for: identifier, variant: .thumbnail)

        let path = try #require(
            await store.storedArtworkPath(for: identifier, variant: .thumbnail))
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(try Data(contentsOf: URL(filePath: path)) == ArtworkFixture.imageBytes("after"))
        #expect(try await presence.isStored(identifier, variant: .thumbnail))
        #expect(await store.storedFootprint().files == 1)
    }
}
