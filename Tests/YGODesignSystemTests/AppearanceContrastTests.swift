import Foundation
import Testing
import YGOCore
@testable import YGODesignSystem

@Suite("Appearance and contrast")
struct AppearanceContrastTests {
    /// Evidence for R2.AC3: a marker nobody can see is not a marker. Silver
    /// synchro disappears on a light surface and near-black Xyz on a dark one,
    /// which is why every frame colour is a pair rather than a value.
    @Test func everyMarkerHoldsThreeToOneAgainstItsOwnSurface() {
        for frame in CardFrame.allCases {
            let pair = Theme.Palette.frameComponents(frame)

            let light = ColourMetrics.contrastRatio(pair.light, Theme.Palette.lightSurface)
            let dark = ColourMetrics.contrastRatio(pair.dark, Theme.Palette.darkSurface)

            #expect(light >= 3, "\(frame.rawValue) light \(light):1")
            #expect(dark >= 3, "\(frame.rawValue) dark \(dark):1")
        }

        // The two that make the pairing necessary, checked the wrong way round
        // to show what a single value would have cost.
        let synchro = Theme.Palette.frameComponents(.synchro)
        let xyz = Theme.Palette.frameComponents(.xyz)
        #expect(ColourMetrics.contrastRatio(synchro.dark, Theme.Palette.lightSurface) < 3)
        #expect(ColourMetrics.contrastRatio(xyz.light, Theme.Palette.darkSurface) < 3)
    }

    /// Evidence for R2.AC3: text carries the meaning, so it holds the stricter
    /// ratio — on every surface it can be drawn on, in both appearances.
    @Test func everyTextPairHoldsFourAndAHalfToOneInBothAppearances() {
        for (textName, text) in Theme.Palette.textComponents {
            for (surfaceName, surface) in Theme.Palette.surfaceComponents {
                let light = ColourMetrics.contrastRatio(text.light, surface.light)
                let dark = ColourMetrics.contrastRatio(text.dark, surface.dark)

                #expect(light >= 4.5,
                        "\(textName) on \(surfaceName), light: \(light):1")
                #expect(dark >= 4.5,
                        "\(textName) on \(surfaceName), dark: \(dark):1")
            }
        }

        // Secondary text is quieter than primary but still readable, which is
        // the whole point of having two.
        let primary = Theme.Palette.textComponents["primary"]!
        let secondary = Theme.Palette.textComponents["secondary"]!
        let page = Theme.Palette.surfaceComponents["page"]!
        #expect(ColourMetrics.contrastRatio(primary.light, page.light)
                > ColourMetrics.contrastRatio(secondary.light, page.light))
    }

    /// Evidence for R2.AC4: a fixed value works in one appearance and fails in
    /// the other, silently. Every colour here has somewhere to go in both.
    @Test func everyColourResolvesInBothAppearances() {
        for frame in CardFrame.allCases {
            let pair = Theme.Palette.frameComponents(frame)
            #expect(pair.light != pair.dark, "\(frame.rawValue) is one value")
        }

        for (name, pair) in Theme.Palette.surfaceComponents {
            #expect(pair.light != pair.dark, "surface \(name) is one value")
            // A light surface is light and a dark one is dark, rather than the
            // same grey twice.
            #expect(ColourMetrics.luminance(pair.light) > ColourMetrics.luminance(pair.dark))
        }

        for (name, pair) in Theme.Palette.textComponents {
            #expect(pair.light != pair.dark, "text \(name) is one value")
            #expect(ColourMetrics.luminance(pair.light) < ColourMetrics.luminance(pair.dark))
        }

        // The dark value of a frame is the lighter of the two, because it is
        // drawn on the darker surface.
        for frame in CardFrame.allCases {
            let pair = Theme.Palette.frameComponents(frame)
            #expect(ColourMetrics.luminance(pair.dark) > ColourMetrics.luminance(pair.light),
                    "\(frame.rawValue)")
        }
    }
}
