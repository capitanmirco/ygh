/// A play format a card may belong to.
///
/// The cases are the nine format names the upstream catalog publishes. Only
/// `tcg`, `ocg` and `goat` carry upstream ban data; the rest report membership
/// only, so their restrictions are user-maintained.
public enum CardFormat: String, Hashable, Sendable, Codable, CaseIterable {
    case tcg = "TCG"
    case ocg = "OCG"
    case masterDuel = "Master Duel"
    case goat = "GOAT"
    case ocgGoat = "OCG GOAT"
    case edison = "Edison"
    case duelLinks = "Duel Links"
    case speedDuel = "Speed Duel"
    case commonCharity = "Common Charity"

    /// Whether the upstream catalog publishes a ban list for this format.
    ///
    /// When it does not, restrictions come from the user and must be presented
    /// as such rather than as an authoritative list.
    public var hasUpstreamBanList: Bool {
        switch self {
        case .tcg, .ocg, .goat: true
        case .masterDuel, .ocgGoat, .edison, .duelLinks, .speedDuel, .commonCharity: false
        }
    }
}
