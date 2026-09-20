import Foundation
import Observation
import YGOCore
import YGOPricing

/// The regions keyboard focus moves through in the valuation view.
public enum PricingFocusRegion: Int, CaseIterable, Hashable, Sendable {
    case sourcePicker
    case totals
    case mostValuable
}

/// Drives the valuation view.
///
/// Holds no arithmetic of its own: every figure comes from `YGOPricing`, so
/// what is shown and what is tested are the same numbers.
@MainActor
@Observable
public final class PricingViewModel {
    public private(set) var source: PriceSource = .default
    public private(set) var collectionValue: Valuation?
    public private(set) var valueByRarity: [String?: Valuation] = [:]
    public private(set) var valueByLocation: [String?: Valuation] = [:]
    public private(set) var mostValuable: [ValuedCard] = []
    public private(set) var recordedSpend: Money?
    public private(set) var focusedRegion: PricingFocusRegion = .sourcePicker
    public private(set) var selectedIndex: Int?

    private let lookup: any PriceLookup
    private var items: [ValuationItem] = []
    private var names: [CardIdentifier: String] = [:]

    public init(lookup: any PriceLookup) {
        self.lookup = lookup
    }

    /// Loads a collection and values it.
    public func load(
        items: [ValuationItem],
        names: [CardIdentifier: String],
        recordedSpend: Money? = nil
    ) async {
        self.items = items
        self.names = names
        self.recordedSpend = recordedSpend
        await revalue()
    }

    /// Changing the source changes every figure, because the sources disagree
    /// by a median factor of 74 and blending them is not on offer.
    public func setSource(_ newSource: PriceSource) async {
        guard newSource != source else { return }
        source = newSource
        await revalue()
    }

    private func revalue() async {
        let cards = Set(items.map(\.card))
        guard !cards.isEmpty else {
            collectionValue = nil
            mostValuable = []
            return
        }

        let quoter = PriceQuoter(lookup: lookup, source: source)
        let quotes = (try? await quoter.quotes(for: cards, names: names)) ?? [:]

        collectionValue = Valuer.value(items, quotes: quotes, source: source)
        valueByRarity = Valuer.value(items, quotes: quotes, source: source) { $0.rarity }
        valueByLocation = Valuer.value(items, quotes: quotes, source: source) { $0.location }
        mostValuable = Valuer.ranked(items, quotes: quotes, source: source)

        selectedIndex = mostValuable.isEmpty
            ? nil
            : min(selectedIndex ?? 0, mostValuable.count - 1)
    }

    /// The difference between what the collection is worth and what was paid,
    /// or nothing when the two are not in the same currency.
    public var gainOverSpend: Money? {
        guard let value = collectionValue?.total, let spend = recordedSpend else { return nil }
        return value.subtracting(spend)
    }

    public var selectedCard: ValuedCard? {
        guard let selectedIndex, mostValuable.indices.contains(selectedIndex) else { return nil }
        return mostValuable[selectedIndex]
    }

    /// Every figure on screen, as sentences.
    public var sentences: [String] {
        var all: [String] = []
        if let collectionValue { all.append(collectionValue.sentence) }
        all += mostValuable.map(\.sentence)
        return all
    }

    // MARK: - Keyboard

    public func advanceFocus() {
        let all = PricingFocusRegion.allCases
        let next = (all.firstIndex(of: focusedRegion).map { $0 + 1 } ?? 0) % all.count
        focusedRegion = all[next]
    }

    public func retreatFocus() {
        let all = PricingFocusRegion.allCases
        let current = all.firstIndex(of: focusedRegion) ?? 0
        focusedRegion = all[(current - 1 + all.count) % all.count]
    }

    public func focusRegion(_ region: PricingFocusRegion) {
        focusedRegion = region
    }

    public func moveSelection(by offset: Int) {
        guard !mostValuable.isEmpty else { return }
        selectedIndex = max(0, min(mostValuable.count - 1, (selectedIndex ?? 0) + offset))
    }
}
