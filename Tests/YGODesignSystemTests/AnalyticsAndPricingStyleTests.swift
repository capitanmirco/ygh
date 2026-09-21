import Foundation
import Testing
import YGOCore
@testable import YGODesignSystem

@Suite("Analytics and pricing style")
struct AnalyticsAndPricingStyleTests {
    /// The five screens, and the sources that draw them.
    static let screens: [String: [String]] = [
        "Catalogo": ["Packages/Features/YGOFeatureBrowser/Sources/YGOFeatureBrowser",
                     "Packages/Features/YGOFeatureCardDetail/Sources/YGOFeatureCardDetail"],
        "Mazzi": ["Packages/Features/YGOFeatureDeckBuilder/Sources/YGOFeatureDeckBuilder"],
        "Collezione": ["Packages/Features/YGOFeatureCollection/Sources/YGOFeatureCollection"],
        "Statistiche": ["Packages/Features/YGOFeatureAnalytics/Sources/YGOFeatureAnalytics"],
        "Valore": ["Packages/Features/YGOFeaturePricing/Sources/YGOFeaturePricing"],
    ]

    static let root: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func sources(of screen: String) throws -> [String] {
        try (screens[screen] ?? []).flatMap { path -> [String] in
            let directory = root.appending(path: path)
            return try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
                .map { try String(contentsOf: $0, encoding: .utf8) }
        }
    }

    /// Evidence for R4.AC1: statistics and valuation are mostly numbers, and
    /// numbers in the old body text beside a restyled catalog would read as a
    /// different application.
    @Test func everyFigureUsesTheFigureStyle() throws {
        for screen in ["Statistiche", "Valore"] {
            let sources = try Self.sources(of: screen)
            #expect(!sources.isEmpty)

            let joined = sources.joined()
            #expect(joined.contains("Typography.figure")
                    || joined.contains("Typography.heroFigure"),
                    "\(screen) draws no figure with the figure style")

            // And none of them hand-rolls a monospaced body instead.
            #expect(!joined.contains("Typography.body.monospacedDigit()"),
                    "\(screen) still styles a figure by hand")
        }
    }

    /// Evidence for R4.AC1: a breakdown by card type borrows the colour of the
    /// frame each category is mostly made of, so the chart reads like the
    /// cards it counts.
    @Test func aBreakdownByCardTypeUsesTheFrameColours() throws {
        #expect(BreakdownPalette.frame(forKind: "monster") == .effect)
        #expect(BreakdownPalette.frame(forKind: "spell") == .spell)
        #expect(BreakdownPalette.frame(forKind: "trap") == .trap)
        // Anything else is the neutral, which claims nothing.
        #expect(BreakdownPalette.frame(forKind: "other") == .token)
        #expect(BreakdownPalette.frame(forKind: "nonsense") == .token)

        // The three named categories are told apart from one another.
        let kinds = ["monster", "spell", "trap"]
        for i in kinds.indices {
            for j in kinds.index(after: i)..<kinds.endIndex {
                let a = Theme.Palette.frameComponents(BreakdownPalette.frame(forKind: kinds[i]))
                let b = Theme.Palette.frameComponents(BreakdownPalette.frame(forKind: kinds[j]))
                #expect(ColourMetrics.deltaE(a.light, b.light) >= 18)
            }
        }

        let analytics = try Self.sources(of: "Statistiche").joined()
        #expect(analytics.contains("BreakdownPalette"))
    }

    /// Evidence for R4.AC1: all five, not the two the user looks at most.
    /// Half a restyle is how an application ends up looking like two.
    @Test func allFiveScreensReadTheNewTokens() throws {
        #expect(Self.screens.count == 5)

        for screen in Self.screens.keys {
            let joined = try Self.sources(of: screen).joined()
            #expect(!joined.isEmpty, "\(screen) has no sources")
            #expect(joined.contains("Theme."), "\(screen) reads no tokens")
        }

        // The three screens that show cards carry the frame marker; the other
        // two show numbers and carry the figure style.
        for screen in ["Catalogo", "Mazzi", "Collezione"] {
            let joined = try Self.sources(of: screen).joined()
            #expect(joined.contains("FrameMarker"), "\(screen) marks no frames")
        }
    }
}
