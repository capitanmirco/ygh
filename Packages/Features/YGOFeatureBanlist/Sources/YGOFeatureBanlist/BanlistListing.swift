import Foundation
import YGOCore
import YGODesignSystem

/// One block of a Forbidden & Limited List.
public struct BanlistGroup: Hashable, Sendable, Identifiable {
    public let status: BanlistStatus
    /// Ordered: monsters, then spells, then traps, then by name.
    public let cards: [BanlistListEntry]

    public var id: BanlistStatus { status }
    public var count: Int { cards.count }

    public init(status: BanlistStatus, cards: [BanlistListEntry]) {
        self.status = status
        self.cards = cards
    }

    public var italianName: String {
        switch status {
        case .forbidden: "Proibite"
        case .limited: "Limitate"
        case .semiLimited: "Semi-limitate"
        }
    }
}

/// Turns a stored list into the three blocks a list is read in.
///
/// The ordering is two enumerations and a string: status, then kind, then
/// name. Expressed in SQL that is a `CASE` ladder nobody can read and that
/// cannot be checked without a database. Expressed here it is a comparator,
/// and the whole of `R1` is arithmetic over entries.
public enum BanlistListing {
    /// Most restrictive first, which is the order a list is published in.
    public static let statusOrder: [BanlistStatus] = [.forbidden, .limited, .semiLimited]

    /// Monsters, then spells, then traps. A player looks for them in that
    /// order because that is the order a decklist is built in.
    static func rank(_ frame: CardFrame?) -> Int {
        // No kind at all: the catalog could not match the entry, so it sorts
        // last within its group rather than vanishing from it.
        frame?.cardType.listingOrder ?? 4
    }

    public static func groups(from entries: [BanlistListEntry]) -> [BanlistGroup] {
        statusOrder.map { status in
            let cards = entries
                .filter { $0.status == status && $0.cardID != nil }
                .sorted { lhs, rhs in
                    let left = rank(lhs.frame), right = rank(rhs.frame)
                    if left != right { return left < right }
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                        == .orderedAscending
                }
            return BanlistGroup(status: status, cards: cards)
        }
    }

    /// Entries the catalog cannot name.
    ///
    /// Counted rather than shown: a row reading "konami_id 4007" among card
    /// names is noise, and dropping them in silence is worse than both. The
    /// number closing the arithmetic is what proves this screen is not
    /// quietly losing rows.
    public static func unmatched(in entries: [BanlistListEntry]) -> Int {
        entries.filter { $0.cardID == nil }.count
    }

    /// What every card on a list reads as, for a screen reader and for the
    /// row itself.
    public static func description(of entry: BanlistListEntry) -> String {
        let kind = entry.frame?.italianName ?? "tipo sconosciuto"
        let status = switch entry.status {
        case .forbidden: "proibita"
        case .limited: "limitata a 1"
        case .semiLimited: "semi-limitata a 2"
        }
        return "\(entry.displayName), \(kind), \(status)"
    }
}
