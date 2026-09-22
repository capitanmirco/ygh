/// One of the application's six top-level sections.
///
/// It lives here rather than inside the window because a preference has to
/// store one, and the window is not a thing another module can see. The raw
/// values are stable keys rather than the Italian names shown on screen: what
/// is written to disk must not move when a label is reworded.
public enum AppSection: String, Hashable, Sendable, Codable, CaseIterable {
    case catalog
    case decks
    case collection
    case analytics
    case banlist
    case value

    /// What the window opens on when nothing has been chosen.
    public static let fallback: AppSection = .catalog
}
