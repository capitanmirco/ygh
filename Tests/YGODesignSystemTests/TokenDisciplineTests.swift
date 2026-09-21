import Foundation
import Testing
@testable import YGODesignSystem

@Suite("Token discipline")
struct TokenDisciplineTests {
    static let root: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Every Swift source a feature draws with.
    static func featureSources() throws -> [(name: String, text: String)] {
        let features = Self.root.appending(path: "Packages/Features")
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

    /// Evidence for R4.AC2: a single literal is invisible in review and
    /// permanent afterwards. This scans rather than trusting the convention.
    ///
    /// Zero is allowed: `spacing: 0` is not a magic number, it is the absence
    /// of one.
    @Test func noFeatureSourceContainsAColourOrSizeLiteral() throws {
        let sources = try Self.featureSources()
        #expect(sources.count >= 8)

        let forbidden: [(name: String, pattern: String)] = [
            ("a literal colour", #"Color\(red:"#),
            ("a literal font size", #"\.system\(size:"#),
            ("a literal corner radius", #"cornerRadius: [1-9]"#),
            ("a literal opacity", #"\.opacity\(0?\.[0-9]"#),
            ("a literal spacing", #"spacing: [1-9]"#),
            ("a literal padding", #"padding\([1-9]"#),
        ]

        for (name, text) in sources {
            for (what, pattern) in forbidden {
                let found = text.range(of: pattern, options: .regularExpression)
                #expect(found == nil, "\(name) contains \(what)")
            }
        }
    }

    /// Evidence for R4.AC2: one definition each. A token defined twice is two
    /// tokens that will disagree.
    @Test func everyTokenHasExactlyOneDefinition() throws {
        let designSystem = Self.root
            .appending(path: "Packages/YGODesignSystem/Sources/YGODesignSystem")
        var definitions: [String: Int] = [:]

        for file in try FileManager.default.contentsOfDirectory(
            at: designSystem, includingPropertiesForKeys: nil)
            where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n") {
                guard let match = line.range(
                    of: #"static (let|var) [a-zA-Z]+"#, options: .regularExpression)
                else { continue }
                let name = line[match].split(separator: " ").last!
                definitions[String(name), default: 0] += 1
            }
        }

        #expect(!definitions.isEmpty)
        let duplicated = definitions.filter { $0.value > 1 }
        #expect(duplicated.isEmpty, "defined more than once: \(duplicated.keys.sorted())")

        // The vocabulary is a real one rather than three names.
        #expect(definitions.count >= 25)
    }

    /// Evidence for R4.AC3: a token change lands everywhere because the
    /// screens hold names, not values. Checked by counting how many places
    /// read each name rather than by editing one and rebuilding.
    @Test func changingATokenReachesEveryScreenWithNoOtherEdit() throws {
        let sources = try Self.featureSources()
        let text = sources.map(\.text).joined()

        // Every screen reads the vocabulary rather than restating it.
        for token in ["Theme.Spacing", "Theme.Palette", "Theme.Typography"] {
            let count = text.components(separatedBy: token).count - 1
            #expect(count >= 5, "\(token) is read in only \(count) places")
        }

        // And the values live in exactly one module.
        let designSystem = Self.root
            .appending(path: "Packages/YGODesignSystem/Sources/YGODesignSystem")
        let palette = try String(
            contentsOf: designSystem.appending(path: "FramePalette.swift"), encoding: .utf8)
        #expect(palette.contains("RGB(hex:"))
        #expect(!text.contains("RGB(hex:"), "a feature writes a colour value directly")
    }
}
