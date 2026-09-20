import Foundation

/// Locates the repository's `fixtures/` directory from this file's own path, so
/// tests read the recorded responses without a resource bundle.
enum Fixture {
    static let directory: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()   // YGONetworkingTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root
        .appending(path: "fixtures")

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appending(path: name))
    }
}
