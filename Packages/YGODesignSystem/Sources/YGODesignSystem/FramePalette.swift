import SwiftUI
import YGOCore

/// A colour as three components, so a test can measure it without a display.
///
/// `Color` and `NSColor` cannot be taken apart reliably in a headless test, and
/// the whole point of this palette is that its separations are measured rather
/// than trusted.
public struct RGB: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// From a six-digit hexadecimal string, which is how the palette is
    /// written down and how it was measured.
    public init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(Double((value >> 16) & 0xFF),
                  Double((value >> 8) & 0xFF),
                  Double(value & 0xFF))
    }

    public var color: Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255)
    }
}

/// Distance and contrast, so the palette's rules are arithmetic.
public enum ColourMetrics {
    /// CIE76 in Lab. Crude, and sufficient at the distances this palette uses.
    public static func deltaE(_ a: RGB, _ b: RGB) -> Double {
        let la = lab(a), lb = lab(b)
        return ((la.0 - lb.0) * (la.0 - lb.0)
                + (la.1 - lb.1) * (la.1 - lb.1)
                + (la.2 - lb.2) * (la.2 - lb.2)).squareRoot()
    }

    /// WCAG relative contrast, 1:1 to 21:1.
    public static func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func linear(_ channel: Double) -> Double {
        let c = channel / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func luminance(_ rgb: RGB) -> Double {
        0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
    }

    private static func lab(_ rgb: RGB) -> (Double, Double, Double) {
        let r = linear(rgb.red), g = linear(rgb.green), b = linear(rgb.blue)
        let x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
        let y = r * 0.2126 + g * 0.7152 + b * 0.0722
        let z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883
        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0 / 3.0) : 7.787 * t + 16.0 / 116.0
        }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }
}

extension Theme.Palette {
    /// The two surfaces the markers are measured against.
    public static let lightSurface = RGB(hex: "F6F6F7")
    public static let darkSurface = RGB(hex: "1C1C1E")

    /// What the restriction colours actually are, so a test can check that no
    /// frame colour drifts into them. The game's own effect-monster orange and
    /// normal-monster yellow are exactly these two, which is why those frames
    /// do not use them here.
    public static let restrictionComponents: [BanStatus: RGB] = [
        .forbidden: RGB(hex: "C7292A"),
        .limited: RGB(hex: "D9781A"),
        .semiLimited: RGB(hex: "B89E1A"),
    ]

    /// Where a frame the palette does not know ends up, and where tokens sit.
    ///
    /// A token is not a deck card — the user's own decks hold none, and the
    /// rules do not allow any — so it never has to be told apart from an
    /// effect monster in a list. It shares the neutral by design.
    public static let neutralFrame = (light: RGB(hex: "8C8378"), dark: RGB(hex: "BDB3A6"))

    /// The measured palette. Light value first, dark value second.
    ///
    /// Every pair holds at least 3:1 against its own appearance's surface, at
    /// least ΔE 25 from every restriction colour, and at least ΔE 18 from any
    /// other frame that can share a deck section with it.
    static let frameComponentTable: [CardFrame: (light: RGB, dark: RGB)] = [
        .normal: (RGB(hex: "A98A4E"), RGB(hex: "D9BE7E")),
        .effect: (RGB(hex: "6E6258"), RGB(hex: "A79A8C")),
        .ritual: (RGB(hex: "3D6FB8"), RGB(hex: "6E9BDC")),
        .fusion: (RGB(hex: "9B3FB5"), RGB(hex: "C47AD8")),
        .synchro: (RGB(hex: "7C8795"), RGB(hex: "AEBACA")),
        .xyz: (RGB(hex: "33384A"), RGB(hex: "8E8AA8")),
        .link: (RGB(hex: "0E7F7F"), RGB(hex: "3FB5B5")),
        .spell: (RGB(hex: "1E8A5F"), RGB(hex: "46B98A")),
        .trap: (RGB(hex: "C0397A"), RGB(hex: "E06BA4")),
        .skill: (RGB(hex: "5E6B2E"), RGB(hex: "90A054")),
        .token: neutralFrame,
    ]

    /// The frame a pendulum variant is drawn from.
    ///
    /// The game draws a pendulum card as its base frame with a second tone
    /// across the bottom, so eleven colours and one rule cover seventeen
    /// frames — and the four variants holding fewer than forty cards each cost
    /// nothing.
    public static func baseFrame(of frame: CardFrame) -> CardFrame {
        switch frame {
        case .normalPendulum: .normal
        case .effectPendulum: .effect
        case .ritualPendulum: .ritual
        case .fusionPendulum: .fusion
        case .synchroPendulum: .synchro
        case .xyzPendulum: .xyz
        default: frame
        }
    }

