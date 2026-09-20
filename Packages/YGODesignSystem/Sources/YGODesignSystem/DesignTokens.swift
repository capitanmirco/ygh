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
    }

    public enum Palette {
        /// Card artwork supplies nearly all the colour in this interface, so
        /// the surrounding surfaces stay neutral and let it carry the page.
        public static let surface = Color(nsColor: .windowBackgroundColor)
        public static let raisedSurface = Color(nsColor: .controlBackgroundColor)
        public static let primaryText = Color(nsColor: .labelColor)
        public static let secondaryText = Color(nsColor: .secondaryLabelColor)
        public static let separator = Color(nsColor: .separatorColor)
        public static let accent = Color.accentColor

        /// Restriction badges. Red reads as forbidden across the game's own
        /// materials, so it is kept for exactly that.
        public static let forbidden = Color(red: 0.78, green: 0.16, blue: 0.16)
        public static let limited = Color(red: 0.85, green: 0.47, blue: 0.09)
        public static let semiLimited = Color(red: 0.72, green: 0.62, blue: 0.10)
    }

    public enum Typography {
        public static let cardTitle = Font.system(size: 12, weight: .medium)
        public static let cardSubtitle = Font.system(size: 11, weight: .regular)
        public static let sectionTitle = Font.system(size: 13, weight: .semibold)
        public static let body = Font.system(size: 13)
        public static let caption = Font.system(size: 11)
    }

    /// Grid geometry. Card art is 421 by 614, so tiles keep that ratio and the
    /// rows stay even whatever the window width.
    public enum Grid {
        public static let cardAspectRatio: CGFloat = 421.0 / 614.0
        public static let minimumTileWidth: CGFloat = 132
        public static let spacing: CGFloat = 14
    }
}
