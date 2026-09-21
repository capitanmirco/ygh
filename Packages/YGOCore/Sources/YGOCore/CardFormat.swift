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
    /// Whether the player going first draws on their first turn.
    ///
    /// Not published by the catalog: this comes from the formats' own rule
    /// documents. The 2008 rules had the first player draw, and the modern
    /// rules removed it to offset the advantage of building a board first.
    /// Edison looks modern but is a 2010 event played under the 2008 rules,
    /// so it draws.
    ///
    /// The difference is one card, and one card is 5.7 percentage points on
    /// three copies in forty. Getting it wrong would make every figure in the
    /// analytics quietly wrong for a retro deck.
    public var firstPlayerDraws: Bool {
        switch self {
        case .goat, .ocgGoat, .edison: true
        case .tcg, .ocg, .masterDuel, .duelLinks, .speedDuel, .commonCharity: false
        }
    }

    /// Which published list set describes this format.
    ///
    /// GOAT and Edison are TCG formats frozen at a particular list, so their
    /// lists come from the TCG set rather than from a set of their own — the
    /// source publishes none for them.
    public var banlistFormat: BanlistFormat {
        switch self {
        case .ocg, .ocgGoat: .ocg
        case .masterDuel: .masterDuel
        case .tcg, .goat, .edison, .duelLinks, .speedDuel, .commonCharity: .tcg
        }
    }

    /// The published list this format is frozen at, when it is one.
    ///
    /// GOAT is the TCG list the source dates 2005-03-01: Change of Heart,
    /// Magical Scientist and Fiber Jar forbidden, Graceful Charity and Black
    /// Luster Soldier still limited. Edison is 2010-03-01, with Brionac and
    /// Dark Armed Dragon limited.
    public var definingListDate: String? {
        switch self {
        case .goat, .ocgGoat: "2005-03-01"
        case .edison: "2010-03-01"
        default: nil
        }
    }

    public var hasUpstreamBanList: Bool {
        switch self {
        case .tcg, .ocg, .goat: true
        case .masterDuel, .ocgGoat, .edison, .duelLinks, .speedDuel, .commonCharity: false
        }
    }
}
