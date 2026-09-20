import Foundation
import GRDB
import Testing
import YGOCore
import YGONetworking
import YGOPersistence

enum SyncFixture {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func cards(_ name: String) throws -> [CatalogCardPayload] {
        try YGOProDeckCatalogClient.decodeDataset(
            Data(contentsOf: root.appending(path: "fixtures/\(name)")))
    }

    static let observedAt = Date(timeIntervalSince1970: 1_758_000_000)

    static func migratedDatabase() throws -> DatabaseQueue {
        var configuration = GRDB.Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: configuration)
        try CatalogSchema.migrator.migrate(queue)
        return queue
    }
}

enum StubError: Error, Equatable {
    case unreachable
    case storageRefused
}

/// A client answering from fixtures, recording what was asked for and able to
/// fail on demand. No test reaches a live host.
actor StubCatalogClient: CatalogFetching {
    enum Call: Equatable { case version, dataset(CardLanguage) }

    private(set) var calls: [Call] = []
    private var version: CatalogVersion
    private var english: [CatalogCardPayload]
    private let italian: [CatalogCardPayload]
    private var versionFailure: StubError?
    private var datasetFailure: StubError?

    init(
        version: CatalogVersion,
        english: [CatalogCardPayload],
        italian: [CatalogCardPayload] = [],
        versionFailure: StubError? = nil,
        datasetFailure: StubError? = nil
    ) {
        self.version = version
        self.english = english
        self.italian = italian
        self.versionFailure = versionFailure
        self.datasetFailure = datasetFailure
    }

    func fetchVersion() async throws -> CatalogVersion {
        calls.append(.version)
        if let versionFailure { throw versionFailure }
        return version
    }

    func fetchDataset(language: CardLanguage) async throws -> [CatalogCardPayload] {
        calls.append(.dataset(language))
        if let datasetFailure { throw datasetFailure }
        return language == .english ? english : italian
    }

    /// Swaps in a different payload, standing in for upstream publishing a
    /// changed dataset under a new version.
    func replaceEnglish(with cards: [CatalogCardPayload]) {
        english = cards
    }

    func advanceVersion(to databaseVersion: String) {
        version = CatalogVersion(databaseVersion: databaseVersion, lastUpdate: "2026-09-18 00:00:00")
    }

    var datasetRequestCount: Int {
        calls.filter { if case .dataset = $0 { true } else { false } }.count
    }
}

/// Wraps the real SQLite store so a test can make storage fail without
/// weakening the store itself.
struct RefusingCatalogStore: CatalogStore {
    let wrapped: SQLiteCatalogStore

    func cardCount() async throws -> Int { try await wrapped.cardCount() }
    func storedVersion() async throws -> CatalogVersion? { try await wrapped.storedVersion() }

    func apply(
        _ dataset: CatalogDataset,
        progress: @Sendable @escaping (CatalogSyncProgress) -> Void
    ) async throws {
        throw StubError.storageRefused
    }
}

/// Collects every progress report in order.
final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [CatalogSyncProgress] = []

    var observer: @Sendable (CatalogSyncProgress) -> Void {
        { [self] progress in
            lock.lock(); defer { lock.unlock() }
            reports.append(progress)
        }
    }

    var recorded: [CatalogSyncProgress] {
        lock.lock(); defer { lock.unlock() }
        return reports
    }
}
