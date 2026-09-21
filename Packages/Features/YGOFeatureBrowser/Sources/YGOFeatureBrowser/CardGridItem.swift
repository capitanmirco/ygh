import YGOCore

/// One tile in the card grid, already resolved into what is drawn.
///
/// The view model does the language and artwork resolution so the view holds no
/// policy, and so both can be asserted without rendering anything.
public struct CardGridItem: Identifiable, Hashable, Sendable {
    public let id: CardIdentifier
    public let title: String
    public let subtitle: String
    /// True when the title fell back to English because no translation exists.
    public let isUntranslated: Bool
    public let artwork: ArtworkPresentation
    public let banStatus: BanStatus
    /// What the card is. Carried here so the tile marks it without asking the
    /// catalog again, and so the marker can be asserted without rendering.
    public let frame: CardFrame

    public init(
        id: CardIdentifier,
        title: String,
        subtitle: String,
        isUntranslated: Bool,
        artwork: ArtworkPresentation,
        banStatus: BanStatus,
        frame: CardFrame
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.isUntranslated = isUntranslated
        self.artwork = artwork
        self.banStatus = banStatus
        self.frame = frame
    }

    /// What assistive technology reads out.
    ///
    /// A tile whose artwork has not arrived is still announced by name and
    /// type, so the grid is navigable before any image is on disk.
    public var accessibilityLabel: String {
        var parts = [title, subtitle]
        if banStatus != .unlimited {
            parts.append(banStatus.spokenDescription)
        }
        if isUntranslated {
            parts.append("in inglese")
        }
        return parts.joined(separator: ", ")
    }
}

extension BanStatus {
    /// Read aloud rather than shown as a badge colour, which conveys nothing
    /// to a screen reader.
    public var spokenDescription: String {
        switch self {
        case .forbidden: "vietata"
        case .limited: "limitata a 1"
        case .semiLimited: "semi-limitata a 2"
        case .unlimited: "nessun limite"
        }
    }
}

/// The regions keyboard focus moves through, in tab order.
public enum BrowserFocusRegion: Int, CaseIterable, Hashable, Sendable {
    case searchField
    case filters
    case grid
}
