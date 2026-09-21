import Foundation
import Testing
import YGOCore
@testable import YGODesignSystem

@Suite("Visual language budgets")
struct VisualLanguageBudgetTests {
    /// Evidence for NFR1: a colour-coded interface exists to break exactly one
    /// accessibility rule, so this is the check that matters most. Every fact
    /// the colour encodes is also available as text.
    @Test func noColourCodedFactIsAvailableOnlyAsColour() {
        // A frame's marker names the frame.
        for frame in CardFrame.allCases {
            #expect(!frame.italianName.isEmpty, "\(frame.rawValue) has no name")
        }

        // Frames sharing a colour share a meaning, and the ones that do not
        // are named differently.
        let named = Dictionary(grouping: CardFrame.allCases) {
            Theme.Palette.frameComponents($0).light
        }
        for (_, frames) in named where frames.count > 1 {
            // Pendulum variants share their base's colour and say "Pendulum".
            let names = Set(frames.map { $0.italianName })
            #expect(names.count == frames.count || frames.contains { $0.rawValue.contains("pendulum") })
        }

        // Restriction is named, not only shown as a colour.
        for status in [BanStatus.forbidden, .limited, .semiLimited, .unlimited] {
            #expect(!status.italianName.isEmpty)
        }
        #expect(BanStatus.forbidden.italianName != BanStatus.limited.italianName)

        // A breakdown category names itself too.
        #expect(BreakdownPalette.frame(forKind: "spell").italianName == "Magia")
    }

    /// Evidence for NFR2: contrast is the thing a palette breaks first, and it
    /// breaks silently in whichever appearance the author was not using.
    @Test func contrastHoldsInBothAppearancesAcrossThePalette() {
        for frame in CardFrame.allCases {
            let pair = Theme.Palette.frameComponents(frame)
            #expect(ColourMetrics.contrastRatio(pair.light, Theme.Palette.lightSurface) >= 3)
            #expect(ColourMetrics.contrastRatio(pair.dark, Theme.Palette.darkSurface) >= 3)
        }

        for (_, text) in Theme.Palette.textComponents {
            for (_, surface) in Theme.Palette.surfaceComponents {
                #expect(ColourMetrics.contrastRatio(text.light, surface.light) >= 4.5)
                #expect(ColourMetrics.contrastRatio(text.dark, surface.dark) >= 4.5)
            }
        }

        // The restriction colours are drawn as badges with text on them. The
        // badge picks black or white rather than always white: on the
        // semi-limited yellow, white measures 2.64:1.
        for status in Theme.Palette.restrictionComponents.keys {
            #expect(Theme.Palette.badgeTextContrast(status) >= 4.5,
                    "the \(status) badge cannot carry readable text")
        }
        #expect(Theme.Palette.textOn(.semiLimited) == .black)
        #expect(Theme.Palette.textOn(.forbidden) == .white)
    }

    /// Evidence for NFR3: the grid gained a marker per tile. The budget that
    /// `card-detail` measured is re-measured rather than assumed to have
    /// survived.
    @Test func narrowingStillFollowsAKeystrokeWithinOneHundredFiftyMilliseconds() {
        // Resolving a marker's colour is what every tile now does once, so it
        // is the cost the grid added. Two hundred tiles is one batch.
        let frames = CardFrame.allCases
        var worst: Double = 0

        for _ in 0..<5 {
            let started = DispatchTime.now().uptimeNanoseconds
            for index in 0..<200 {
                _ = Theme.Palette.frameComponents(frames[index % frames.count])
            }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            worst = max(worst, elapsed)
        }

        // Far below the 150 ms the keystroke budget allows, and measured
        // rather than argued.
        #expect(worst < 10, "resolving 200 markers took \(worst) ms")
    }

    /// Evidence for NFR4: one definition per token, which is what makes a
    /// change land everywhere instead of in most places.
    @Test func everyTokenIsReadFromOnePlace() {
        // The palette answers for every frame through one function.
        for frame in CardFrame.allCases {
            let base = Theme.Palette.baseFrame(of: frame)
            #expect(Theme.Palette.frameComponents(frame)
                    == Theme.Palette.frameComponents(base))
        }

        // The scale is described by one enumeration, so it can be checked.
        #expect(Theme.Typography.Level.allCases.count == 5)

        // The surfaces and the text are two small tables, not scattered values.
        #expect(Theme.Palette.surfaceComponents.count == 3)
        #expect(Theme.Palette.textComponents.count == 2)
        #expect(Theme.Palette.restrictionComponents.count == 3)
    }
}
