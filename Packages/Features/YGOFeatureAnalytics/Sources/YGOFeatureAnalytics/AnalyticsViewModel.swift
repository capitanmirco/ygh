import Foundation
import Observation
import YGOAnalytics
import YGOCore

/// The regions keyboard focus moves through in the analytics view.
public enum AnalyticsFocusRegion: Int, CaseIterable, Hashable, Sendable {
    case playOrder
    case breakdowns
    case cardList
    case probabilityTable
}

/// Drives the analytics view.
///
/// Holds no maths of its own: every figure comes from `YGOAnalytics`, so what
/// is shown and what is tested are the same numbers.
@MainActor
@Observable
public final class AnalyticsViewModel {
    public private(set) var deck: Deck?
    public private(set) var mainBreakdown: DeckBreakdown?
    public private(set) var extraBreakdown: DeckBreakdown?
    public private(set) var odds: [DrawOdds] = []
    public private(set) var table: CopyCountTable?
    public private(set) var dealtHand: [String] = []
    public private(set) var focusedRegion: AnalyticsFocusRegion = .playOrder
    public private(set) var selectedIndex: Int?

    public private(set) var playingFirst = true

    private var index = DeckCardIndex(entries: [])

    public init() {}

    // MARK: - Loading

    public func load(deck: Deck, index: DeckCardIndex) {
        self.deck = deck
        self.index = index
        recompute()
    }

    /// Going second is a different question, so every figure is recomputed
    /// rather than adjusted.
    public func setPlayingFirst(_ value: Bool) {
        guard value != playingFirst else { return }
        playingFirst = value
        recompute()
    }

    private func recompute() {
        guard let deck else {
            mainBreakdown = nil
            extraBreakdown = nil
            odds = []
            table = nil
            return
        }

        mainBreakdown = deck.breakdown(of: .main, using: index)
        extraBreakdown = deck.breakdown(of: .extra, using: index)

        // One row per distinct card in the main section, most likely first.
        let cards = Set(deck.slots(in: .main).map(\.card))
        odds = cards
            .map { Hypergeometric.odds(for: $0, in: deck, index: index,
                                       playingFirst: playingFirst) }
            .sorted { lhs, rhs in
                lhs.atLeastOne == rhs.atLeastOne
                    ? lhs.cardName < rhs.cardName
                    : lhs.atLeastOne > rhs.atLeastOne
            }

        if odds.isEmpty { selectedIndex = nil }
        else { selectedIndex = min(selectedIndex ?? 0, odds.count - 1) }
        refreshTable()
    }

    private func refreshTable() {
        guard let deck, let selected = selectedOdds else {
            table = nil
            return
        }
        table = Hypergeometric.copyCountTable(
            for: selected.card, in: deck, index: index, playingFirst: playingFirst)
    }

    public var selectedOdds: DrawOdds? {
        guard let selectedIndex, odds.indices.contains(selectedIndex) else { return nil }
        return odds[selectedIndex]
    }

    /// The hand every figure on screen was computed against.
    public var hand: OpeningHand? { odds.first?.hand ?? deck.map {
        OpeningHand(format: $0.format, playingFirst: playingFirst)
    } }

    // MARK: - Dealing

    /// Deals a hand so a percentage becomes something to look at.
    public func dealHand(seed: UInt64 = UInt64.random(in: 0..<UInt64.max)) {
        guard let deck else { return }
        let simulator = HandSimulator(deck: deck, playingFirst: playingFirst)
        dealtHand = simulator.deal(seed: seed).drawn.map {
            index[$0]?.name ?? "Carta \($0.rawValue)"
        }
    }

    // MARK: - Keyboard

    public func advanceFocus() {
        let all = AnalyticsFocusRegion.allCases
        let next = (all.firstIndex(of: focusedRegion).map { $0 + 1 } ?? 0) % all.count
        focusedRegion = all[next]
    }

    public func retreatFocus() {
        let all = AnalyticsFocusRegion.allCases
        let current = all.firstIndex(of: focusedRegion) ?? 0
        focusedRegion = all[(current - 1 + all.count) % all.count]
    }

    public func focusRegion(_ region: AnalyticsFocusRegion) {
        focusedRegion = region
    }

    /// Stops at the ends rather than wrapping, so the edge of the list is
    /// perceptible without sight.
    public func moveSelection(by offset: Int) {
        guard !odds.isEmpty else { return }
        selectedIndex = max(0, min(odds.count - 1, (selectedIndex ?? 0) + offset))
        refreshTable()
    }

    /// Every figure on screen, as sentences, which is what a screen reader reads.
    public var sentences: [String] { odds.map(\.sentence) }
}
