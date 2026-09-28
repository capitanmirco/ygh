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

/// Why a chosen deck produced no report.
enum ShortfallReadFailure: Error {
    /// The library no longer holds the deck.
    case deckMissing
}

/// Drives the collection view.
@MainActor
@Observable
public final class CollectionViewModel {
    public private(set) var items: [OwnedCardItem] = []
    public private(set) var totals: CollectionTotals?
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

    /// The decks the shortfall can be asked about. Absent means the panel has
    /// no subject to offer, which is how the screen was built before it had one.
    private let library: (any DeckRepository)?
    /// Names for the cards a deck needs, in the collection's language.
    private let naming: (any CardNaming)?

    /// Every stored deck, in the order the library lists them.
    public private(set) var decks: [Deck] = []
    /// The deck the report is about, once one has been read.
    public private(set) var chosenShortfallDeck: Deck?
    /// Kept with the chosen deck, so a write on this screen recomputes the
    /// report without reading the deck and its names again.
    private var chosenNames: [CardIdentifier: String] = [:]
    /// What the panel says. Everything else about the shortfall is read from it.
    public private(set) var shortfallReport: ShortfallReport = .chooseADeck
    /// Bumped by every computation. Two choices in quick succession each read
    /// storage, and the one that answers last is not necessarily the one the
    /// user made last.
    private var shortfallGeneration = 0

    public init(
        reader: any CollectionReading,
        writer: (any CollectionWriting)? = nil,
        catalogue: (any CardSearching)? = nil,
        library: (any DeckRepository)? = nil,
        naming: (any CardNaming)? = nil
    ) {
        self.reader = reader
        self.writer = writer
        self.catalogue = catalogue
        self.library = library
        self.naming = naming
    }

    public var canEdit: Bool { writer != nil }

    public var canChooseShortfallDeck: Bool { library != nil && naming != nil }

    // MARK: - Loading

    /// Re-reads the collection, and the report with it: every write on this
    /// screen ends here, which is what keeps the list of missing cards in step
    /// with the cards being recorded.
    public func reload() async {
        items = (try? await reader.ownedCardItems(matching: query)) ?? []
        totals = try? await reader.collectionTotals()
        selectedIndex = items.isEmpty ? nil : min(selectedIndex ?? 0, items.count - 1)

        if let deck = chosenShortfallDeck {
            await computeShortfall(for: deck, names: chosenNames)
        }
    }

    // MARK: - What a deck is missing

    /// Reads the library and starts the report on `deckID` when the library
    /// holds it — the deck already chosen elsewhere in the window.
    public func startShortfall(on deckID: Int64?) async {
        guard let library else { return }
        do {
            decks = try await library.allDecks()
        } catch {
            decks = []
            chosenShortfallDeck = nil
            shortfallReport = .unavailable(deckName: nil)
            return
        }

        if let deckID, decks.contains(where: { $0.id == deckID }) {
            await chooseShortfallDeck(deckID)
        } else {
            chosenShortfallDeck = nil
            shortfallReport = decks.isEmpty ? .noDecks : .chooseADeck
        }
    }

    /// Makes a deck the report's subject: reads it and the names of its cards,
    /// then computes what it needs.
    public func chooseShortfallDeck(_ deckID: Int64) async {
        guard let library, let naming else { return }
        shortfallGeneration += 1
        let mine = shortfallGeneration
        let knownName = decks.first { $0.id == deckID }?.name

        do {
            guard let deck = try await library.deck(with: deckID) else {
                throw ShortfallReadFailure.deckMissing
            }
            let names = try await naming.cardNames(for: Set(deck.slots.map(\.card)))
            guard mine == shortfallGeneration else { return }
            await computeShortfall(for: deck, names: names)
        } catch {
            guard mine == shortfallGeneration else { return }
            chosenShortfallDeck = nil
            shortfallReport = .unavailable(deckName: knownName)
        }
    }

    /// What a deck still needs, given what is owned.
    ///
    /// Counts cards rather than limit names: owning three `Harpie Lady 2` does
    /// not let anyone play a deck that lists `Harpie Lady 1`.
    ///
    /// A failed read of the owned copies is reported as such. It used to be
    /// read as a collection that owns nothing, which lists every card of the
    /// deck as missing — an answer, and a wrong one.
    public func computeShortfall(for deck: Deck, names: [CardIdentifier: String]) async {
        shortfallGeneration += 1
        let mine = shortfallGeneration
        chosenShortfallDeck = deck
        chosenNames = names

        do {
            let owned = try await reader.ownedCopiesByCard()
            guard mine == shortfallGeneration else { return }
            let entries = ShortfallCalculator.shortfall(deck: deck, names: names, owned: owned)
            shortfallReport = entries.isEmpty
                ? .satisfied(deckName: deck.name)
                : .missing(deckName: deck.name, entries: entries)
        } catch {
            guard mine == shortfallGeneration else { return }
            shortfallReport = .unavailable(deckName: deck.name)
        }
    }

    /// The cards still needed, read from the report.
    public var shortfall: [ShortfallEntry] { shortfallReport.entries }

    /// The report as sentences, which is what assistive technology reads.
    public var shortfallSentences: [String] { shortfall.map(\.sentence) }

    /// True only for a deck that was read and needs nothing. An empty list is
    /// not enough: no deck chosen and a failed read are empty too.
    public var isShortfallSatisfied: Bool {
        if case .satisfied = shortfallReport { true } else { false }
    }

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
