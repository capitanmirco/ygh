import Testing
@testable import YGOCore

/// Stands in for the actors that own networking, synchronisation and the
/// artwork store: if a domain value cannot cross an actor boundary, the module
/// graph does not satisfy the project's strict-concurrency rule.
private actor IsolationProbe {
    func roundTrip<Value: Sendable>(_ value: Value) -> Value { value }
}

@Suite("Toolchain harness")
struct ToolchainHarnessTests {
    /// Evidence for NFR7: the package builds in Swift 6 language mode and a
    /// domain value crosses an actor boundary without an isolation escape.
    @Test func buildsUnderStrictConcurrency() async {
        let probe = IsolationProbe()
        let identifier = CardIdentifier(55144522)

        let returned = await probe.roundTrip(identifier)

        #expect(returned == identifier)
        #expect(returned.description == "55144522")
    }
}
