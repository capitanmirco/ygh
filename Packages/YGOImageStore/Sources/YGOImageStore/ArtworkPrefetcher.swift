import Foundation
import YGOCore

/// Fills the local artwork store in the background.
///
/// Thumbnails for the whole pool are about 350 MB, which is worth holding so
/// that browsing is instant and works offline. Full-resolution images are two
/// gigabytes, so those are fetched only when a card is actually opened.
public actor ArtworkPrefetcher {
    public struct Progress: Hashable, Sendable {
        public let stored: Int
        public let total: Int

        public var proportion: Double {
            guard total > 0 else { return 0 }
            return min(1, Double(stored) / Double(total))
        }
    }

    /// Why a prefetch run stopped.
    public enum Outcome: Hashable, Sendable {
        case completed(stored: Int)
        /// Upstream stopped answering. The gaps stay recorded, so the next run
        /// picks up exactly where this one left off.
        case interrupted(stored: Int, failures: Int)
        case nothingToDo
    }

    private let store: ArtworkStore
    private let presence: any ArtworkPresenceTracking
    private let fetcher: any ArtworkFetching
    private let observe: @Sendable (Progress) -> Void
    private let consecutiveFailureLimit: Int

    public init(
        store: ArtworkStore,
        presence: any ArtworkPresenceTracking,
        fetcher: any ArtworkFetching,
        consecutiveFailureLimit: Int = 5,
        observe: @escaping @Sendable (Progress) -> Void = { _ in }
    ) {
        self.store = store
        self.presence = presence
        self.fetcher = fetcher
        self.consecutiveFailureLimit = consecutiveFailureLimit
        self.observe = observe
    }

    /// Retrieves every thumbnail the store does not already hold.
    ///
    /// The work list comes from an anti-join against the presence table, so an
    /// interrupted run resumes by asking for exactly the gaps rather than
    /// re-checking every file.
    @discardableResult
    public func prefetchThumbnails() async throws -> Outcome {
        let missing = try await presence.missing(variant: .thumbnail, limit: nil)
        let total = try await presence.totalArtworkCount()
        var stored = try await presence.storedCount(variant: .thumbnail)

        guard !missing.isEmpty else { return .nothingToDo }
        observe(Progress(stored: stored, total: total))

        var consecutiveFailures = 0
        var retrieved = 0

        for identifier in missing {
            if Task.isCancelled {
                return .interrupted(stored: retrieved, failures: consecutiveFailures)
            }

            do {
                let data = try await fetcher.imageData(for: identifier, variant: .thumbnail)
                try await store.store(data, for: identifier, variant: .thumbnail)
                consecutiveFailures = 0
                retrieved += 1
                stored += 1
                observe(Progress(stored: stored, total: total))
            } catch {
                consecutiveFailures += 1
                // Hammering an unreachable or annoyed host makes things worse,
                // and the gaps are already recorded for the next attempt.
                if consecutiveFailures >= consecutiveFailureLimit {
                    return .interrupted(stored: retrieved, failures: consecutiveFailures)
                }
            }
        }

        return .completed(stored: retrieved)
    }

    /// Ensures a card's full-resolution image is held, fetching it only the
    /// first time the card is opened.
    @discardableResult
    public func ensureFullImage(
        for identifier: ArtworkIdentifier,
        cardName: String
    ) async -> ArtworkPresentation {
        if let path = await store.storedArtworkPath(for: identifier, variant: .full) {
            return .stored(path: path)
        }

        do {
            let data = try await fetcher.imageData(for: identifier, variant: .full)
            let url = try await store.store(data, for: identifier, variant: .full)
            return .stored(path: url.path(percentEncoded: false))
        } catch {
            // An unreachable image host must not leave a blank hole in the
            // interface; the card stays identifiable by name.
            return .placeholder(cardName: cardName)
        }
    }
}
