import Testing
import YGOCore
@testable import YGOValidation

@Suite("Deck size rules")
struct DeckSizeRuleTests {
    private let validator = DeckValidator()

    private func sizeViolations(_ count: Int, in section: DeckSection) -> [DeckViolation] {
        let (slots, entries) = Sample.filler(count, section: section)
        var all = slots
        var all2 = entries
        // The main section has a floor, so a deck testing another section needs
        // a legal main deck or that floor drowns out what is being measured.
        if section != .main {
            let (mainSlots, mainEntries) = Sample.filler(40, startingAt: 5_000)
            all += mainSlots
            all2 += mainEntries
        }
        return validator.violations(
            in: Sample.deck(all), using: DeckCardIndex(entries: all2))
            .filter { if case .sectionSize = $0 { true } else { false } }
    }

    /// Evidence for R2.AC1: forty through sixty, and nothing outside it.
    @Test func mainSectionIsLegalBetweenFortyAndSixtyCards() {
        #expect(!sizeViolations(39, in: .main).isEmpty)
        #expect(sizeViolations(40, in: .main).isEmpty)
        #expect(sizeViolations(50, in: .main).isEmpty)
        #expect(sizeViolations(60, in: .main).isEmpty)
        #expect(!sizeViolations(61, in: .main).isEmpty)

        // The violation says which bound was broken.
        let tooFew = sizeViolations(39, in: .main)
        guard case .sectionSize(let section, let held, let permitted)? = tooFew.first else {
            Issue.record("attesa una violazione di dimensione")
            return
        }
        #expect(section == .main)
        #expect(held == 39)
        #expect(permitted == 40...60)
    }

    /// Evidence for R2.AC2: up to fifteen, and empty is fine.
    @Test func extraSectionIsLegalUpToFifteenCards() {
        #expect(sizeViolations(0, in: .extra).isEmpty)
        #expect(sizeViolations(15, in: .extra).isEmpty)
        #expect(!sizeViolations(16, in: .extra).isEmpty)
    }

    /// Evidence for R2.AC3: the side section is capped the same way.
    @Test func sideSectionIsLegalUpToFifteenCards() {
        #expect(sizeViolations(0, in: .side).isEmpty)
        #expect(sizeViolations(15, in: .side).isEmpty)
        #expect(!sizeViolations(16, in: .side).isEmpty)
    }

    /// Copies count, not entries: twenty cards held three times each is sixty.
    @Test func sizeCountsCopiesRatherThanDistinctCards() {
        let slots = (0..<20).map { Sample.slot(1_000 + $0, quantity: 3) }
        let entries = (0..<20).map { Sample.entry(1_000 + $0) }

        let violations = validator.violations(
            in: Sample.deck(slots), using: DeckCardIndex(entries: entries))
        #expect(!violations.contains { if case .sectionSize = $0 { true } else { false } })
    }
}
