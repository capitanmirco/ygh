import Testing
import YGOCore
@testable import YGOValidation

@Suite("Deck placement rules")
struct DeckPlacementRuleTests {
    private let validator = DeckValidator()

    private func misplaced(_ slots: [DeckSlot], _ entries: [DeckCardIndex.Entry]) -> [DeckViolation] {
        let (fillerSlots, fillerEntries) = Sample.filler(40, startingAt: 5_000)
        return validator.violations(
            in: Sample.deck(slots + fillerSlots),
            using: DeckCardIndex(entries: entries + fillerEntries))
            .filter { if case .misplacedCard = $0 { true } else { false } }
    }

    /// Evidence for R2.AC4: an Extra Deck card anywhere else is named.
    @Test func extraDeckCardOutsideExtraSectionIsReportedByName() {
        let extraFrames: [CardFrame] = [.fusion, .synchro, .xyz, .link,
                                        .fusionPendulum, .synchroPendulum, .xyzPendulum]

        for (offset, frame) in extraFrames.enumerated() {
            let id = 100 + offset
            let inMain = misplaced(
                [Sample.slot(id, section: .main)],
                [Sample.entry(id, name: "Extra \(offset)", frame: frame)])
            #expect(inMain.count == 1, "\(frame) nel main doveva essere segnalata")
            guard case .misplacedCard(_, let name, let section)? = inMain.first else { return }
            #expect(name == "Extra \(offset)")
            #expect(section == .main)

            // The same card in the extra section is correct.
            let inExtra = misplaced(
                [Sample.slot(id, section: .extra)],
                [Sample.entry(id, name: "Extra \(offset)", frame: frame)])
            #expect(inExtra.isEmpty)
        }

        // The side section is no more allowed to hold one than the main is.
        let inSide = misplaced(
            [Sample.slot(200, section: .side)],
            [Sample.entry(200, name: "Fusione", frame: .fusion)])
        #expect(inSide.count == 1)
    }

    /// Evidence for R2.AC5: a main-deck card in the Extra Deck is named too.
    @Test func mainDeckCardInExtraSectionIsReportedByName() {
        let mainFrames: [CardFrame] = [.normal, .effect, .ritual, .spell, .trap,
                                       .normalPendulum, .effectPendulum]

        for (offset, frame) in mainFrames.enumerated() {
            let id = 300 + offset
            let violations = misplaced(
                [Sample.slot(id, section: .extra)],
                [Sample.entry(id, name: "Principale \(offset)", frame: frame)])
            #expect(violations.count == 1, "\(frame) nell'extra doveva essere segnalata")
            guard case .misplacedCard(_, let name, let section)? = violations.first else { return }
            #expect(name == "Principale \(offset)")
            #expect(section == .extra)
        }
    }

    /// A card in the wrong place is one problem, not one per copy.
    @Test func reportsAMisplacedCardOnceHoweverManyCopies() {
        let violations = misplaced(
            [Sample.slot(400, section: .main, quantity: 3)],
            [Sample.entry(400, name: "Fusione", frame: .fusion)])
        #expect(violations.count == 1)
    }
}
