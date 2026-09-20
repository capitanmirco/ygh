import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOImageStore

@Suite("Artwork store")
struct ArtworkStoreTests {
    private func makeStore() throws -> (ArtworkStore, SQLiteArtworkPresence, DatabaseQueue, URL) {
        let (database, directory) = try ArtworkFixture.seededDatabase()
        let presence = SQLiteArtworkPresence(database: database)
        let store = ArtworkStore(
            rootURL: directory, presence: presence, now: { ArtworkFixture.storedAt })
        return (store, presence, database, directory)
    }

    /// Evidence for R4.AC1: once an image is held locally it is served from
    /// disk, with nothing reaching the upstream host. Hotlinking its images is
    /// forbidden and gets the client's address blacklisted.
    @Test func servesStoredArtworkWithFetcherDisabled() async throws {
        let (store, presence, _, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let identifier = ArtworkIdentifier(55144522)
        let bytes = ArtworkFixture.imageBytes("thumbnail-bytes")
        try await store.store(bytes, for: identifier, variant: .thumbnail)

        // No network of any kind is involved in reading it back.
        let path = try #require(await store.storedArtworkPath(
            for: identifier, variant: .thumbnail))
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(try Data(contentsOf: URL(filePath: path)) == bytes)

        // The path is local, never a remote address.
        #expect(!path.hasPrefix("http"))
        #expect(path.hasPrefix(directory.path(percentEncoded: false)))

        let tracked = try await presence.isStored(identifier, variant: .thumbnail)
        #expect(tracked)

        // A variant that was never stored is simply absent.
        let full = await store.storedArtworkPath(for: identifier, variant: .full)
        #expect(full == nil)
    }

    /// Files are sharded by the low byte of the identifier, so no directory
    /// ends up holding the whole fourteen thousand.
    @Test func shardsFilesByIdentifierSoNoDirectoryGrowsUnbounded() async throws {
        let (store, _, _, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let identifiers = (0..<600).map { ArtworkIdentifier(1_000_000 + $0) }
        for identifier in identifiers {
            try await store.store(
                ArtworkFixture.imageBytes("x"), for: identifier, variant: .thumbnail)
        }

        let thumbnailRoot = directory.appending(path: "thumb")
        let shards = try FileManager.default.contentsOfDirectory(
            atPath: thumbnailRoot.path(percentEncoded: false))
        #expect(shards.count == 256)

        let largestShard = try shards.map { shard in
            try FileManager.default.contentsOfDirectory(
                atPath: thumbnailRoot.appending(path: shard).path(percentEncoded: false)).count
        }.max()
        #expect((largestShard ?? 0) <= 4)
    }

    /// A file deleted behind the application's back repairs its own record on
    /// the next read, instead of costing a filesystem scan at every start.
    @Test func repairsPresenceWhenFileWasRemovedOutOfBand() async throws {
        let (store, presence, _, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let identifier = ArtworkIdentifier(46986414)
        try await store.store(
            ArtworkFixture.imageBytes("y"), for: identifier, variant: .thumbnail)
        let tracked = try await presence.isStored(identifier, variant: .thumbnail)
        #expect(tracked)

        try FileManager.default.removeItem(at: store.fileURL(for: identifier, variant: .thumbnail))

        let path = await store.storedArtworkPath(for: identifier, variant: .thumbnail)
        #expect(path == nil)
        let stillTracked = try await presence.isStored(identifier, variant: .thumbnail)
        #expect(!stillTracked, "il record doveva essere riparato dopo la lettura mancata")
    }

    /// Evidence for R4.AC9: emptying the image store frees the disk and leaves
    /// every card record where it was. Artwork is the one part of the catalog
    /// that can always be fetched again.
    @Test func purgeEmptiesDirectoryAndKeepsCardRecords() async throws {
        let (store, presence, database, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let artworkIDs = try ArtworkFixture.cards().flatMap { $0.cardImages.map(\.id) }
        for id in artworkIDs.prefix(20) {
            try await store.store(
                ArtworkFixture.imageBytes("z"), for: ArtworkIdentifier(id), variant: .thumbnail)
        }

        let cardsBefore = try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM card")
        }
        let storedBefore = try await presence.storedCount(variant: .thumbnail)
        #expect(storedBefore == 20)
        #expect(await store.storedByteSize() > 0)

        try await store.purge()

        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
        let storedAfter = try await presence.storedCount(variant: .thumbnail)
        #expect(storedAfter == 0)

        // Cards, artwork mappings and everything else survive untouched.
        let cardsAfter = try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM card")
        }
        #expect(cardsAfter == cardsBefore)
        let artworkRows = try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM card_artwork")
        }
        #expect(artworkRows == artworkIDs.count)
    }
}
