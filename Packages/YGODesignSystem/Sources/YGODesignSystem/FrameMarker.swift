import SwiftUI
import YGOCore

/// The one way a card's frame is shown: a bar or a dot in its colour.
///
/// A marker rather than a fill behind text, which is the line between colourful
/// and loud. Nothing is written on top of it, so its contrast never has to
/// carry type.
public struct FrameMarker: View {
    public enum Shape: Sendable {
        /// A bar along the leading edge, for tiles and rows.
        case bar
        /// A dot, for dense lists and headers.
        case dot
    }

    private let frame: CardFrame
    private let shape: Shape

    public init(_ frame: CardFrame, shape: Shape = .bar) {
        self.frame = frame
        self.shape = shape
    }

    public var body: some View {
        Group {
            switch shape {
            case .bar:
                RoundedRectangle(cornerRadius: Theme.Radius.marker)
                    .fill(Theme.Palette.frame(frame))
                    .frame(width: Theme.Marker.barWidth)
            case .dot:
                Circle()
                    .fill(Theme.Palette.frame(frame))
                    .frame(width: Theme.Marker.dotSize, height: Theme.Marker.dotSize)
            }
        }
        // The colour is never the only way the fact is available: the frame's
        // name is read aloud beside it.
        .accessibilityLabel(frame.italianName)
    }
}

extension Theme {
    public enum Marker {
        public static let barWidth: CGFloat = 4
        public static let dotSize: CGFloat = 8
    }
}

extension CardFrame {
    /// What the marker means, in words. `NFR1` requires that colour is never
    /// the only way a fact is conveyed.
    public var italianName: String {
        switch self {
        case .normal: "Mostro Normale"
        case .effect: "Mostro Effetto"
        case .ritual, .ritualPendulum: "Mostro Rituale"
        case .fusion, .fusionPendulum: "Mostro Fusione"
        case .synchro, .synchroPendulum: "Mostro Synchro"
        case .xyz, .xyzPendulum: "Mostro Xyz"
        case .link: "Mostro Link"
        case .normalPendulum: "Mostro Normale Pendulum"
        case .effectPendulum: "Mostro Effetto Pendulum"
        case .spell: "Magia"
        case .trap: "Trappola"
        case .token: "Token"
        case .skill: "Abilità"
        }
    }
}

/// The frames a breakdown's categories stand for.
///
/// A statistics screen counts monsters, spells and traps rather than the
/// seventeen frames, so it borrows the colour of the frame each category is
/// mostly made of. Nothing else in the application should need this.
public enum BreakdownPalette {
    public static func frame(forKind kind: String) -> CardFrame {
        switch kind {
        case "monster": .effect
        case "spell": .spell
        case "trap": .trap
        default: .token
        }
    }

    public static func colour(forKind kind: String) -> Color {
        Theme.Palette.frame(frame(forKind: kind))
    }
}
