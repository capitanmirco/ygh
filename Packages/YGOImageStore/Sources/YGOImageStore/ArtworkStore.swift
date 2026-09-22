import Foundation
import YGOCore

/// Holds card artwork as files on the local disk.
///
/// The upstream host forbids serving its images directly and blacklists
/// clients that do, so nothing in the application ever renders a remote
/// address: an image is downloaded once and read from here afterwards.
///
/// Files sit outside the database. Three hundred and fifty megabytes of
/// thumbnails inside it would breach the database size budget and make the
/// pre-migration backup enormous for data that can simply be fetched again.
public actor ArtworkStore: ArtworkProviding, ArtworkMaintaining {
    private let rootURL: URL
    private let presence: any ArtworkPresenceTracking
    private let now: @Sendable () -> Date

    public init(
        rootURL: URL,
        presence: any ArtworkPresenceTracking,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.rootURL = rootURL
        self.presence = presence
        self.now = now
    }

    /// `Application Support/.../Artwork/thumb/2a/55144522.jpg`
    ///
    /// The shard is the low byte of the identifier, which keeps directories to
    /// roughly sixty entries instead of one holding fourteen thousand files.
    public nonisolated func fileURL(
        for identifier: ArtworkIdentifier,
        variant: ArtworkVariant
    ) -> URL {
        let shard = String(format: "%02x", identifier.rawValue & 0xFF)
        return rootURL
            .appending(path: variant.rawValue)
            .appending(path: shard)
            .appending(path: "\(identifier.rawValue).jpg")
    }

    /// The local path of a stored artwork, or `nil` when it is not held.
    ///
    /// A record whose file has gone missing repairs itself here rather than in
    /// a start-up scan, because the condition only arises when something
    /// outside the application deletes the files.
    public func storedArtworkPath(
        for identifier: ArtworkIdentifier,
        variant: ArtworkVariant
    ) async -> String? {
        let url = fileURL(for: identifier, variant: variant)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            return url.path(percentEncoded: false)
        }
        try? await presence.forget(identifier, variant: variant)
        return nil
    }

    @discardableResult
    public func store(
        _ data: Data,
        for identifier: ArtworkIdentifier,
        variant: ArtworkVariant
    ) async throws -> URL {
        let url = fileURL(for: identifier, variant: variant)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try await presence.recordStored(
            identifier, variant: variant, byteSize: data.count, at: now())
        return url
    }

    /// What to draw for a card: its stored artwork, or a named placeholder.
    public func presentation(
        for identifier: ArtworkIdentifier,
        variant: ArtworkVariant,
        cardName: String
    ) async -> ArtworkPresentation {
        if let path = await storedArtworkPath(for: identifier, variant: variant) {
            return .stored(path: path)
        }
        return .placeholder(cardName: cardName)
    }

    /// Empties the image store. Card records are untouched: artwork is the one
    /// part of the catalog that can always be fetched again.
    public func purge() async throws {
        if FileManager.default.fileExists(atPath: rootURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: rootURL)
        }
        try await presence.forgetAll()
    }

    /// Bytes currently held, for the storage budget.
    public func storedByteSize() -> Int { storedFootprint().bytes }

    /// What the store occupies, counted from the disk rather than from the
    /// presence table.
    ///
    /// The table is this application's belief about the files; the disk is the
    /// files. They can disagree — `storedArtworkPath` repairs a record whose
    /// file was removed from outside — and a panel asking the user to reclaim
    /// hundreds of megabytes has to report the thing being reclaimed.
    ///
    /// One walk yields both figures, so the count and the byte total can never
    /// describe two different moments.
    public func storedFootprint() -> ArtworkFootprint {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        else { return ArtworkFootprint(files: 0, bytes: 0) }

        var files = 0
        var bytes = 0
        for entry in enumerator {
            guard let url = entry as? URL,
                  let values = try? url.resourceValues(
                      forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true
            else { continue }
            files += 1
            bytes += values.fileSize ?? 0
        }
        return ArtworkFootprint(files: files, bytes: bytes)
    }
}
