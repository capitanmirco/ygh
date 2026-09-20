import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOImageStore

private enum FetchFailure: Error { case unreachable }

/// Answers with stand-in bytes, records what was asked for, and can be made to
/// fail or to block. No test here reaches the image host.
private actor StubArtworkFetcher: ArtworkFetching {
    private(set) var requested: [(ArtworkIdentifier, ArtworkVariant)] = []
    private var failing = false
    private var gate: CheckedContinuation<Void, Never>?
    private var waitForGate = false

    init(failing: Bool = false, waitForGate: Bool = false) {
        self.failing = failing
        self.waitForGate = waitForGate
    }

    func imageData(
        for identifier: ArtworkIdentifier,
        variant: ArtworkVariant
    ) async throws -> Data {
        requested.append((identifier, variant))
        if waitForGate {
            waitForGate = false
            await withCheckedContinuation { gate = $0 }
        }
        if failing { throw FetchFailure.unreachable }
        return Data("image-\(identifier.rawValue)-\(variant.rawValue)".utf8)
    }

    func openGate() {
        gate?.resume()
        gate = nil
    }

    func startFailing() { failing = true }
    func stopFailing() { failing = false }

    var requestedThumbnails: [ArtworkIdentifier] {
        requested.filter { $0.1 == .thumbnail }.map(\.0)
    }
    var requestCount: Int { requested.count }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [ArtworkPrefetcher.Progress] = []

    var observer: @Sendable (ArtworkPrefetcher.Progress) -> Void {
        { [self] progress in
            lock.lock(); defer { lock.unlock() }
            entries.append(progress)
        }
    }

    var recorded: [ArtworkPrefetcher.Progress] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }
}

@Suite("Artwork prefetch")
struct ArtworkPrefetchTests {
    private struct Rig {
        let store: ArtworkStore
        let presence: SQLiteArtworkPresence
        let database: DatabaseQueue
        let directory: URL
        let artworkIDs: [Int]
    }

    private func rig() throws -> Rig {
        let (database, directory) = try ArtworkFixture.seededDatabase()
        let presence = SQLiteArtworkPresence(database: database)
        return Rig(
            store: ArtworkStore(rootURL: directory, presence: presence,
                                now: { ArtworkFixture.storedAt }),
            presence: presence,
            database: database,
            directory: directory,
            artworkIDs: try ArtworkFixture.cards().flatMap { $0.cardImages.map(\.id) })
    }

    /// Evidence for R4.AC2: once the catalog is seeded, thumbnails fill in on
    /// their own with no further user action.
    @Test func beginsThumbnailRetrievalAfterSeedCompletes() async throws {
        let rig = try rig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        let before = try await rig.presence.storedCount(variant: .thumbnail)
        #expect(before == 0)

        let fetcher = StubArtworkFetcher()
        let outcome = try await ArtworkPrefetcher(
            store: rig.store, presence: rig.presence, fetcher: fetcher).prefetchThumbnails()

        #expect(outcome == .completed(stored: rig.artworkIDs.count))
        let after = try await rig.presence.storedCount(variant: .thumbnail)
        #expect(after == rig.artworkIDs.count)

        // Only thumbnails: the two gigabytes of full images are not pulled down.
        let fullRequests = await fetcher.requested.filter { $0.1 == .full }
        #expect(fullRequests.isEmpty)
    }

    /// Evidence for R4.AC3: the run reports how many it holds against how many
    /// there are, and that figure climbs.
    @Test func reportsStoredCountAdvancingAgainstExpectedTotal() async throws {
        let rig = try rig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        let log = ProgressLog()
        _ = try await ArtworkPrefetcher(
            store: rig.store, presence: rig.presence,
            fetcher: StubArtworkFetcher(), observe: log.observer).prefetchThumbnails()

        let entries = log.recorded
        #expect(entries.count > 2)
        #expect(entries.allSatisfy { $0.total == rig.artworkIDs.count })

        let stored = entries.map(\.stored)
        #expect(stored == stored.sorted())
        #expect(stored.first == 0)
        #expect(stored.last == rig.artworkIDs.count)
        #expect(entries.last?.proportion == 1)
    }

    /// Evidence for R4.AC4: retrieval runs beside the catalog rather than in
    /// front of it, so the grid stays usable while images arrive.
    @Test func answersSearchWhilePrefetchIsRunning() async throws {
        let rig = try rig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        let fetcher = StubArtworkFetcher(waitForGate: true)
        let prefetcher = ArtworkPrefetcher(
            store: rig.store, presence: rig.presence, fetcher: fetcher)

        let running = Task { try await prefetcher.prefetchThumbnails() }

        // While the first retrieval is held open, the catalog still answers.
        let repository = SQLiteCardRepository(database: rig.database)
        let count = try await repository.cardCount()
        #expect(count == 35)

        let firstCard = try #require(try ArtworkFixture.cards().first)
        let card = try await repository.card(with: CardIdentifier(firstCard.id))
        #expect(card?.englishName == firstCard.name)

        await fetcher.openGate()
        let outcome = try await running.value
        #expect(outcome == .completed(stored: rig.artworkIDs.count))
    }

