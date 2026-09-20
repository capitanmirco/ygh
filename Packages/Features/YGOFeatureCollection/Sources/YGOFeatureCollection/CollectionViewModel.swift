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
    /// Absent when the collection is only being read, which keeps a read-only
    /// screen from being able to change anything by accident.
    private let writer: (any CollectionWriting)?
    /// Finds cards to add. Absent means the screen cannot add any.
    private let catalogue: (any CardSearching)?

    /// What a search of the catalog turned up, for adding to the collection.
    public private(set) var candidates: [Card] = []
    public var catalogueQuery: String = ""

    public init(
        reader: any CollectionReading,
        writer: (any CollectionWriting)? = nil,
        catalogue: (any CardSearching)? = nil
    ) {
        self.reader = reader
        self.writer = writer
        self.catalogue = catalogue
    }

    public var canEdit: Bool { writer != nil }

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

    // MARK: - Editing

    /// Searches the catalog for a card to record.
    public func searchCatalogue() async {
        guard let catalogue, !catalogueQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            candidates = []
            return
        }
        let outcome = try? await catalogue.search(CardQuery(text: catalogueQuery, limit: 40))
        candidates = outcome?.cards ?? []
    }

    /// Records one copy of a card, against no printing when none was chosen.
    ///
    /// A copy with no printing is how the 552 cards the catalog lists no
    /// printing for get into a collection at all.
    public func recordCopy(
        of card: CardIdentifier,
        printID: Int64? = nil,
        condition: CardCondition = .nearMint,
        locationID: Int64? = nil
    ) async {
        guard let writer else { return }
        try? await writer.addCopy(cardID: card, printID: printID,
                                  condition: condition, locationID: locationID)
        await reload()
    }

    /// Sets how many copies of a card are held, removing the lot at zero.
    public func setCopies(
        _ quantity: Int,
        of card: CardIdentifier,
        printID: Int64? = nil,
        condition: CardCondition = .nearMint,
        locationID: Int64? = nil
    ) async {
        guard let writer else { return }
        try? await writer.setQuantity(quantity, cardID: card, printID: printID,
                                      condition: condition, locationID: locationID)
        await reload()
    }

    /// Removes every lot of a card, once the removal has been confirmed.
    ///
    /// Copies are hand-entered and recoverable from nowhere, so this runs only
    /// after `confirmedRemoval` has handed back what the user agreed to.
    public func removeConfirmedCard() async {
        guard let writer, let card = confirmedRemoval() else { return }
        let lots = (try? await writer.entries(forCard: card)) ?? []
        for lot in lots {
            try? await writer.deleteEntry(lot.id, confirmed: true)
        }
        await reload()
    }

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
