import Foundation

/// The passage of time as the rate limiter sees it.
///
/// Injecting it keeps the limiter's tests deterministic and instantaneous: a
/// test drives a hundred acquisitions through virtual time rather than waiting
/// ten real seconds for them.
public protocol RateLimiterClock: Sendable {
    /// Monotonic seconds since this clock started.
    func now() async -> Double
    func sleep(for seconds: Double) async throws
}

/// Wall-clock implementation backed by a monotonic source, so that a system
/// clock adjustment cannot make the limiter issue a burst.
public struct SystemRateLimiterClock: RateLimiterClock {
    private let origin: ContinuousClock.Instant

    public init() {
        origin = ContinuousClock.now
    }

    public func now() async -> Double {
        let elapsed = origin.duration(to: ContinuousClock.now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }

    public func sleep(for seconds: Double) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(for: .seconds(seconds))
    }
}
