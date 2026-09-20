import Foundation
import Testing
import YGOCore
@testable import YGONetworking

/// Answers from recorded responses and remembers what was asked for, in order.
/// No test in this suite reaches a live host.
private actor RecordingTransport: CatalogTransport {
    private(set) var requested: [URL] = []
    private var responses: [String: Data] = [:]

    init(responses: [String: Data]) {
        self.responses = responses
    }

    func data(from url: URL) async throws -> Data {
        requested.append(url)
        guard let body = responses[url.path()] else {
            throw CatalogTransportError.rejectedByUpstream(statusCode: 404)
        }
        return body
    }

    var requestedPaths: [String] { requested.map { $0.path() } }
}

@Suite("Catalog client")
struct CatalogClientTests {
    private func transport() throws -> RecordingTransport {
        RecordingTransport(responses: [
            "/api/v7/checkDBVer.php": try Fixture.data("checkdbver.json"),
            "/api/v7/cardinfo.php": try Fixture.data("catalog-en.json"),
        ])
    }

    /// Evidence for R2.AC1: asking for the catalog version is a request of its
    /// own and never drags the dataset along with it. The version response is
    /// eighty bytes; the dataset is twenty-three megabytes, so conflating them
    /// would make every start pay for a download it may not need.
    @Test func requestsCatalogVersionBeforeAnyDataset() async throws {
        let transport = try transport()
        let client = YGOProDeckCatalogClient(transport: transport)

        _ = try await client.fetchVersion()

        var paths = await transport.requestedPaths
        #expect(paths == ["/api/v7/checkDBVer.php"])
        #expect(!paths.contains("/api/v7/cardinfo.php"))

        _ = try await client.fetchDataset(language: .english)

        paths = await transport.requestedPaths
        #expect(paths == ["/api/v7/checkDBVer.php", "/api/v7/cardinfo.php"])
    }

    @Test func readsVersionFromTheRecordedUpstreamResponse() async throws {
        let client = YGOProDeckCatalogClient(transport: try transport())

        let version = try await client.fetchVersion()

        #expect(!version.databaseVersion.isEmpty)
        #expect(!version.lastUpdate.isEmpty)
    }

    @Test func decodesTheRecordedEnglishDataset() async throws {
        let client = YGOProDeckCatalogClient(transport: try transport())

        let cards = try await client.fetchDataset(language: .english)

        // Derived from the fixture rather than pinned, so extending it for a
        // later feature does not turn this into a false failure.
        let expected = try YGOProDeckCatalogClient.decodeDataset(Fixture.data("catalog-en.json")).count
        #expect(cards.count == expected)
        #expect(cards.count > 30)
        #expect(cards.allSatisfy { !$0.cardImages.isEmpty })
        // The fixture was built to carry a card with three artworks, which is
        // what makes alias resolution testable downstream.
        #expect(cards.contains { $0.cardImages.count >= 3 })
        #expect(cards.contains { $0.banlistInfo != nil })
    }

    /// `misc=yes` carries format membership and release dates; a dataset
    /// fetched without it cannot answer a format question.
    @Test func alwaysRequestsExtendedFieldsAndTagsTheLanguage() {
        let english = YGOProDeckCatalogClient.datasetURL(for: .english)
        let italian = YGOProDeckCatalogClient.datasetURL(for: .italian)

        #expect(english.query()?.contains("misc=yes") == true)
        #expect(english.query()?.contains("language") == false)
        #expect(italian.query()?.contains("misc=yes") == true)
        #expect(italian.query()?.contains("language=it") == true)
    }

    /// Upstream reports a bad query with a JSON error envelope and a 200, so it
    /// has to become a typed failure rather than a confusing decoding error.
    @Test func reportsUpstreamErrorEnvelopeAsTypedFailure() async {
        let envelope = Data(#"{"error": "No card matching your query was found."}"#.utf8)

        #expect(throws: CatalogClientError.self) {
            try YGOProDeckCatalogClient.decodeDataset(envelope)
        }
    }
}
