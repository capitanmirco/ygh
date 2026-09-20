import Testing
import YGOCore
@testable import YGOValidation

/// Where a card lands when the user does not choose a section.
///
/// This is deliberately the same rule the placement pass enforces: if the two
/// ever disagreed, the application would put a card somewhere and then report
/// it for being there.
@Suite("Default section")
struct DefaultSectionTests {
    private let validator = DeckValidator()

    /// A card placed by the default rule, checked against the placement pass
    /// with a legal main deck around it so section sizes stay out of the way.
    private func misplaced(_ slots: [DeckSlot], _ entries: [DeckCardIndex.Entry]) -> [DeckViolation] {
        let (fillerSlots, fillerEntries) = Sample.filler(40, startingAt: 5_000)
        return validator.violations(
            in: Sample.deck(slots + fillerSlots),
            using: DeckCardIndex(entries: entries + fillerEntries))
            .filter { if case .misplacedCard = $0 { true } else { false } }
    }
    /// Evidence for R2.AC6: the rule that places a card and the rule that
    /// judges its placement are the same rule.
    @Test func placesExtraDeckFramesInTheExtraSectionAndTheRestInMain() {
        for frame in [CardFrame.fusion, .synchro, .xyz, .link,
                      .fusionPendulum, .synchroPendulum, .xyzPendulum] {
            #expect(DeckValidator.defaultSection(for: frame) == .extra)
        }

        for frame in [CardFrame.normal, .effect, .ritual, .spell, .trap, .token,
                      .normalPendulum, .effectPendulum, .ritualPendulum] {
            #expect(DeckValidator.defaultSection(for: frame) == .main)
        }

        // Anything the placement rule sends to a section must not then be
        // reported as misplaced there.
        for frame in [CardFrame.fusion, .effect, .spell, .link] {
            let section = DeckValidator.defaultSection(for: frame)
            let violations = misplaced(
                [Sample.slot(500, section: section)],
                [Sample.entry(500, frame: frame)])
            #expect(violations.isEmpty, "\(frame) collocata in \(section) e poi segnalata")
        }
    }
}
