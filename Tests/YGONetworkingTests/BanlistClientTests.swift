import Foundation
import Testing
import YGOCore
@testable import YGONetworking

/// Serves the recorded listings and bodies, so no test reaches a live host.
struct RecordedBanlistTransport: CatalogTransport {
    static let directory: URL = Fixture.directory.appending(path: "banlist")

    var failingHosts: Set<String> = []

    func data(from url: URL) async throws -> Data {
        if let host = url.host(), failingHosts.contains(host) {
            throw URLError(.cannotConnectToHost)
        }

        if url.host() == "api.github.com" {
            let format = url.lastPathComponent
            return try Data(contentsOf: Self.directory
                .appending(path: "\(format)-index.json"))
        }

        let components = url.pathComponents.suffix(2)
        return try Data(contentsOf: Self.directory
            .appending(path: components.joined(separator: "/")))
    }
}

@Suite("Banlist client")
struct BanlistClientTests {
    private func client(failing hosts: Set<String> = []) -> YAMLYugiBanlistClient {
        YAMLYugiBanlistClient(
            transport: RecordedBanlistTransport(failingHosts: hosts))
    }

    /// Evidence for R1.AC1: enumeration finds every list the source publishes,
    /// from the first one to the current one, and the four formats together
    /// come to 177.
    @Test func enumeratesSeventyThreeTCGListsFromNineteenNinetyNine() async throws {
        let dates = try await client().availableDates(for: .tcg)

        #expect(dates.count == 73)
        #expect(dates.first == "1999-08-01")
        #expect(dates.last == "2026-05-18")
        #expect(dates == dates.sorted())
        #expect(Set(dates).count == dates.count)
        #expect(dates.contains("2005-03-01"))
        // The European effective date, which is the one that applies here.
        #expect(dates.contains("2024-04-22"))
        #expect(!dates.contains("2024-04-15"))

        var total = 0
        for format in BanlistFormat.allCases {
            total += try await client().availableDates(for: format).count
        }
        #expect(total == 177)
    }

    /// Evidence for R1.AC1: `current` is a pointer at the newest dated list and
    /// `upcoming` is a list not yet in force. Counting either would file one
    /// list twice. The directories also hold `.raw.json`, `.name.json`, `.csv`
    /// and `.html` renderings of the same lists, which are equally skipped.
    @Test func skipsTheCurrentAndUpcomingPointers() async throws {
        let dates = try await client().availableDates(for: .tcg)
        #expect(!dates.contains { $0.contains("current") || $0.contains("upcoming") })

        // The listing did carry the pointer, so the filter is what removed it.
        let index = try await RecordedBanlistTransport().data(
            from: YAMLYugiBanlistClient.indexURL(for: .tcg))
        let names = try JSONDecoder().decode([[String: String]].self, from: index)
            .compactMap { $0["name"] }
        #expect(names.contains("current.vector.json"))
        #expect(names.contains("2026-05-18.raw.json"))
        #expect(names.contains("options.json"))
        #expect(names.filter { $0.hasSuffix(".vector.json") }.count == dates.count + 1)

        // The pointer resolves to a date that was enumerated anyway.
        let newest = try await client().fetchList(.tcg, effectiveDate: "2026-05-18")
        #expect(newest.effectiveDate == "2026-05-18")

        for name in ["current.vector.json", "upcoming.vector.json",
                     "2026-05-18.raw.json", "202601.csv", "202601.html",
                     "2026-01-08.name.json", "options.json"] {
            #expect(YAMLYugiBanlistClient.effectiveDate(fromFileName: name) == nil, "\(name)")
        }
        #expect(YAMLYugiBanlistClient.effectiveDate(fromFileName: "2026-05-18.vector.json")
                == "2026-05-18")
    }

    /// Evidence for R1.AC5: an unreachable source is reported, naming the
    /// format that could not be read, rather than surfacing as an empty list of
    /// dates that a caller would read as "nothing published".
    @Test func reportsFailureWhenTheSourceIsUnreachable() async throws {
        let offline = client(failing: ["api.github.com", "dawnbrandbots.github.io"])

        await #expect(throws: BanlistClientError.self) {
            try await offline.availableDates(for: .tcg)
        }

        do {
            _ = try await offline.availableDates(for: .ocg)
            Issue.record("enumeration should have failed")
        } catch let error as BanlistClientError {
            guard case let .enumerationFailed(format, reason) = error else {
                Issue.record("wrong case: \(error)")
                return
            }
            #expect(format == .ocg)
            #expect(!reason.isEmpty)
        }
    }

    /// Evidence for R1.AC5: the dated paths are served but undocumented. If
    /// they stopped being served, enumeration would still succeed and every
    /// body would fail, which is the same containment as an unreachable source.
    @Test func reportsFailureWhenEnumerationSucceedsAndBodiesDoNot() async throws {
        let partial = client(failing: ["dawnbrandbots.github.io"])

        let dates = try await partial.availableDates(for: .tcg)
        #expect(dates.count == 73)

        do {
            _ = try await partial.fetchList(.tcg, effectiveDate: "2005-03-01")
            Issue.record("body fetch should have failed")
        } catch let error as BanlistClientError {
            guard case let .listUnavailable(format, date, _) = error else {
                Issue.record("wrong case: \(error)")
                return
            }
            #expect(format == .tcg)
            #expect(date == "2005-03-01")
        }

        // A body that arrives but is not a list is refused just as clearly.
        struct Garbage: CatalogTransport {
            func data(from url: URL) async throws -> Data { Data("[]".utf8) }
        }
        await #expect(throws: BanlistClientError.self) {
            try await YAMLYugiBanlistClient(transport: Garbage())
                .fetchList(.tcg, effectiveDate: "2005-03-01")
        }
    }
}
