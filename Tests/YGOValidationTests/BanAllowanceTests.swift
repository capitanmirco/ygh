import Testing
import YGOCore
@testable import YGOValidation

/// A restriction is not a boolean. The interface has to be able to tell the
/// duelist how many copies they hold and how many they may, which is why the
/// violation carries both figures rather than a flag.
@Suite("Ban allowance")
struct BanAllowanceTests {
    private let validator = DeckValidator()

    private func copyViolations(_ held: Int, _ status: BanStatus) -> [DeckViolation] {
        let (fillerSlots, fillerEntries) = Sample.filler(40, startingAt: 9_000)
        return validator.violations(
            in: Sample.deck([Sample.slot(1, quantity: held)] + fillerSlots),
            using: DeckCardIndex(entries: [Sample.entry(1, name: "Raigeki", ban: status)]
                                 + fillerEntries))
            .filter { if case .overCopyLimit = $0 { true } else { false } }
    }

    /// Evidence for R3.AC4: the violation states what is held against what is
    /// permitted, and names the card it is about.
    @Test func reportsHeldCountAgainstPermittedCountForARestrictedCard() {
        let violations = copyViolations(3, .limited)

        #expect(violations.count == 1)
        guard case .overCopyLimit(let name, let held, let permitted, let reason)? = violations.first
        else { Issue.record("attesa una violazione"); return }
        #expect(name == "Raigeki")
        #expect(held == 3)
        #expect(permitted == 1)
        #expect(reason == .banStatus(.limited))

        // The sentence carries all three, which is what a screen reader reads.
        let sentence = violations[0].sentence
        #expect(sentence.contains("Raigeki"))
        #expect(sentence.contains("3"))
        #expect(sentence.contains("1"))

        // One copy of a Limited card is legal and reports nothing.
        #expect(copyViolations(1, .limited).isEmpty)
    }

    /// Each status permits what the rules say it permits, no more.
    @Test func eachStatusPermitsItsOwnNumberOfCopies() {
        let expected: [(BanStatus, Int)] = [
            (.forbidden, 0), (.limited, 1), (.semiLimited, 2), (.unlimited, 3),
        ]

        for (status, permitted) in expected {
            // At the allowance: legal.
            if permitted > 0 {
                #expect(copyViolations(permitted, status).isEmpty,
                        "\(status) doveva permettere \(permitted) copie")
            }

            // One over: reported, with the right numbers.
            let over = copyViolations(permitted + 1, status)
            #expect(over.count == 1, "\(status) non doveva permettere \(permitted + 1) copie")
            guard case .overCopyLimit(_, let held, let reported, _)? = over.first else { continue }
            #expect(held == permitted + 1)
            #expect(reported == permitted)
        }
    }

    /// A Forbidden card is illegal at one copy, not merely over some threshold.
    @Test func forbiddenCardIsReportedAtASingleCopy() {
        let violations = copyViolations(1, .forbidden)

        #expect(violations.count == 1)
        guard case .overCopyLimit(_, let held, let permitted, let reason)? = violations.first
        else { Issue.record("attesa una violazione"); return }
        #expect(held == 1)
        #expect(permitted == 0)
        #expect(reason == .banStatus(.forbidden))
        #expect(violations[0].sentence.contains("vietata"))
    }
}
