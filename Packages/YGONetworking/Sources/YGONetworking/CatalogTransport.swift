import Foundation
import YGOCore

/// Performs one HTTP GET.
///
/// The client is written against this rather than `URLSession` so that tests
/// run against recorded fixtures: the project constitution forbids a test
/// reaching a live host.
public protocol CatalogTransport: Sendable {
    func data(from url: URL) async throws -> Data
}

public enum CatalogTransportError: Error, Equatable {
    case rejectedByUpstream(statusCode: Int)
    case rateLimited(retryAfter: Double)
}

/// The real transport: every request takes a permit from the shared limiter
/// first, and a rejection halts that limiter rather than being retried.
public struct URLSessionCatalogTransport: CatalogTransport {
    private let session: URLSession
    private let limiter: RateLimiter

    public init(session: URLSession = .shared, limiter: RateLimiter) {
        self.session = session
        self.limiter = limiter
    }

    public func data(from url: URL) async throws -> Data {
        try await limiter.acquire()
        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse else { return data }

        switch http.statusCode {
        case 200..<300:
            return data
        case 429:
            // Retrying into an active ban only lengthens it.
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")
                .flatMap(Double.init)) ?? 3600
            await limiter.haltAfterUpstreamRejection(retryAfter: retryAfter)
            throw CatalogTransportError.rateLimited(retryAfter: retryAfter)
        default:
            throw CatalogTransportError.rejectedByUpstream(statusCode: http.statusCode)
        }
    }
}
