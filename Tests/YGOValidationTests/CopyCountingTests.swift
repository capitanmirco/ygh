import Testing
import YGOCore
@testable import YGOValidation

@Suite("Copy counting")
struct CopyCountingTests {
    private let validator = DeckValidator()

    private func overLimits(_ slots: [DeckSlot], _ entries: [DeckCardIndex.Entry],
                            format: CardFormat = .tcg) -> [DeckViolation] {
        let (fillerSlots, fillerEntries) = Sample.filler(40, startingAt: 9_000)
        return validator.violations(
            in: Sample.deck(format: format, slots + fillerSlots),
            using: DeckCardIndex(entries: entries + fillerEntries))
            .filter { if case .overCopyLimit = $0 { true } else { false } }
    }

    /// Evidence for R3.AC1: the side deck is not a second allowance.
    @Test func countsCopiesAcrossMainExtraAndSideTogether() {
        let entry = Sample.entry(1, name: "Ash Blossom", ban: .limited)

        let split = overLimits(
            [Sample.slot(1, section: .main, quantity: 2, artwork: 1),
             Sample.slot(1, section: .side, quantity: 2, artwork: 1)],
            [entry])

        #expect(split.count == 1)
        guard case .overCopyLimit(let name, let held, let permitted, _)? = split.first else {
            Issue.record("attesa una violazione di copie"); return
        }
        #expect(name == "Ash Blossom")
        #expect(held == 4, "due in main più due in side sono quattro, non due")
        #expect(permitted == 1)
    }

    /// Evidence for R3.AC2: a different printing is not a different card.
    @Test func countsEveryArtworkOfACardAsTheSameCard() {
        let entry = Sample.entry(2, name: "Dark Magician", ban: .unlimited)

        let acrossPrintings = overLimits(
            [Sample.slot(2, quantity: 2, artwork: 2),
             Sample.slot(2, quantity: 2, artwork: 36_996_508)],
            [entry])

        #expect(acrossPrintings.count == 1)
        guard case .overCopyLimit(_, let held, let permitted, let reason)? = acrossPrintings.first
        else { Issue.record("attesa una violazione"); return }
        #expect(held == 4)
        #expect(permitted == 3)
        #expect(reason == .absoluteLimit)

        // Three copies spread over two printings is still legal.
        let legal = overLimits(
            [Sample.slot(2, quantity: 2, artwork: 2),
             Sample.slot(2, quantity: 1, artwork: 36_996_508)],
            [entry])
        #expect(legal.isEmpty)
    }

    /// Evidence for R3.AC3: cards that share a name share one allowance.
    /// `Harpie Lady 1`, `2` and `3` are three cards with one limit between them.
    @Test func countsCardsSharingALimitNameTogether() {
        let harpies = (1...3).map {
            Sample.entry(100 + $0, name: "Harpie Lady \($0)", limitName: "Harpie Lady")
        }

        let overTheLimit = overLimits(
            [Sample.slot(101, quantity: 2), Sample.slot(102, quantity: 2)],
            harpies)

        #expect(overTheLimit.count == 1)
        guard case .overCopyLimit(let name, let held, let permitted, _)? = overTheLimit.first
        else { Issue.record("attesa una violazione"); return }
        #expect(name == "Harpie Lady", "il gruppo deve essere nominato dal limite, non dalla stampa")
        #expect(held == 4)
        #expect(permitted == 3)

        // One of each is three copies of one card, which is legal.
        let legal = overLimits(
            [Sample.slot(101), Sample.slot(102), Sample.slot(103)],
            harpies)
        #expect(legal.isEmpty)

        // A fourth card sharing the name tips it over again.
        let withFourth = overLimits(
            [Sample.slot(101), Sample.slot(102), Sample.slot(103),
             Sample.slot(104)],
            harpies + [Sample.entry(104, name: "Cyber Harpie Lady", limitName: "Harpie Lady")])
        #expect(withFourth.count == 1)
    }

    /// A group is only as free as its most restricted member.
    @Test func appliesTheTightestAllowanceInAGroup() {
        let entries = [
            Sample.entry(201, name: "Umi", limitName: "Umi", ban: .unlimited),
            Sample.entry(202, name: "A Legendary Ocean", limitName: "Umi", ban: .limited),
        ]

        let violations = overLimits(
            [Sample.slot(201, quantity: 1), Sample.slot(202, quantity: 1)],
            entries)

        #expect(violations.count == 1)
        guard case .overCopyLimit(_, let held, let permitted, let reason)? = violations.first
        else { Issue.record("attesa una violazione"); return }
        #expect(held == 2)
        #expect(permitted == 1)
        #expect(reason == .banStatus(.limited))
    }

    /// Evidence for R3.AC5: three is the ceiling even where nobody publishes
    /// a ban list at all.
    @Test func reportsMoreThanThreeCopiesEvenWithoutABanList() {
        let entry = Sample.entry(300, name: "Carta Libera",
                                 formats: [.edison], ban: .unlimited)

        let violations = overLimits(
            [Sample.slot(300, quantity: 4)], [entry], format: .edison)

        let copyIssues = violations.filter { if case .overCopyLimit = $0 { true } else { false } }
        #expect(copyIssues.count == 1)
        guard case .overCopyLimit(_, let held, let permitted, let reason)? = copyIssues.first
        else { Issue.record("attesa una violazione"); return }
        #expect(held == 4)
        #expect(permitted == 3)
        #expect(reason == .absoluteLimit, "non è una banlist a vietarlo, è il limite assoluto")

        // Exactly three is fine.
        let atTheLimit = overLimits(
            [Sample.slot(300, quantity: 3)], [entry], format: .edison)
        #expect(atTheLimit.isEmpty)
    }
}
