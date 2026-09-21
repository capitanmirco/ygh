import SwiftUI

/// The shared visual vocabulary. Features read these rather than writing
/// literals, so a change to spacing or colour lands everywhere at once.
public enum Theme {
    public enum Spacing {
        public static let hair: CGFloat = 2
        public static let tight: CGFloat = 6
        public static let snug: CGFloat = 10
        public static let regular: CGFloat = 16
        public static let loose: CGFloat = 24
        public static let section: CGFloat = 32
    }

    public enum Radius {
        public static let card: CGFloat = 8
        public static let control: CGFloat = 6
        public static let marker: CGFloat = 2
    }

    public enum Palette {
        /// Card artwork supplies nearly all the colour in this interface, so
        /// the surrounding surfaces stay neutral and let it carry the page.
        public static let surface = Color(nsColor: .windowBackgroundColor)
        public static let raisedSurface = Color(nsColor: .controlBackgroundColor)
        /// Defined from the measured components in `FramePalette.swift`, not
        /// from the system aliases: the secondary label does not hold 4.5:1
        /// against the overlay surface in dark appearance.
        public static var primaryText: Color { text }
        public static var secondaryText: Color { secondary }
        public static let separator = Color(nsColor: .separatorColor)
        public static let accent = Color.accentColor

        /// State tints. Named so nobody has to decide what 0.18 meant.
        public static let selection = accent.opacity(0.18)
        public static let dropTarget = accent.opacity(0.15)
        public static let chartFill = accent.opacity(0.65)

        /// Restriction badges. Red reads as forbidden across the game's own
        /// materials, so it is kept for exactly that.
        public static let forbidden = Color(red: 0.78, green: 0.16, blue: 0.16)
        public static let limited = Color(red: 0.85, green: 0.47, blue: 0.09)
        public static let semiLimited = Color(red: 0.72, green: 0.62, blue: 0.10)
    }

    /// Five sizes between 11 and 13 points is not a scale, it is a wall. The
    /// levels below are ordered so a screen has a shape: a title you land on,
    /// headings you scan, body you read, figures you compare and captions you
    /// consult.
    public enum Typography {
        /// The one figure a screen is about: a collection's worth, a deck's
        /// cost. Larger than a section heading because it is the answer, not a
        /// label for one.
        public static let heroFigure = Font.system(size: 34, weight: .semibold).monospacedDigit()
        public static let screenTitle = Font.system(size: 22, weight: .semibold)
        public static let sectionTitle = Font.system(size: 15, weight: .semibold)
        /// Numbers, in a form whose digits do not change width. A total that
        /// shifts the text beside it as it changes is the kind of thing nobody
        /// reports and everybody notices.
        public static let figure = Font.system(size: 17, weight: .medium).monospacedDigit()
        public static let body = Font.system(size: 13)
        public static let caption = Font.system(size: 11)
        /// The smallest thing on screen: a one-letter restriction badge.
        public static let badge = Font.system(size: 10, weight: .bold)

        public static let cardTitle = Font.system(size: 12, weight: .medium)
        public static let cardSubtitle = Font.system(size: 11, weight: .regular)

        /// The scale's own description, so its ordering can be checked rather
        /// than eyeballed.
        public enum Level: String, CaseIterable, Sendable {
            case screenTitle, figure, sectionTitle, body, caption

            /// Point size and weight, most prominent first.
            public var size: Double {
                switch self {
                case .screenTitle: 22
                case .figure: 17
                case .sectionTitle: 15
                case .body: 13
                case .caption: 11
                }
            }

            public var isMonospacedDigit: Bool { self == .figure }
        }
    }

    /// Grid geometry. Card art is 421 by 614, so tiles keep that ratio and the
    /// rows stay even whatever the window width.
    public enum Grid {
        public static let cardAspectRatio: CGFloat = 421.0 / 614.0
        public static let minimumTileWidth: CGFloat = 132
        public static let spacing: CGFloat = 14
    }
}

extension Theme {
    /// How wide an inspector is allowed to be.
    ///
    /// A rule rather than a number in a view, so both screens that show one
    /// follow it and so the rule itself can be checked without rendering.
    public enum Inspector {
        /// The most of the window an inspector may take. A card detail beside
        /// a grid and a filter panel is a third column, and three columns at
        /// laptop width are three strips.
        public static let maximumShare: CGFloat = 0.25
        /// Narrow enough to leave room, wide enough to read a card's effect.
        /// Below this the window narrows the content beside it instead.
        public static let minimumWidth: CGFloat = 260

        public static func width(forWindowWidth total: CGFloat) -> CGFloat {
            max(minimumWidth, total * maximumShare)
        }

        /// True when the window is too narrow to honour both the share and
        /// the floor, which is when the floor wins.
        public static func isFloorApplied(forWindowWidth total: CGFloat) -> Bool {
            total * maximumShare < minimumWidth
        }
    }
}
