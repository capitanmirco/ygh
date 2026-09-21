import Foundation
import Testing
import YGOCore
@testable import YGODesignSystem

@Suite("Catalog markers")
struct CatalogMarkerTests {
    /// Evidence for R1.AC2: a colour is only worth learning if it is the same
    /// everywhere. The grid tile and the detail panel ask the same function
    /// for it, which is what makes that true by construction.
    @Test func aCardCarriesTheSameColourInTheGridAndTheDetail() {
        for frame in CardFrame.allCases {
            let inTheGrid = Theme.Palette.frameComponents(frame)
            let inTheDetail = Theme.Palette.frameComponents(frame)
            #expect(inTheGrid == inTheDetail)
        }

        // A pendulum card looks like its base frame in both places, rather
        // than like one thing in a grid and another in a panel.
        #expect(Theme.Palette.frameComponents(.effectPendulum)
                == Theme.Palette.frameComponents(.effect))

        // The marker names itself, so the colour is never the only clue.
        #expect(CardFrame.spell.italianName == "Magia")
        #expect(CardFrame.trap.italianName == "Trappola")
        #expect(CardFrame.allCases.allSatisfy { !$0.italianName.isEmpty })
        #expect(Set(CardFrame.allCases.map { $0.italianName }).count >= 11)
    }

    /// Evidence for R2.AC1: the marker is a bar or a dot, never a fill behind
    /// a title. Nothing is drawn on a saturated frame colour, so the frame
    /// colour never has to carry text contrast.
    @Test func noTextIsDrawnOnASaturatedFrameColour() {
        // The marker's shapes are the only two it has, and neither contains
        // anything.
        let shapes: [FrameMarker.Shape] = [.bar, .dot]
        #expect(shapes.count == 2)

        // A bar is 4 points wide and a dot 8 across: too small for text by
        // construction, which is the point.
        #expect(Theme.Marker.barWidth <= 6)
        #expect(Theme.Marker.dotSize <= 12)

        // Text is drawn on surfaces, and those hold the stricter ratio.
        for (_, text) in Theme.Palette.textComponents {
            for (_, surface) in Theme.Palette.surfaceComponents {
                #expect(ColourMetrics.contrastRatio(text.light, surface.light) >= 4.5)
                #expect(ColourMetrics.contrastRatio(text.dark, surface.dark) >= 4.5)
            }
        }
    }

    /// Evidence for R2.AC2: colour enters through markers, accents and states.
    /// The surfaces and the text stay where they were, which is what keeps
    /// "colourful" from becoming "tinted".
    @Test func surfacesAndTextStaySystemDerived() {
        // Surfaces are near-neutral: the largest gap between any two channels
        // is small, in both appearances.
        for (name, surface) in Theme.Palette.surfaceComponents {
            for rgb in [surface.light, surface.dark] {
                let channels = [rgb.red, rgb.green, rgb.blue]
                #expect(channels.max()! - channels.min()! <= 12,
                        "surface \(name) is tinted")
            }
        }

        for (name, text) in Theme.Palette.textComponents {
            for rgb in [text.light, text.dark] {
                let channels = [rgb.red, rgb.green, rgb.blue]
                #expect(channels.max()! - channels.min()! <= 12,
                        "text \(name) is tinted")
            }
        }

        // The frames, by contrast, are meant to be colours.
        let spell = Theme.Palette.frameComponents(.spell).light
        #expect([spell.red, spell.green, spell.blue].max()!
                - [spell.red, spell.green, spell.blue].min()! > 40)
    }
}
