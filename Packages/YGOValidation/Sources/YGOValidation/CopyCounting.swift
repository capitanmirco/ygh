import YGOCore

/// How many copies of each limited name a deck holds.
///
/// Copies are grouped by limit name rather than by card, which is what makes
/// `Harpie Lady 1`, `2` and `3` share one allowance between them, and what
/// makes two printings of one card count as two copies rather than one each.
struct CopyTally {
    struct Group {
        let limitName: String
        let held: Int
        /// The tightest allowance any card in the group carries. A group is
        /// only as free as its most restricted member.
        let permitted: Int
        let reason: DeckViolation.CopyLimitReason
    }

    let groups: [Group]

    init(deck: Deck, index: DeckCardIndex, absoluteLimit: Int) {
        var heldByName: [String: Int] = [:]
        var tightest: [String: (permitted: Int, reason: DeckViolation.CopyLimitReason)] = [:]

        for slot in deck.slots {
            guard let entry = index[slot.card] else { continue }
            let name = entry.limitName

            // Every section and every printing counts into the same figure.
            heldByName[name, default: 0] += slot.quantity

            let allowance = min(absoluteLimit, entry.banStatus.copyAllowance.maximumCopies)
            let reason: DeckViolation.CopyLimitReason =
                entry.banStatus == .unlimited ? .absoluteLimit : .banStatus(entry.banStatus)

            if let current = tightest[name], current.permitted <= allowance { continue }
            tightest[name] = (allowance, reason)
        }

        groups = heldByName.map { name, held in
            let limit = tightest[name] ?? (absoluteLimit, .absoluteLimit)
            return Group(limitName: name, held: held,
                         permitted: limit.permitted, reason: limit.reason)
        }
        .sorted { $0.limitName < $1.limitName }
    }
}