    /// Evidence for R4.AC5: a resumed run asks for exactly the gaps, never for
    /// what is already on disk.
    @Test func requestsOnlyMissingThumbnailsAfterInterruption() async throws {
        let rig = try rig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        // A first run stores part of the set, then upstream stops answering.
        let firstFetcher = StubArtworkFetcher()
        let partial = Array(rig.artworkIDs.prefix(12)).map { ArtworkIdentifier($0) }
        for identifier in partial {
            let data = try await firstFetcher.imageData(for: identifier, variant: .thumbnail)
            try await rig.store.store(data, for: identifier, variant: .thumbnail)
        }

        let storedAfterInterruption = try await rig.presence.storedCount(variant: .thumbnail)
        #expect(storedAfterInterruption == 12)

        // The next run must ask only for what is missing.
        let resumeFetcher = StubArtworkFetcher()
        let outcome = try await ArtworkPrefetcher(
            store: rig.store, presence: rig.presence,
            fetcher: resumeFetcher).prefetchThumbnails()

        let requested = await resumeFetcher.requestedThumbnails
        #expect(requested.count == rig.artworkIDs.count - 12)
        #expect(Set(requested).isDisjoint(with: Set(partial)))
        #expect(outcome == .completed(stored: rig.artworkIDs.count - 12))

        // And a third run has nothing left to do.
        let idleFetcher = StubArtworkFetcher()
        let idle = try await ArtworkPrefetcher(
            store: rig.store, presence: rig.presence, fetcher: idleFetcher).prefetchThumbnails()
        #expect(idle == .nothingToDo)
        let idleRequests = await idleFetcher.requestCount
        #expect(idleRequests == 0)
    }

    /// A run against an unreachable host gives up rather than grinding through
    /// fourteen thousand failures, and leaves the gaps recorded.
    @Test func stopsAfterRepeatedFailuresAndKeepsGapsForLater() async throws {
        let rig = try rig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        let fetcher = StubArtworkFetcher(failing: true)
        let outcome = try await ArtworkPrefetcher(
            store: rig.store, presence: rig.presence,
            fetcher: fetcher, consecutiveFailureLimit: 3).prefetchThumbnails()

        #expect(outcome == .interrupted(stored: 0, failures: 3))
        let attempts = await fetcher.requestCount
        #expect(attempts == 3, "doveva fermarsi al limite, non provarle tutte")

        let stored = try await rig.presence.storedCount(variant: .thumbnail)
        #expect(stored == 0)
    }

    /// Evidence for R4.AC6: the full image arrives when the card is opened, and
    /// opening it again costs nothing.
    @Test func retrievesFullImageOnDetailOpenAndNotAgain() async throws {
        let rig = try rig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        let fetcher = StubArtworkFetcher()
        let prefetcher = ArtworkPrefetcher(
            store: rig.store, presence: rig.presence, fetcher: fetcher)
        let identifier = ArtworkIdentifier(try #require(rig.artworkIDs.first))

        let first = await prefetcher.ensureFullImage(for: identifier, cardName: "Pot of Greed")
        guard case .stored(let path) = first else {
            Issue.record("attesa immagine memorizzata, ricevuto \(first)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: path))
        let afterFirst = await fetcher.requestCount
        #expect(afterFirst == 1)

        let second = await prefetcher.ensureFullImage(for: identifier, cardName: "Pot of Greed")
        #expect(second == first)
        let afterSecond = await fetcher.requestCount
        #expect(afterSecond == 1, "la seconda apertura non deve scaricare di nuovo")
    }

    /// Evidence for R4.AC7: a card with no usable image is still an
    /// identifiable element rather than a blank one.
    @Test func yieldsNamedPlaceholderWhenArtworkUnavailable() async throws {
        let rig = try rig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        let prefetcher = ArtworkPrefetcher(
            store: rig.store, presence: rig.presence,
            fetcher: StubArtworkFetcher(failing: true))
        let identifier = ArtworkIdentifier(try #require(rig.artworkIDs.first))

        let presentation = await prefetcher.ensureFullImage(
            for: identifier, cardName: "Anfora dell'Avidità")
        #expect(presentation == .placeholder(cardName: "Anfora dell'Avidità"))

        // The store agrees: nothing was written, and its own presentation for
        // an absent artwork is the same named placeholder.
        let fromStore = await rig.store.presentation(
            for: identifier, variant: .full, cardName: "Anfora dell'Avidità")
        #expect(fromStore == .placeholder(cardName: "Anfora dell'Avidità"))
    }
}
