import Foundation
import Observation
import YGOCore

/// The regions keyboard focus moves through in the collection view.
public enum CollectionFocusRegion: Int, CaseIterable, Hashable, Sendable {
    case search
    case filters
    case ownedList
    case shortfall
}

/// Drives the collection view.
@MainActor
@Observable
public final class CollectionViewModel {
    public private(set) var items: [OwnedCardItem] = []
    public private(set) var totals: CollectionTotals?
    public private(set) var shortfall: [ShortfallEntry] = []
    public private(set) var focusedRegion: CollectionFocusRegion = .search
    public private(set) var selectedIndex: Int?
    /// Set when a removal was asked for and not yet confirmed. Copies are
    /// hand-entered and recoverable from nowhere, so the model asks rather
    /// than acts.
    public private(set) var pendingRemoval: CardIdentifier?

    public var query: String = ""

    private let reader: any CollectionReading

    public init(reader: any CollectionReading) {
        self.reader = reader
    }

    // MARK: - Loading

    public func reload() async {
        items = (try? await reader.ownedCardItems(matching: query)) ?? []
        totals = try? await reader.collectionTotals()
        selectedIndex = items.isEmpty ? nil : min(selectedIndex ?? 0, items.count - 1)
    }

    /// What a deck still needs, given what is owned.
    ///
    /// Counts cards rather than limit names: owning three `Harpie Lady 2` does
    /// not let anyone play a deck that lists `Harpie Lady 1`.
    public func computeShortfall(for deck: Deck, names: [CardIdentifier: String]) async {
        let owned = (try? await reader.ownedCopiesByCard()) ?? [:]
        shortfall = ShortfallCalculator.shortfall(deck: deck, names: names, owned: owned)
    }

    /// The report as sentences, which is what assistive technology reads.
    public var shortfallSentences: [String] { shortfall.map(\.sentence) }

    public var isShortfallSatisfied: Bool { shortfall.isEmpty }

    // MARK: - Removal

    public func requestRemoval(of card: CardIdentifier) {
        pendingRemoval = card
    }

    public func cancelRemoval() {
        pendingRemoval = nil
    }

    /// Hands back what the caller must confirm, rather than doing it: the
    /// model never removes hand-entered copies on its own.
    public func confirmedRemoval() -> CardIdentifier? {
        defer { pendingRemoval = nil }
        return pendingRemoval
    }

    // MARK: - Keyboard

    public func advanceFocus() {
        let all = CollectionFocusRegion.allCases
        let next = (all.firstIndex(of: focusedRegion).map { $0 + 1 } ?? 0) % all.count
        focusedRegion = all[next]
    }

    public func retreatFocus() {
        let all = CollectionFocusRegion.allCases
        let current = all.firstIndex(of: focusedRegion) ?? 0
        focusedRegion = all[(current - 1 + all.count) % all.count]
    }

    public func focusRegion(_ region: CollectionFocusRegion) {
        focusedRegion = region
    }

    /// Stops at the ends rather than wrapping, so the edge of the list is
    /// perceptible without sight.
    public func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = max(0, min(items.count - 1, (selectedIndex ?? 0) + offset))
    }

    public var selectedItem: OwnedCardItem? {
        guard let selectedIndex, items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }
}
