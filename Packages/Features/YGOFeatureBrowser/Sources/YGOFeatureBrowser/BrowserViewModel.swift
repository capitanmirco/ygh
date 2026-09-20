import Foundation
import Observation
import YGOCore

/// Drives the card browser.
///
/// It depends only on the protocols declared in `YGOCore`, so it compiles and
/// is tested without SQLite, without a network, and without a view.
@MainActor
@Observable
public final class BrowserViewModel {
    /// What the browser is showing. `noMatches` is a settled answer and is a
    /// separate case from `searching`, so the interface never shows an empty
    /// grid that might still be loading.
    public enum State: Hashable, Sendable {
        case idle
        case searching
        case results([CardGridItem])
        case noMatches
    }

    public private(set) var state: State = .idle
    public private(set) var language: CardLanguage
    public private(set) var focusedRegion: BrowserFocusRegion = .searchField
    /// Index of the highlighted tile, or `nil` when the grid holds no selection.
    public private(set) var selectedIndex: Int?

    public var queryText: String = ""
    public var filters = CardFilters()

    private let repository: any CardSearching
    private let artwork: any ArtworkProviding
    private let banStatusProvider: any CardRepository
    /// The cards behind the current results, kept so that a language change is
    /// a re-presentation rather than another query.
    private var loadedCards: [Card] = []
    private var loadedArtwork: [CardIdentifier: ArtworkPresentation] = [:]
    private var loadedBanStatuses: [CardIdentifier: BanStatus] = [:]

    public init(
        repository: any CardSearching,
        artwork: any ArtworkProviding,
        banStatusProvider: any CardRepository,
        language: CardLanguage = .italian
    ) {
        self.repository = repository
        self.artwork = artwork
        self.banStatusProvider = banStatusProvider
        self.language = language
    }

    // MARK: - Searching

    public func search() async {
        state = .searching
        let query = CardQuery(text: queryText, filters: filters, limit: 200)

        do {
            let outcome = try await repository.search(query)
            loadedCards = outcome.cards
            await loadPresentationData(for: loadedCards)
            rebuildItems()
        } catch {
            // A local query failing is not a network problem; there is nothing
            // to retry, so the browser reports nothing found rather than
            // pretending to be busy for ever.
            loadedCards = []
            state = .noMatches
        }
    }

    private func loadPresentationData(for cards: [Card]) async {
        loadedArtwork = [:]
        loadedBanStatuses = [:]
        let format = filters.format ?? .tcg

        for card in cards {
            if let first = card.artworks.first {
                loadedArtwork[card.id] = await artworkPresentation(for: first, card: card)
            }
            loadedBanStatuses[card.id] =
                (try? await banStatusProvider.banStatus(for: card.id, in: format)) ?? .unlimited
        }
    }

    private func artworkPresentation(
        for identifier: ArtworkIdentifier,
        card: Card
    ) async -> ArtworkPresentation {
        let name = card.text(in: language).name
        guard let path = await artwork.storedArtworkPath(for: identifier, variant: .thumbnail)
        else { return .placeholder(cardName: name) }
        return .stored(path: path)
    }

    // MARK: - Language

    /// Re-presents the cards already held in the new language.
    ///
    /// Both languages are stored on every card, so this costs no query and
    /// works with no network at all.
    public func setLanguage(_ newLanguage: CardLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        rebuildItems()
    }

    private func rebuildItems() {
        guard !loadedCards.isEmpty else {
            state = .noMatches
            selectedIndex = nil
            return
        }

        let items = loadedCards.map { card -> CardGridItem in
            let text = card.text(in: language)
            let placeholder = ArtworkPresentation.placeholder(cardName: text.name)
            var presentation = loadedArtwork[card.id] ?? placeholder
            // A placeholder carries the name, so it has to follow the language.
            if case .placeholder = presentation { presentation = placeholder }

            return CardGridItem(
                id: card.id,
                title: text.name,
                subtitle: card.humanReadableType,
                isUntranslated: text.isFallbackToEnglish,
                artwork: presentation,
                banStatus: loadedBanStatuses[card.id] ?? .unlimited)
        }

        state = .results(items)
        if selectedIndex == nil { selectedIndex = 0 }
        selectedIndex = selectedIndex.map { min($0, items.count - 1) }
    }

    public var items: [CardGridItem] {
        if case .results(let items) = state { return items }
        return []
    }

    // MARK: - Keyboard

    /// Records focus landing somewhere directly, such as a mouse click, so the
    /// model and the view never disagree about where the keyboard is.
    public func focusRegion(_ region: BrowserFocusRegion) {
        focusedRegion = region
    }

    /// Moves focus to the next region, wrapping at the end so no region can be
    /// stranded beyond reach of the keyboard.
    public func advanceFocus() {
        let all = BrowserFocusRegion.allCases
        let next = (all.firstIndex(of: focusedRegion).map { $0 + 1 } ?? 0) % all.count
        focusedRegion = all[next]
    }

    public func retreatFocus() {
        let all = BrowserFocusRegion.allCases
        let current = all.firstIndex(of: focusedRegion) ?? 0
        focusedRegion = all[(current - 1 + all.count) % all.count]
    }

    /// Moves the grid selection. Stops at the ends rather than wrapping, which
    /// would make it impossible to tell the edge of the grid by feel.
    public func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        let current = selectedIndex ?? 0
        selectedIndex = max(0, min(items.count - 1, current + offset))
    }

    public var selectedItem: CardGridItem? {
        guard let selectedIndex, items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }
}
