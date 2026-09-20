import Testing
@testable import YGONetworking

/// Virtual time: `sleep` jumps the clock forward instead of waiting, so a test
/// covering a hundred requests across ten seconds finishes in microseconds.
private actor VirtualClock: RateLimiterClock {
    private var seconds: Double = 0

    func now() async -> Double { seconds }

    func sleep(for seconds: Double) async throws {
        guard seconds > 0 else { return }
        self.seconds += seconds
    }

    /// Advances time without a permit being involved.
    func advance(by seconds: Double) { self.seconds += seconds }
}

@Suite("Rate limiter")
struct RateLimiterTests {
    /// Evidence for R4.AC8 and NFR5: across a run of requests, no one-second
    /// interval anywhere on the timeline holds more than the ceiling.
    @Test func neverExceedsTenPermitsInAnyOneSecondWindow() async throws {
        let clock = VirtualClock()
        let limiter = RateLimiter(permitsPerWindow: 10, windowSeconds: 1.0, clock: clock)

        var issuedAt: [Double] = []
        for _ in 0..<100 {
            try await limiter.acquire()
            issuedAt.append(await clock.now())
        }

        #expect(issuedAt.count == 100)

        // Slide a one-second window over every issue time and count what falls
        // inside it. A token bucket starting full would fail exactly here.
        for start in issuedAt {
            let inWindow = issuedAt.filter { $0 >= start && $0 < start + 1.0 }.count
            #expect(inWindow <= 10, "finestra da \(start)s contiene \(inWindow) permessi")
        }

        // Ten per second is also the rate actually achieved, not merely an
        // upper bound met by stalling.
        let span = (issuedAt.last ?? 0) - (issuedAt.first ?? 0)
        #expect(span >= 9.0)
        #expect(span <= 10.0)
    }

    /// Evidence for R4.AC8: a rejection from upstream stops the limiter rather
    /// than letting retries extend the ban.
    @Test func haltsAfterUpstreamRejectsWithTooManyRequests() async throws {
        let clock = VirtualClock()
        let limiter = RateLimiter(permitsPerWindow: 10, windowSeconds: 1.0, clock: clock)

        try await limiter.acquire()
        await limiter.haltAfterUpstreamRejection(retryAfter: 3600)

        #expect(await limiter.isHalted())

        let before = await clock.now()
        try await limiter.acquire()
        let after = await clock.now()

        // The next permit cannot be issued before the stated interval elapsed.
        #expect(after - before >= 3600)
        #expect(await limiter.isHalted() == false)
    }

    /// A second rejection while already halted must extend the pause, never
    /// shorten it.
    @Test func laterRejectionNeverShortensAnActiveHalt() async throws {
        let clock = VirtualClock()
        let limiter = RateLimiter(permitsPerWindow: 10, windowSeconds: 1.0, clock: clock)

        await limiter.haltAfterUpstreamRejection(retryAfter: 3600)
        await limiter.haltAfterUpstreamRejection(retryAfter: 1)

        let before = await clock.now()
        try await limiter.acquire()
        #expect(await clock.now() - before >= 3600)
    }

    /// An idle period empties the window, so the next burst is not penalised
    /// for requests that have long since aged out.
    @Test func idleTimeRestoresFullAllowance() async throws {
        let clock = VirtualClock()
        let limiter = RateLimiter(permitsPerWindow: 10, windowSeconds: 1.0, clock: clock)

        for _ in 0..<10 { try await limiter.acquire() }
        await clock.advance(by: 5)

        let before = await clock.now()
        for _ in 0..<10 { try await limiter.acquire() }
        #expect(await clock.now() == before)
    }
}
