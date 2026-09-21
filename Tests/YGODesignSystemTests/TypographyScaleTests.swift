import Foundation
import Testing
@testable import YGODesignSystem

@Suite("Typography scale")
struct TypographyScaleTests {
    /// Evidence for R3.AC1: the interface had five sizes between 11 and 13
    /// points, which is a wall rather than a scale. These five are ordered.
    @Test func theFiveLevelsAreStrictlyOrderedInProminence() {
        let levels = Theme.Typography.Level.allCases
        #expect(levels.count == 5)

        let sizes = levels.map(\.size)
        #expect(sizes == sizes.sorted(by: >), "levels are not ordered: \(sizes)")
        #expect(Set(sizes).count == 5, "two levels share a size")

        // A real top and a real bottom, not five variations on 12.
        #expect(Theme.Typography.Level.screenTitle.size == 22)
        #expect(Theme.Typography.Level.caption.size == 11)
        #expect(sizes.first! - sizes.last! >= 10)

        // Every adjacent step is visible rather than nominal.
        for (bigger, smaller) in zip(sizes, sizes.dropFirst()) {
            #expect(bigger - smaller >= 2, "\(bigger) to \(smaller) is not a step")
        }
    }

    /// Evidence for R3.AC2: a figure that changes width as it changes value
    /// moves everything beside it. This is the one type style where that
    /// matters, and the only one that asks for it.
    @Test func figuresUseMonospacedDigitsSoNothingShifts() {
        #expect(Theme.Typography.Level.figure.isMonospacedDigit)

        for level in Theme.Typography.Level.allCases where level != .figure {
            #expect(!level.isMonospacedDigit, "\(level.rawValue) should not be monospaced")
        }

        // The figure sits above body text: a total is read before the words
        // around it.
        #expect(Theme.Typography.Level.figure.size > Theme.Typography.Level.body.size)
    }

    /// Evidence for R3.AC3: a raised surface has to be distinguishable from
    /// the page without a border being drawn around it, in both appearances.
    @Test func theThreeElevationLevelsDifferInBothAppearances() {
        let surfaces = Theme.Palette.surfaceComponents
        #expect(surfaces.count == 3)

        let page = surfaces["page"]!
        let raised = surfaces["raised"]!
        let overlay = surfaces["overlay"]!

        // Each step is lighter than the last in dark appearance, and the other
        // way in light: elevation reads as "closer to the viewer" either way.
        #expect(ColourMetrics.luminance(raised.dark) > ColourMetrics.luminance(page.dark))
        #expect(ColourMetrics.luminance(overlay.dark) > ColourMetrics.luminance(raised.dark))
        #expect(ColourMetrics.luminance(raised.light) > ColourMetrics.luminance(page.light))

        // And the difference is visible rather than nominal.
        for (a, b) in [(page, raised), (raised, overlay)] {
            #expect(ColourMetrics.deltaE(a.dark, b.dark) >= 3)
        }
        #expect(ColourMetrics.deltaE(page.light, raised.light) >= 2)
    }
}
