import Foundation

/// Paces every outbound request to the upstream catalog and image hosts.
///
/// This is the only place in the application that can breach the upstream
/// limit, which is why both the JSON client and the image fetcher acquire from
/// one shared instance rather than pacing themselves.
///
/// The upstream ceiling is twenty requests per second with a one-hour ban for
/// exceeding it; the default here is half that, so an accounting error costs
/// throughput rather than an hour of downtime.
///
/// A token bucket is deliberately not used: a full bucket lets through a burst
/// of ten and then a steady stream, which puts nineteen requests inside one
/// sliding second. This keeps the timestamps of recent permits and refuses to
/// let any one-second window hold more than the ceiling.
public actor RateLimiter {
    private let permitsPerWindow: Int
    private let windowSeconds: Double
    private let clock: any RateLimiterClock

    /// Issue times of the permits still inside the window, oldest first.
    private var recentPermits: [Double] = []
    /// Set when upstream reports the limit was exceeded; no permit is issued
    /// before this instant.
    private var haltedUntil: Double?

    public init(
        permitsPerWindow: Int = 10,
        windowSeconds: Double = 1.0,
        clock: any RateLimiterClock = SystemRateLimiterClock()
    ) {
        self.permitsPerWindow = permitsPerWindow
        self.windowSeconds = windowSeconds
        self.clock = clock
    }

    /// Waits until issuing a request keeps the window within its ceiling.
    public func acquire() async throws {
        while true {
            let now = await clock.now()

            if let haltedUntil, now < haltedUntil {
                try await clock.sleep(for: haltedUntil - now)
                continue
            }

            discardPermitsOlderThanWindow(now: now)

            if recentPermits.count < permitsPerWindow {
                recentPermits.append(now)
                return
            }

            // Wait for the oldest permit to age out of the window.
            let oldest = recentPermits[0]
            try await clock.sleep(for: max(oldest + windowSeconds - now, 0))
        }
    }

    /// Records that upstream rejected a request for exceeding its limit.
    ///
    /// Retrying into an active ban only lengthens it, so the limiter stops
    /// issuing permits entirely until the stated interval has passed.
    public func haltAfterUpstreamRejection(retryAfter seconds: Double) async {
        let now = await clock.now()
        haltedUntil = max(haltedUntil ?? now, now + seconds)
    }

    /// Whether the limiter is currently refusing to issue permits.
    public func isHalted() async -> Bool {
        guard let haltedUntil else { return false }
        return await clock.now() < haltedUntil
    }

    private func discardPermitsOlderThanWindow(now: Double) {
        let cutoff = now - windowSeconds
        if let firstInside = recentPermits.firstIndex(where: { $0 > cutoff }) {
            recentPermits.removeFirst(firstInside)
        } else {
            recentPermits.removeAll(keepingCapacity: true)
        }
    }
}
