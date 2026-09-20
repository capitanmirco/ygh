/// Something that makes a deck illegal.
///
/// Each case carries the numbers behind it rather than a prepared string, so
/// the interface can render it and a screen reader can read it as a sentence
/// without the rules module knowing about either.
public enum DeckViolation: Hashable, Sendable {
    /// A section holds too few or too many cards.
    case sectionSize(section: DeckSection, held: Int, permitted: ClosedRange<Int>)

    /// A card sits in a section its type does not belong to.
    case misplacedCard(card: CardIdentifier, cardName: String, section: DeckSection)

    /// More copies than the format's restriction permits.
    case overCopyLimit(
        limitName: String,
        held: Int,
        permitted: Int,
        because: CopyLimitReason)

    /// A card that is not part of the format's pool at all.
    case outsideFormatPool(card: CardIdentifier, cardName: String, format: CardFormat)

    /// Why a copy limit is what it is.
    public enum CopyLimitReason: Hashable, Sendable {
        case banStatus(BanStatus)
        /// The three-copy ceiling that holds regardless of any ban list.
        case absoluteLimit
    }
}

extension DeckViolation {
    /// A sentence naming the card and the rule, for the interface and for
    /// assistive technology. Italian, like the rest of what the user reads.
    public var sentence: String {
        switch self {
        case .sectionSize(let section, let held, let permitted):
            let name = section.italianName
            if held < permitted.lowerBound {
                return "\(name): \(held) carte, il minimo è \(permitted.lowerBound)."
            }
            return "\(name): \(held) carte, il massimo è \(permitted.upperBound)."

        case .misplacedCard(_, let cardName, let section):
            return section == .extra
                ? "\(cardName) non può stare nell'Extra Deck."
                : "\(cardName) va nell'Extra Deck, non in \(section.italianName)."

        case .overCopyLimit(let limitName, let held, let permitted, let because):
            let copies = held == 1 ? "1 copia" : "\(held) copie"
            switch because {
            case .banStatus(let status):
                return "\(limitName): \(copies), il massimo è \(permitted) (\(status.italianName))."
            case .absoluteLimit:
                return "\(limitName): \(copies), il massimo è sempre \(permitted)."
            }

        case .outsideFormatPool(_, let cardName, let format):
            return "\(cardName) non fa parte del formato \(format.rawValue)."
        }
    }
}

extension DeckSection {
    public var italianName: String {
        switch self {
        case .main: "Deck principale"
        case .extra: "Extra Deck"
        case .side: "Side Deck"
        }
    }
}

extension BanStatus {
    public var italianName: String {
        switch self {
        case .forbidden: "vietata"
        case .limited: "limitata"
        case .semiLimited: "semi-limitata"
        case .unlimited: "senza limiti"
        }
    }
}
