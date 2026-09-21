import Foundation
import YGOCore

public enum BanlistClientError: Error, Equatable {
    case enumerationFailed(format: BanlistFormat, reason: String)
    case listUnavailable(format: BanlistFormat, effectiveDate: String, reason: String)
}

/// Reads the published Forbidden & Limited Lists from `yaml-yugi-limit-regulation`.
///
/// Two hosts for one source, which is worth naming rather than discovering from
/// a failure. The project documents only `current.vector.json` and
/// `upcoming.vector.json`; the dated bodies are served but nothing publishes an
/// index of them, so the dates come from the GitHub contents API and the bodies
/// from GitHub Pages.
public struct YAMLYugiBanlistClient: BanlistFetching {
    public static let source = "yaml-yugi-limit-regulation"

    /// Lists a format's directory. Rate limited to sixty an hour
    /// unauthenticated, and four calls cover every format.
    public static func indexURL(for format: BanlistFormat) -> URL {
        URL(string: "https://api.github.com/repos/DawnbrandBots/"
            + "yaml-yugi-limit-regulation/contents/data/\(format.rawValue)")!
    }

    public static func listURL(for format: BanlistFormat, effectiveDate: String) -> URL {
        URL(string: "https://dawnbrandbots.github.io/yaml-yugi-limit-regulation/"
            + "\(format.rawValue)/\(effectiveDate).vector.json")!
    }

    /// `current` points at the newest dated list and `upcoming` is a list not
    /// yet in force. Both are skipped: storing them would file one list twice
    /// under two names, and a list that has not taken effect is not history.
    static let pointerNames: Set<String> = ["current.vector.json", "upcoming.vector.json"]

    private struct IndexEntry: Decodable {
        let name: String
    }

    private let transport: any CatalogTransport

    public init(transport: any CatalogTransport) {
        self.transport = transport
    }

    public func availableDates(for format: BanlistFormat) async throws -> [String] {
        let data: Data
        do {
            data = try await transport.data(from: Self.indexURL(for: format))
        } catch {
            throw BanlistClientError.enumerationFailed(
                format: format, reason: String(describing: error))
        }

        let entries: [IndexEntry]
        do {
            entries = try JSONDecoder().decode([IndexEntry].self, from: data)
        } catch {
            throw BanlistClientError.enumerationFailed(
                format: format, reason: "listing is not a directory: \(error)")
        }

        return entries
            .map(\.name)
            .filter { !Self.pointerNames.contains($0) }
            .compactMap(Self.effectiveDate(fromFileName:))
            .sorted()
    }

    public func fetchList(
        _ format: BanlistFormat, effectiveDate: String
    ) async throws -> PublishedBanlist {
        let data: Data
        do {
            data = try await transport.data(
                from: Self.listURL(for: format, effectiveDate: effectiveDate))
        } catch {
            throw BanlistClientError.listUnavailable(
                format: format, effectiveDate: effectiveDate,
                reason: String(describing: error))
        }

        do {
            return try JSONDecoder().decode(PublishedBanlist.self, from: data)
        } catch {
            throw BanlistClientError.listUnavailable(
                format: format, effectiveDate: effectiveDate,
                reason: "body is not a published list: \(error)")
        }
    }

    /// A dated body is `YYYY-MM-DD.vector.json`. The directories also hold
    /// `.raw.json`, `.name.json`, `.csv` and `.html` renderings of the same
    /// lists; taking any of them would count a list more than once.
    static func effectiveDate(fromFileName name: String) -> String? {
        guard name.hasSuffix(".vector.json") else { return nil }
        let date = String(name.dropLast(".vector.json".count))
        guard date.count == 10 else { return nil }
        let parts = date.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) })
        else { return nil }
        return date
    }
}
