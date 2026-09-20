import Foundation

/// What a synchronisation is doing, and how far along it is.
public struct CatalogSyncProgress: Hashable, Sendable {
    public enum Stage: String, Hashable, Sendable {
        case checkingVersion
        case downloading
        case storing
        case finished
    }

    public let stage: Stage
    public let completed: Int
    public let total: Int

    public init(stage: Stage, completed: Int = 0, total: Int = 0) {
        self.stage = stage
        self.completed = completed
        self.total = total
    }

    /// Zero to one. A stage that cannot count its work reports zero rather
    /// than pretending to a figure it does not have.
    public var proportion: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }
}

/// One upstream snapshot, ready to be stored.
public struct CatalogDataset: Sendable {
    public let english: [CatalogCardPayload]
    public let italian: [CatalogCardPayload]
    public let version: CatalogVersion
    public let observedAt: Date

    public init(
        english: [CatalogCardPayload],
        italian: [CatalogCardPayload] = [],
        version: CatalogVersion,
        observedAt: Date
    ) {
        self.english = english
        self.italian = italian
        self.version = version
        self.observedAt = observedAt
    }
}

/// The storage side of synchronisation.
///
/// Declared here so that the synchroniser can drive persistence without
/// depending on it: `YGOSync` and `YGOPersistence` both see only this.
public protocol CatalogStore: Sendable {
    func cardCount() async throws -> Int
    func storedVersion() async throws -> CatalogVersion?

    /// Stores a whole snapshot. Implementations commit it as one unit: a
    /// failure part way through must leave the previous contents in place.
    func apply(
        _ dataset: CatalogDataset,
        progress: @Sendable @escaping (CatalogSyncProgress) -> Void
    ) async throws
}

/// A synchronisation that did not finish.
public struct CatalogSyncFailure: Error, Sendable {
    public let stage: CatalogSyncProgress.Stage
    public let underlying: any Error
    /// Whether trying again could reasonably succeed. A network failure can;
    /// a malformed upstream payload cannot.
    public let isRetryable: Bool

    public init(stage: CatalogSyncProgress.Stage, underlying: any Error, isRetryable: Bool) {
        self.stage = stage
        self.underlying = underlying
        self.isRetryable = isRetryable
    }
}
