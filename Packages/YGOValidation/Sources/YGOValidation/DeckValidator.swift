import YGOCore

/// Decides whether a deck is legal, and says why when it is not.
///
/// Every rule reads the same snapshot and appends to the same array. Nothing
/// here performs a lookup, a query or an allocation beyond that array, which is
/// what lets a re-evaluation run on every keystroke rather than on a timer.
///
/// The passes never stop at the first problem: a duelist fixing a deck wants
/// the whole list, not one item at a time.
public struct DeckValidator: DeckValidating {
    /// The ceiling that holds in every format, including those with no ban
    /// list at all.
    public static let absoluteCopyLimit = 3

    public init() {}

    public func violations(in deck: Deck, using index: DeckCardIndex) -> [DeckViolation] {
        var found: [DeckViolation] = []
        appendSectionSizeViolations(deck, to: &found)
        appendPlacementViolations(deck, index, to: &found)
        appendCopyLimitViolations(deck, index, to: &found)
        appendFormatPoolViolations(deck, index, to: &found)
        return found
    }

    // MARK: - Sizes

    private func appendSectionSizeViolations(_ deck: Deck, to found: inout [DeckViolation]) {
        for section in DeckSection.allCases {
            let held = deck.count(in: section)
            let permitted = section.permittedRange

            // An empty extra or side section is legal; an empty main section is
            // a deck that has not been built yet, and its floor still applies.
            if section != .main, held == 0 { continue }
            guard !permitted.contains(held) else { continue }

            found.append(.sectionSize(section: section, held: held, permitted: permitted))
        }
    }

    // MARK: - Copies

    private func appendCopyLimitViolations(
        _ deck: Deck,
        _ index: DeckCardIndex,
        to found: inout [DeckViolation]
    ) {
        let tally = CopyTally(deck: deck, index: index, absoluteLimit: Self.absoluteCopyLimit)

        for group in tally.groups where group.held > group.permitted {
            found.append(.overCopyLimit(
                limitName: group.limitName,
                held: group.held,
                permitted: group.permitted,
                because: group.reason))
        }
    }

    // MARK: - Format pool

    /// A format is not only a ban list: a card released after a retro format's
    /// cutoff is not legal in it at any count.
    private func appendFormatPoolViolations(
        _ deck: Deck,
        _ index: DeckCardIndex,
        to found: inout [DeckViolation]
    ) {
        var reported: Set<CardIdentifier> = []

        for slot in deck.slots {
            guard let entry = index[slot.card], !reported.contains(slot.card) else { continue }
            guard !entry.formats.contains(deck.format) else { continue }

            reported.insert(slot.card)
            found.append(.outsideFormatPool(
                card: slot.card, cardName: entry.name, format: deck.format))
        }
    }

    // MARK: - Placement

    private func appendPlacementViolations(
        _ deck: Deck,
        _ index: DeckCardIndex,
        to found: inout [DeckViolation]
    ) {
        // Report each card once, however many copies of it sit in the wrong
        // place: the mistake is the card, not each copy of it.
        var reported: Set<CardIdentifier> = []

        for slot in deck.slots {
            guard let entry = index[slot.card], !reported.contains(slot.card) else { continue }

            let belongsInExtra = entry.frame.belongsInExtraDeck
            let isInExtra = slot.section == .extra
            guard belongsInExtra != isInExtra else { continue }

            reported.insert(slot.card)
            found.append(.misplacedCard(
                card: slot.card, cardName: entry.name, section: slot.section))
        }
    }
}

extension DeckValidator {
    /// Where a card goes when the user does not say.
    ///
    /// The same rule the placement pass enforces, so the two cannot disagree
    /// about what belongs in the Extra Deck.
    public static func defaultSection(for frame: CardFrame) -> DeckSection {
        frame.belongsInExtraDeck ? .extra : .main
    }
}
