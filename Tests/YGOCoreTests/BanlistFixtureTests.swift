import Foundation
import Testing
@testable import YGOCore

/// Locates `fixtures/banlist/` from this file's own path, so the recorded
/// lists are read without a resource bundle.
enum BanlistFixture {
    static let directory: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()   // YGOCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root
        .appending(path: "fixtures")
        .appending(path: "banlist")

    /// Every dated body recorded for a format, oldest first.
    static func datedFiles(_ format: BanlistFormat) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory.appending(path: format.rawValue),
            includingPropertiesForKeys: nil)
        return contents
            .filter { $0.lastPathComponent.hasSuffix(".vector.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func list(_ format: BanlistFormat, _ date: String) throws -> PublishedBanlist {
        let data = try Data(contentsOf: directory
            .appending(path: format.rawValue)
            .appending(path: "\(date).vector.json"))
        return try JSONDecoder().decode(PublishedBanlist.self, from: data)
    }

    /// The directory listing as the contents API returned it.
    static func index(_ format: BanlistFormat) throws -> [String] {
        struct Entry: Decodable { let name: String }
        let data = try Data(contentsOf: directory.appending(path: "\(format.rawValue)-index.json"))
        return try JSONDecoder().decode([Entry].self, from: data).map(\.name)
    }
}

@Suite("Banlist fixtures")
struct BanlistFixtureTests {
    /// The counts the whole specification rests on. Recorded whole rather than
    /// sampled, because `R1.AC1` compares a stored count against a published
    /// one and three sampled lists could not check that.
    ///
    /// `current.vector.json` is a pointer at the newest dated list, not a list
    /// of its own: for the TCG it reports 2026-05-18, which is already recorded
    /// as a dated file. Counting it would double the newest list.
    @Test func recordsEveryPublishedListAcrossTheFourFormats() throws {
        let expected: [BanlistFormat: Int] = [
            .tcg: 73, .ocg: 23, .masterDuel: 66, .rush: 15,
        ]

        var total = 0
        for format in BanlistFormat.allCases {
            let files = try BanlistFixture.datedFiles(format)
            #expect(files.count == expected[format], "\(format.rawValue)")
            total += files.count

            // Every recorded body is a dated one; the pointers stay out.
            #expect(!files.contains { $0.lastPathComponent == "current.vector.json" })
            #expect(!files.contains { $0.lastPathComponent == "upcoming.vector.json" })

            // The listing that produced them is recorded alongside.
            let index = try BanlistFixture.index(format)
            #expect(index.contains("current.vector.json"))
            #expect(index.filter { $0.hasSuffix(".vector.json") }.count == files.count + 1)
        }
        #expect(total == 177)

        // The pointer resolves to a list that was recorded.
        let current = try BanlistFixture.list(.tcg, "2026-05-18")
        #expect(current.effectiveDate == "2026-05-18")
    }

    /// Evidence for R1.AC3, on a real list rather than a constructed one: the
    /// March 2005 TCG list as published.
    @Test func decodesTheMarch2005ListAsSeventySevenEntries() throws {
        let list = try BanlistFixture.list(.tcg, "2005-03-01")

        #expect(list.effectiveDate == "2005-03-01")
        #expect(list.count == 77)
        #expect(list.konamiIDs(at: .forbidden).count == 18)
        #expect(list.konamiIDs(at: .limited).count == 44)
        #expect(list.konamiIDs(at: .semiLimited).count == 15)

        // Each identifier carries exactly one status.
        #expect(list.statuses.count == Set(list.statuses.keys).count)
    }

    /// Evidence for R1.AC3 and `C3`: the source encodes three values, a card
    /// absent from a list carries the fourth meaning by absence, and a body
    /// holding anything else is refused rather than quietly mapped.
    @Test func decodesTheThreePublishedStatusesAndNoFourth() throws {
        #expect(BanlistStatus.allCases.count == 3)
        #expect(BanlistStatus(rawValue: 0) == .forbidden)
        #expect(BanlistStatus(rawValue: 1) == .limited)
        #expect(BanlistStatus(rawValue: 2) == .semiLimited)
        #expect(BanlistStatus(rawValue: 3) == nil)

        // Across all 177 recorded lists, nothing but 0, 1 and 2 appears.
        var seen: Set<BanlistStatus> = []
        var entries = 0
        for format in BanlistFormat.allCases {
            for file in try BanlistFixture.datedFiles(format) {
                let list = try JSONDecoder().decode(
                    PublishedBanlist.self, from: try Data(contentsOf: file))
                seen.formUnion(list.statuses.values)
                entries += list.count
            }
        }
        #expect(seen == Set(BanlistStatus.allCases))
        #expect(entries == 28_648)

        // An unpublished value is a decoding failure, not a silent default.
        let rogue = Data(#"{"date":"2026-01-01","regulation":{"4007":3}}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PublishedBanlist.self, from: rogue)
        }

        // A card the list does not name has no status; absence is the answer.
        let list = try BanlistFixture.list(.tcg, "2005-03-01")
        #expect(list.status(forKonamiID: -1) == nil)
        #expect(BanlistStatus.forbidden.copiesAllowed == 0)
        #expect(BanlistStatus.semiLimited.banStatus == .semiLimited)
    }
}
