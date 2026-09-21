import Foundation
import Testing
import YGOCore
@testable import YGODesignSystem

@Suite("Frame palette")
struct FramePaletteTests {
    /// The frames that can share a deck section, and therefore have to be told
    /// apart from one another. Tokens are not deck cards — the rules do not
    /// allow one in a deck and the user's own decks hold none — so a token
    /// never sits beside an effect monster in a list.
    static let mainDeckFrames: [CardFrame] = [.normal, .effect, .ritual, .spell, .trap]
    static let extraDeckFrames: [CardFrame] = [.fusion, .synchro, .xyz, .link]

    private func components(_ frame: CardFrame) -> (light: RGB, dark: RGB) {
        Theme.Palette.frameComponents(frame)
    }

    /// Evidence for R1.AC1: all seventeen frames resolve, and the five
    /// pendulum variants come from their base rather than from nowhere.
    @Test func everyFrameIncludingPendulumVariantsResolves() {
        #expect(CardFrame.allCases.count == 17)

        for frame in CardFrame.allCases {
            let pair = components(frame)
            #expect(pair.light != pair.dark,
                    "\(frame.rawValue) needs a value per appearance")
        }

        // Pendulum variants take their base frame's colour.
        let pendulums: [(CardFrame, CardFrame)] = [
            (.normalPendulum, .normal), (.effectPendulum, .effect),
            (.ritualPendulum, .ritual), (.fusionPendulum, .fusion),
            (.synchroPendulum, .synchro), (.xyzPendulum, .xyz),
        ]
        for (variant, base) in pendulums {
            #expect(Theme.Palette.baseFrame(of: variant) == base)
            #expect(components(variant) == components(base))
            #expect(Theme.Palette.isPendulum(variant))
        }
        #expect(!Theme.Palette.isPendulum(.effect))

        // Eleven colours cover seventeen frames: the five pendulum variants
        // take their base's, and the token takes the neutral.
        let distinct = Set(CardFrame.allCases.map { components($0).light })
        #expect(distinct.count == 11)
    }

    /// Evidence for R1.AC1: a colour that cannot be told from the one beside
    /// it is decoration. ΔE 18 is the floor, measured in both appearances.
    @Test func noTwoBaseFramesAreCloserThanEighteenDeltaE() {
        for group in [Self.mainDeckFrames, Self.extraDeckFrames] {
            for (a, b) in group.pairs() {
                let light = ColourMetrics.deltaE(components(a).light, components(b).light)
                let dark = ColourMetrics.deltaE(components(a).dark, components(b).dark)
                #expect(light >= 18, "\(a.rawValue) vs \(b.rawValue) light ΔE \(light)")
                #expect(dark >= 18, "\(a.rawValue) vs \(b.rawValue) dark ΔE \(dark)")
            }
        }
    }

    /// Evidence for R1.AC3: a deck builder sorts extra-deck cards into one
    /// section and has to tell four frames apart inside it.
    @Test func theSevenExtraDeckFramesAreSeparableByColourAlone() {
        let extra = CardFrame.allCases.filter { $0.belongsInExtraDeck }
        // Seven, not eight: link has no pendulum variant, because the game has
        // no Link Pendulum monster.
        #expect(extra.count == 7)
        #expect(!CardFrame.allCases.contains { $0.rawValue == "link_pendulum" })

        // Seven frames, four colours: the three pendulum variants among them
        // take their base's colour, which is what the game does too.
        let colours = Set(extra.map { components($0).light })
        #expect(colours.count == 4)

        // And none of them is a main-deck frame's colour.
        let mainColours = Set(Self.mainDeckFrames.map { components($0).light })
        #expect(colours.isDisjoint(with: mainColours))
        for extraColour in colours {
            for mainColour in mainColours {
                #expect(ColourMetrics.deltaE(extraColour, mainColour) >= 18)
            }
        }
    }

    /// Evidence for R1.AC4, and the reason this task comes first: the game's
    /// own effect-monster orange is this application's "limited", and its
    /// normal-monster yellow is "semi-limited". Only measuring catches that.
    @Test func noFrameComesWithinTwentyFiveDeltaEOfARestrictionColour() {
        let restriction = Theme.Palette.restrictionComponents
        #expect(restriction.count == 3)

        for frame in CardFrame.allCases {
            let pair = components(frame)
            for (status, colour) in restriction {
                let light = ColourMetrics.deltaE(pair.light, colour)
                let dark = ColourMetrics.deltaE(pair.dark, colour)
                #expect(light >= 25,
                        "\(frame.rawValue) light is ΔE \(light) from \(status)")
                #expect(dark >= 25,
                        "\(frame.rawValue) dark is ΔE \(dark) from \(status)")
            }
        }
    }

    /// Evidence for R1.AC4: red, orange and yellow keep meaning restriction.
    /// Moving them would have been the easy way out of the constraint above.
    @Test func theRestrictionColoursKeepTheirMeaningAndTheirValues() {
        let restriction = Theme.Palette.restrictionComponents
        #expect(restriction[.forbidden] == RGB(hex: "C7292A"))
        #expect(restriction[.limited] == RGB(hex: "D9781A"))
        #expect(restriction[.semiLimited] == RGB(hex: "B89E1A"))
        #expect(restriction[.unlimited] == nil)

        // They are ordered by severity and separable from each other.
        for (a, b) in [BanStatus.forbidden, .limited, .semiLimited].pairs() {
            let distance = ColourMetrics.deltaE(restriction[a]!, restriction[b]!)
            #expect(distance >= 18, "\(a) vs \(b) ΔE \(distance)")
        }
    }

    /// Evidence for R1.AC5: the catalog's frames come from upstream and can
    /// grow. A card whose frame the palette does not know still has to render
    /// as something, in a colour that claims nothing.
    @Test func anUnknownFrameFallsBackToTheNeutralRatherThanVanishing() {
        // Token is the frame that already shares the neutral, by design.
        #expect(components(.token).light == Theme.Palette.neutralFrame.light)
        #expect(components(.token).dark == Theme.Palette.neutralFrame.dark)

        // The neutral is genuinely neutral: near-equal components.
        let neutral = Theme.Palette.neutralFrame.light
        #expect(abs(neutral.red - neutral.blue) < 30)

        // It is still visible, which is the difference between neutral and
        // absent.
        #expect(ColourMetrics.contrastRatio(
            Theme.Palette.neutralFrame.light, Theme.Palette.lightSurface) >= 3)
        #expect(ColourMetrics.contrastRatio(
            Theme.Palette.neutralFrame.dark, Theme.Palette.darkSurface) >= 3)

        // And it is not mistakable for a restriction colour either.
        for colour in Theme.Palette.restrictionComponents.values {
            #expect(ColourMetrics.deltaE(Theme.Palette.neutralFrame.light, colour) >= 25)
        }
    }
}

extension Array {
    /// Every unordered pair, which is what a distinctness check walks.
    func pairs() -> [(Element, Element)] {
        var result: [(Element, Element)] = []
        for i in indices {
            for j in index(after: i)..<endIndex { result.append((self[i], self[j])) }
        }
        return result
    }
}
