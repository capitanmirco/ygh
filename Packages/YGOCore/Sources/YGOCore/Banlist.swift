import Foundation

/// The formats whose Forbidden & Limited Lists the history source publishes.
///
/// Separate from ``CardFormat`` on purpose. The catalog's formats describe what
/// a card is legal in; these four name directories in a second upstream, and
/// Rush Duel has no ``CardFormat`` counterpart. Folding the two together would
/// force a new case on every exhaustive switch the catalog already owns.
public enum BanlistFormat: String, Hashable, Sendable, CaseIterable, Codable {
    case tcg
    case ocg
    case masterDuel = "master-duel"
    case rush

    /// The catalog format this history describes, when the catalog has one.
    public var cardFormat: CardFormat? {
        switch self {
        case .tcg: .tcg
        case .ocg: .ocg
        case .masterDuel: .masterDuel
        case .rush: nil
        }
    }

    public var displayName: String {
        switch self {
        case .tcg: "TCG"
        case .ocg: "OCG"
        case .masterDuel: "Master Duel"
        case .rush: "Rush Duel"
        }
    }
}

/// A status as the source publishes it: 0, 1 or 2.
///
/// There is deliberately no `unlimited` case. The source never writes one, and
/// absence from a list is what carries that meaning (`C3`). A fourth case would
/// invite a stored row for every unrestricted card on every list, which is a
/// quarter of a million rows saying nothing.
public enum BanlistStatus: Int, Hashable, Sendable, CaseIterable, Codable {
    case forbidden = 0
    case limited = 1
    case semiLimited = 2

    /// The value written to `banlist_entry.status`.
    public var storedValue: String {
        switch self {
        case .forbidden: "forbidden"
        case .limited: "limited"
        case .semiLimited: "semi_limited"
        }
    }

    public init?(storedValue: String) {
        switch storedValue {
        case "forbidden": self = .forbidden
        case "limited": self = .limited
        case "semi_limited": self = .semiLimited
        default: return nil
        }
    }

    /// The catalog's four-case status, which does have an `unlimited` member.
    public var banStatus: BanStatus {
        switch self {
        case .forbidden: .forbidden
        case .limited: .limited
        case .semiLimited: .semiLimited
        }
    }

    public var copiesAllowed: Int {
        switch self {
        case .forbidden: 0
        case .limited: 1
        case .semiLimited: 2
        }
    }
}

/// One published list, as decoded from a `<date>.vector.json` body.
///
/// Keyed by `konami_id` rather than by card: the source publishes identifiers,
/// and resolving them to cards at decode time would discard the ones the
/// catalog has not caught up with (`R1.AC6`).
public struct PublishedBanlist: Hashable, Sendable {
    public let effectiveDate: String
    public let statuses: [Int: BanlistStatus]

    public init(effectiveDate: String, statuses: [Int: BanlistStatus]) {
        self.effectiveDate = effectiveDate
        self.statuses = statuses
    }

    public func status(forKonamiID konamiID: Int) -> BanlistStatus? {
        statuses[konamiID]
    }

    public func konamiIDs(at status: BanlistStatus) -> [Int] {
        statuses.filter { $0.value == status }.keys.sorted()
    }

    public var count: Int { statuses.count }
}

extension PublishedBanlist: Decodable {
    private enum CodingKeys: String, CodingKey {
        case date
        case regulation
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let date = try container.decode(String.self, forKey: .date)
        let raw = try container.decode([String: Int].self, forKey: .regulation)

        var statuses: [Int: BanlistStatus] = [:]
        statuses.reserveCapacity(raw.count)
        for (key, value) in raw {
            guard let konamiID = Int(key) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .regulation, in: container,
                    debugDescription: "identifier \(key) is not a number")
            }
            guard let status = BanlistStatus(rawValue: value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .regulation, in: container,
                    debugDescription: "status \(value) is not one of 0, 1, 2")
            }
            statuses[konamiID] = status
        }
        self.init(effectiveDate: date, statuses: statuses)
    }
}
