import Foundation
import YGOCore

public enum CatalogClientError: Error, Equatable {
    /// Upstream answered, but with its error envelope instead of data.
    case upstreamReportedError(String)
    case emptyVersionResponse
}

/// Reads the card catalog from the YGOPRODeck public API.
///
/// No credentials are involved: the endpoint is open. What it does demand is
/// pacing, which is the transport's job, and that images are never served from
/// its host, which is the artwork store's job.
public struct YGOProDeckCatalogClient: CatalogFetching {
    /// The version stamp. Around eighty bytes, so it is cheap enough to ask for
    /// on every start before deciding whether the 23 MB dataset is needed.
    public static let versionEndpoint = URL(
        string: "https://db.ygoprodeck.com/api/v7/checkDBVer.php")!
    public static let datasetEndpoint = URL(
        string: "https://db.ygoprodeck.com/api/v7/cardinfo.php")!

    private let transport: any CatalogTransport

    public init(transport: any CatalogTransport) {
        self.transport = transport
    }

    public func fetchVersion() async throws -> CatalogVersion {
        let data = try await transport.data(from: Self.versionEndpoint)
        // The endpoint answers with a single-element array.
        let versions = try JSONDecoder().decode([CatalogVersion].self, from: data)
        guard let version = versions.first else {
            throw CatalogClientError.emptyVersionResponse
        }
        return version
    }

    public func fetchDataset(language: CardLanguage) async throws -> [CatalogCardPayload] {
        let data = try await transport.data(from: Self.datasetURL(for: language))
        return try Self.decodeDataset(data)
    }

    /// `misc=yes` is what carries format membership, release dates and Master
    /// Duel rarity; without it the catalog cannot answer format questions.
    public static func datasetURL(for language: CardLanguage) -> URL {
        var components = URLComponents(url: datasetEndpoint, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "misc", value: "yes")]
        if language != .english {
            items.append(URLQueryItem(name: "language", value: language.rawValue))
        }
        components.queryItems = items
        return components.url!
    }

    /// Decodes a dataset response, turning the upstream error envelope into a
    /// typed failure rather than a decoding error about a missing `data` key.
    public static func decodeDataset(_ data: Data) throws -> [CatalogCardPayload] {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(UpstreamErrorEnvelope.self, from: data) {
            throw CatalogClientError.upstreamReportedError(envelope.error)
        }
        return try decoder.decode(DatasetEnvelope.self, from: data).data
    }

    private struct DatasetEnvelope: Decodable {
        let data: [CatalogCardPayload]
    }

    private struct UpstreamErrorEnvelope: Decodable {
        let error: String
    }
}