    public static func frameComponents(_ frame: CardFrame) -> (light: RGB, dark: RGB) {
        frameComponentTable[baseFrame(of: frame)] ?? neutralFrame
    }

    /// The marker colour for a card's frame, resolving per appearance.
    public static func frame(_ frame: CardFrame) -> Color {
        let components = frameComponents(frame)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let rgb = dark ? components.dark : components.light
            return NSColor(srgbRed: rgb.red / 255, green: rgb.green / 255,
                           blue: rgb.blue / 255, alpha: 1)
        })
    }

    /// True when the frame is drawn as a pendulum variant of its base.
    public static func isPendulum(_ frame: CardFrame) -> Bool {
        baseFrame(of: frame) != frame
    }
}

extension Theme.Palette {
    /// Builds a colour that resolves differently per appearance.
    static func dynamic(_ pair: (light: RGB, dark: RGB)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let rgb = dark ? pair.dark : pair.light
            return NSColor(srgbRed: rgb.red / 255, green: rgb.green / 255,
                           blue: rgb.blue / 255, alpha: 1)
        })
    }

    /// The text colours, as values rather than as system aliases.
    ///
    /// They started as `NSColor.labelColor` and `.secondaryLabelColor`. The
    /// second of those measures 3.95:1 against the overlay surface in dark
    /// appearance, which is under what `R2.AC3` requires — so these are the
    /// resolved values with that one lifted, and the views read them. Keeping
    /// the alias and measuring a different number would have made the proof a
    /// statement about nothing.
    public static let textComponents: [String: (light: RGB, dark: RGB)] = [
        "primary": (RGB(hex: "3C3C3C"), RGB(hex: "DDDDDD")),
        // Lifted from the system default: at 98989D, secondary text on
        // the overlay surface measures 3.95:1 in dark appearance, which
        // is under the 4.5:1 R2.AC3 requires.
        "secondary": (RGB(hex: "6E6E73"), RGB(hex: "ACACB2")),
    ]

    /// What the views read. Defined from the measured components above, so
    /// the thing proven and the thing drawn are the same thing.
    public static let text = dynamic(textComponents["primary"]!)
    public static let secondary = dynamic(textComponents["secondary"]!)

    public static let surfaceComponents: [String: (light: RGB, dark: RGB)] = [
        "page": (RGB(hex: "F6F6F7"), RGB(hex: "1C1C1E")),
        "raised": (RGB(hex: "FFFFFF"), RGB(hex: "2C2C2E")),
        "overlay": (RGB(hex: "FFFFFF"), RGB(hex: "3A3A3C")),
    ]
}

extension Theme {
    /// How far a surface sits from the page behind it.
    ///
    /// Three levels rather than a shadow: a shadow that has to be seen in both
    /// appearances ends up being two shadows.
    public enum Elevation {
        public static let page = Color(nsColor: .windowBackgroundColor)
        public static let raised = Color(nsColor: .controlBackgroundColor)
        public static let overlay = Color(nsColor: .underPageBackgroundColor)
    }
}

extension Theme.Palette {
    /// Black or white, whichever the background can carry.
    ///
    /// The semi-limited badge is a case in point: white on its yellow measures
    /// 2.64:1, which is unreadable, while black on it measures 7.9:1. Choosing
    /// by luminance is what lets the three restriction colours keep the values
    /// the game's own materials use.
    public static func textOn(_ background: RGB) -> Color {
        ColourMetrics.contrastRatio(background, RGB(255, 255, 255))
            >= ColourMetrics.contrastRatio(background, RGB(0, 0, 0))
            ? .white : .black
    }

    public static func textOn(_ status: BanStatus) -> Color {
        guard let background = restrictionComponents[status] else { return .white }
        return textOn(background)
    }

    /// The contrast a badge's own text actually achieves.
    public static func badgeTextContrast(_ status: BanStatus) -> Double {
        guard let background = restrictionComponents[status] else { return 21 }
        let white = ColourMetrics.contrastRatio(background, RGB(255, 255, 255))
        let black = ColourMetrics.contrastRatio(background, RGB(0, 0, 0))
        return max(white, black)
    }
}
