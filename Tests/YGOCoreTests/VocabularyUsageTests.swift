import Foundation
import Testing
@testable import YGOCore

@Suite("Vocabulary usage")
struct VocabularyUsageTests {
    static let root: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func featureSources() throws -> [(name: String, text: String)] {
        let features = root.appending(path: "Packages/Features")
        let manager = FileManager.default
        var result: [(String, String)] = []
        for module in try manager.contentsOfDirectory(
            at: features, includingPropertiesForKeys: nil) {
            let sources = module.appending(path: "Sources")
                .appending(path: module.lastPathComponent)
            guard manager.fileExists(atPath: sources.path) else { continue }
            for file in try manager.contentsOfDirectory(
                at: sources, includingPropertiesForKeys: nil)
                where file.pathExtension == "swift" {
                result.append((file.lastPathComponent,
                               try String(contentsOf: file, encoding: .utf8)))
            }
        }
        return result
    }

    /// Evidence for R2.AC1: the same term has to read the same in the grid,
    /// the detail panel, a deck row and a collection row. One function asked
    /// from four places makes that true by construction rather than by
    /// remembering.
    @Test func theSameCardReadsTheSameOnEveryScreen() throws {
        let sources = try Self.featureSources()

        // Every place that shows a card's kind goes through the vocabulary.
        let showsKind = sources.filter { $0.text.contains("humanReadableType") }
        #expect(showsKind.count >= 4, "expected four screens, found \(showsKind.count)")

        for (name, text) in showsKind {
            // No screen prints the upstream term directly.
            let raw = text.range(
                of: #"(Text|subtitle:)\s*\(?\s*(card|detail\.card)\.humanReadableType"#,
                options: .regularExpression)
            #expect(raw == nil, "\(name) prints the upstream term raw")
            #expect(text.contains("Vocabulary.cardKind"), "\(name) does not translate")
        }

        // And they all get the same answer for the same input.
        let kind = "Xyz Effect Monster"
        let answers = Set((0..<4).map { _ in Vocabulary.cardKind(kind) })
        #expect(answers.count == 1)
        #expect(answers.first == "Mostro Xyz Effetto")
    }

    /// Evidence for R2.AC2: a translation defined twice is two translations
    /// that will disagree. The scan is what keeps this from unravelling.
    @Test func noFeatureSourceTranslatesAnUpstreamTermItself() throws {
        let sources = try Self.featureSources()

        // The Italian words for the terms this table owns must appear only in
        // the table, never in a feature that decided to do it itself.
        let owned = ["Mostro Effetto", "Magia Rapida", "Trappola Continua",
                     "Incantatore", "Bestia Alata", "OSCURITÀ", "Mostro Normale"]

        for (name, text) in sources {
            // Comments are where the reasons live, and a comment explaining
            // why the filter must find "Incantatore" is not a second
            // definition of it. Only code counts.
            let code = text.split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")

            for term in owned {
                #expect(!code.contains("\"\(term)\""),
                        "\(name) defines \(term) itself")
            }
        }

        // The table holds them, which is what the scan is checking against.
        #expect(Vocabulary.cardKinds.values.contains("Mostro Effetto"))
        #expect(Vocabulary.monsterTypes.values.contains("Incantatore"))
        #expect(Vocabulary.attributes.values.contains("OSCURITÀ"))
    }
}
