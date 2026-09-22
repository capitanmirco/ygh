import Foundation
import YGOCore

/// What the application occupies under its container directory, and the two
/// things in there that can be reclaimed.
///
/// It takes the bootstrapper's own configuration rather than re-deriving the
/// file names, so the panel cannot drift from the component that creates them.
public struct FileStorageInventory: StorageInventorying {
    private let configuration: DatabaseBootstrapper.Configuration
    private let artwork: any ArtworkMaintaining

    public init(
        configuration: DatabaseBootstrapper.Configuration,
        artwork: any ArtworkMaintaining
    ) {
        self.configuration = configuration
        self.artwork = artwork
    }

    public func footprint() async -> StorageFootprint {
        let artworkFootprint = await artwork.storedFootprint()
        return StorageFootprint(
            artworkFiles: artworkFootprint.files,
            artworkBytes: artworkFootprint.bytes,
            databaseBytes: Self.byteSize(of: configuration.databaseURL) ?? 0,
            backupBytes: Self.byteSize(of: configuration.backupURL))
    }

    /// Empties the image cache. Card records are untouched: artwork is the one
    /// part of the catalog that can always be fetched again.
    public func purgeArtwork() async throws {
        try await artwork.purge()
    }

    /// Removes the pre-migration backup and nothing else.
    ///
    /// The backup is the containment for a migration that throws; by the time
    /// anyone can ask for this, that migration has committed. What the user
    /// gives up is a hand rollback to the previous schema, which is why the
    /// window asks before this runs.
    ///
    /// The live database's write-ahead log and shared-memory files are not
    /// touched. Removing one of those is how SQLite is told to replay a log
    /// belonging to a file that is gone.
    public func deleteBackup() async throws {
        let path = configuration.backupURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.removeItem(at: configuration.backupURL)
    }

    /// Nil when the file is not there, which is how an absent backup is told
    /// apart from an empty one.
    private static func byteSize(of url: URL) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return nil }
        return size
    }
}
