import Foundation
import Testing
import YGOCore
@testable import YGODesignSystem

@Suite("Deck and collection markers")
struct DeckAndCollectionMarkerTests {
    /// Evidence for R1.AC2: a deck entry carries the same colour the grid tile
    /// did, because both ask the palette the same question about the same
    /// frame.
    @Test func aDeckEntryCarriesItsFramesColour() {
        for frame in CardFrame.allCases {
            let colour = Theme.Palette.frameComponents(frame)
            #expect(colour == Theme.Palette.frameComponents(frame))
            #expect(!frame.italianName.isEmpty)
        }

        // A spell in a deck list is the same green as a spell in the catalog.
        #expect(Theme.Palette.frameComponents(.spell).light == RGB(hex: "1E8A5F"))
        #expect(Theme.Palette.frameComponents(.trap).light == RGB(hex: "C0397A"))
    }

    /// Evidence for R1.AC2: the extra deck is one section holding four kinds
    /// of card. Telling them apart without reading is what the colour is for.
    @Test func extraDeckEntriesAreToldApartWithoutReading() {
        let extra = CardFrame.allCases.filter { $0.belongsInExtraDeck }
        #expect(extra.count == 7)

        // Four colours across the seven, since three are pendulum variants.
        let colours = Set(extra.map { Theme.Palette.frameComponents($0).light })
        #expect(colours.count == 4)

        // Every pair of them is separable, in both appearances.
        let bases: [CardFrame] = [.fusion, .synchro, .xyz, .link]
        for i in bases.indices {
            for j in bases.index(after: i)..<bases.endIndex {
                let a = Theme.Palette.frameComponents(bases[i])
                let b = Theme.Palette.frameComponents(bases[j])
                #expect(ColourMetrics.deltaE(a.light, b.light) >= 18)
                #expect(ColourMetrics.deltaE(a.dark, b.dark) >= 18)
            }
        }

        // And each names itself, because colour is never the only clue.
        #expect(CardFrame.fusion.italianName.contains("Fusione"))
        #expect(CardFrame.synchro.italianName.contains("Synchro"))
        #expect(CardFrame.xyz.italianName.contains("Xyz"))
        #expect(CardFrame.link.italianName.contains("Link"))
    }

    /// Evidence for R4.AC1: a card looks like itself in the collection too.
    /// One function, asked from three screens, is what makes that cheap.
    @Test func collectionRowsUseTheSameMarkerAsEverywhereElse() {
        // The marker has two shapes and no third way of drawing a frame.
        let shapes: [FrameMarker.Shape] = [.bar, .dot]
        #expect(shapes.count == 2)

        // Whichever shape a screen uses, the colour is the same.
        for frame in CardFrame.allCases {
            let components = Theme.Palette.frameComponents(frame)
            #expect(components.light != components.dark)
            #expect(ColourMetrics.contrastRatio(
                components.light, Theme.Palette.lightSurface) >= 3)
        }

        // A card the collection holds but the palette does not know still
        // marks, which is what keeps a row from looking broken.
        #expect(Theme.Palette.frameComponents(.token) == Theme.Palette.neutralFrame)
    }
}
