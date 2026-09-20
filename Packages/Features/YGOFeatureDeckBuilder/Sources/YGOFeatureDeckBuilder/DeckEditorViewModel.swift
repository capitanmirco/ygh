import Foundation
import Observation
import YGOCore
import YGOValidation

/// The regions keyboard focus moves through in the deck editor.
public enum DeckEditorFocusRegion: Int, CaseIterable, Hashable, Sendable {
    case sections
    case cardList
    case violationReport
}

/// One row in a deck's card list, already resolved into what is shown.
public struct DeckEntryItem: Identifiable, Hashable, Sendable {
    public let id: ArtworkIdentifier
    public let card: CardIdentifier
    public let title: String
    public let section: DeckSection
    public let quantity: Int
    public let banStatus: BanStatus

    public var accessibilityLabel: String {
        var parts = ["\(quantity)× \(title)", section.italianName]
        if banStatus != .unlimited { parts.append(banStatus.italianName) }
        return parts.joined(separator: ", ")
    }
}

/// Drives the deck editor.
///
/// Every edit re-evaluates the whole deck: at ninety distinct cards that is
/// cheaper than the bookkeeping an incremental cache would need, and it cannot
/// drift out of step with the deck the way a cache can.
@MainActor
@Observable
public final class DeckEditorViewModel {
    public private(set) var deck: Deck?
    public private(set) var items: [DeckEntryItem] = []
    public private(set) var legality: DeckLegality?
    public private(set) var focusedRegion: DeckEditorFocusRegion = .sections
    public private(set) var selectedIndex: Int?
    public private(set) var language: CardLanguage

    /// Set when an action was refused for want of a confirmation, so the
    /// interface can ask rather than the model deciding on the user's behalf.
    public private(set) var pendingDeletion: Int64?

    private let repository: any DeckBuilding
    private let validator: any DeckValidating
    /// Finds cards to add. Absent means the editor can only remove.
    private let catalogue: (any CardSearching)?
    private var index = DeckCardIndex(entries: [])

    /// What a search of the catalog turned up, ready to be added.
    public private(set) var candidates: [Card] = []
    public var catalogueQuery: String = ""

    public init(
        repository: any DeckBuilding,
        validator: any DeckValidating,
        catalogue: (any CardSearching)? = nil,
        language: CardLanguage = .italian
    ) {
        self.repository = repository
        self.validator = validator
        self.catalogue = catalogue
        self.language = language
    }

    public var canAddCards: Bool { catalogue != nil }

    // MARK: - Loading

    public func load(deckID: Int64) async {
        guard let loaded = try? await repository.deck(with: deckID) else { return }
        await refresh(with: loaded)
    }

    private func refresh(with deck: Deck) async {
        self.deck = deck
        index = (try? await repository.cardIndex(for: deck)) ?? DeckCardIndex(entries: [])
        rebuild()
    }

    /// Re-reads the deck and re-evaluates it. Called after every edit.
    private func rebuild() {
        guard let deck else {
            items = []
            legality = nil
            return
        }

        items = deck.slots
            .sorted { lhs, rhs in
                lhs.section.rawValue == rhs.section.rawValue
                    ? lhs.artwork.rawValue < rhs.artwork.rawValue
                    : lhs.section.rawValue < rhs.section.rawValue
            }
            .map { slot in
                let entry = index[slot.card]
                return DeckEntryItem(
                    id: slot.artwork,
                    card: slot.card,
                    title: entry?.name ?? "Carta \(slot.card.rawValue)",
                    section: slot.section,
                    quantity: slot.quantity,
                    banStatus: entry?.banStatus ?? .unlimited)
            }

        legality = validator.legality(of: deck, using: index)

        if items.isEmpty { selectedIndex = nil }
        else { selectedIndex = min(selectedIndex ?? 0, items.count - 1) }
    }

    /// Re-evaluates without touching storage, for measuring the edit budget.
    public func reevaluate() {
        rebuild()
    }

    // MARK: - Editing

    /// Searches the catalog for a card to add.
    public func searchCatalogue() async {
        guard let catalogue, !catalogueQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            candidates = []
            return
        }
        let outcome = try? await catalogue.search(CardQuery(text: catalogueQuery, limit: 40))
        candidates = outcome?.cards ?? []
    }

    /// Adds a card, placing it by its frame unless a section was chosen.
    ///
    /// The placement rule is the validator's own, so a card the editor puts
    /// somewhere is never then reported for being there.
    public func add(_ card: Card, to section: DeckSection? = nil) async {
        guard let deck, let artwork = card.artworks.first else { return }
        let target = section ?? DeckValidator.defaultSection(for: card.frame)
        try? await repository.addCard(artwork: artwork, section: target, to: deck.id)
        await load(deckID: deck.id)
    }

    public func add(artwork: ArtworkIdentifier, to section: DeckSection) async {
        guard let deck else { return }
        try? await repository.addCard(artwork: artwork, section: section, to: deck.id)
        await load(deckID: deck.id)
    }

    public func remove(artwork: ArtworkIdentifier, from section: DeckSection) async {
        guard let deck else { return }
        try? await repository.removeCard(artwork: artwork, section: section, from: deck.id)
        await load(deckID: deck.id)
    }

    /// Asks rather than acts. A deck is irreplaceable, so the confirmation is
    /// a separate step the interface has to take deliberately.
    public func requestDeletion() {
        pendingDeletion = deck?.id
    }

    public func cancelDeletion() {
        pendingDeletion = nil
    }

    @discardableResult
    public func confirmDeletion() async -> Bool {
        guard let id = pendingDeletion else { return false }
        do {
            try await repository.delete(id, confirmed: true)
            pendingDeletion = nil
            deck = nil
            rebuild()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Keyboard

    public func advanceFocus() {
        let all = DeckEditorFocusRegion.allCases
        let next = (all.firstIndex(of: focusedRegion).map { $0 + 1 } ?? 0) % all.count
        focusedRegion = all[next]
    }

    public func retreatFocus() {
        let all = DeckEditorFocusRegion.allCases
        let current = all.firstIndex(of: focusedRegion) ?? 0
        focusedRegion = all[(current - 1 + all.count) % all.count]
    }

    public func focusRegion(_ region: DeckEditorFocusRegion) {
        focusedRegion = region
    }

    /// Stops at the ends rather than wrapping, so the edge of the list is
    /// perceptible without sight.
    public func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = max(0, min(items.count - 1, (selectedIndex ?? 0) + offset))
    }

    public var selectedItem: DeckEntryItem? {
        guard let selectedIndex, items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    /// The report as sentences, which is what assistive technology reads.
    public var violationSentences: [String] {
        (legality?.violations ?? []).map(\.sentence)
    }
}
