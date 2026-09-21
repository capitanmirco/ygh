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

    /// How many cards the current query matches, which is not how many are
    /// shown: the grid holds a batch at a time.
    public private(set) var matchCount: Int = 0
    /// How many cards a release-year range hid because the catalog holds no
    /// date for them. 523 cards are in that position, and hiding them without
    /// saying so would make a year range look like a smaller catalog.
    public private(set) var excludedUndated: Int = 0
    /// How many entries on the chosen list name a card the catalog cannot
    /// match. Reported rather than shown as a shorter list.
    public private(set) var unmatchedOnList: Int = 0

    /// What is narrowing the results right now, in sentences.
    public var appliedFilters: [String] { filters.descriptions }

    /// Whether anything is narrowing the results at all.
    public var hasFilters: Bool { !filters.isEmpty }

    /// Puts the catalog back the way it opened.
    public func clearFilters() async {
        guard hasFilters else { return }
        filters = CardFilters()
        await reload()
    }

    /// The lists available for a format, oldest first. Empty when none has
    /// been downloaded, which the interface states rather than showing an
    /// empty chooser.
    public func availableLists(for format: BanlistFormat) -> [BanlistRevision] {
        (try? publishedLists?.revisions(for: format)) ?? []
    }
    public private(set) var state: State = .idle
    public private(set) var language: CardLanguage
    public private(set) var focusedRegion: BrowserFocusRegion = .searchField
    /// Index of the highlighted tile, or `nil` when the grid holds no selection.
    public private(set) var selectedIndex: Int?

    public var queryText: String = ""
    public var filters = CardFilters()

    /// One batch. Showing all 14,566 cards at once would put 417 MB of
    /// thumbnails within reach of the layout to answer a question a stated
    /// total answers better.
    public static let batchSize = 200

    private let repository: any CardSearching
    private let counter: any CardSearchCounting
    private let artwork: any ArtworkProviding
    private let banStatusProvider: any CardRepository
    /// Reads the stored Forbidden & Limited Lists. Absent means the browser
    /// can show today's statuses but cannot offer a historical list.
    private let publishedLists: (any BanlistHistoryReading)?
    /// Bumped by every load. A result carrying an older number was asked for
    /// by text the user has since moved past, so it is discarded rather than
    /// shown.
    private var generation = 0
    /// The cards behind the current results, kept so that a language change is
    /// a re-presentation rather than another query.
    private var loadedCards: [Card] = []
    private var loadedArtwork: [CardIdentifier: ArtworkPresentation] = [:]
    private var loadedBanStatuses: [CardIdentifier: BanStatus] = [:]

    public init(
        repository: any CardSearching,
        counter: any CardSearchCounting,
        artwork: any ArtworkProviding,
        banStatusProvider: any CardRepository,
        publishedLists: (any BanlistHistoryReading)? = nil,
        language: CardLanguage = .italian
    ) {
        self.repository = repository
        self.counter = counter
        self.artwork = artwork
        self.banStatusProvider = banStatusProvider
        self.publishedLists = publishedLists
        self.language = language
    }

    // MARK: - Searching

    /// The first load, issued when the browser appears.
    ///
    /// The catalog is there to be looked through, not only queried, and an
    /// unnarrowed query costs 3.9 ms. Waiting for the user to type would be
    /// withholding something already paid for.
    public func start() async {
        await reload()
    }

    /// Called on every change to the query text. No debounce: the query is
    /// cheap, and a timer would tax every keystroke to solve a problem the
    /// measurements do not show.
    public func queryChanged() async {
        await reload()
    }

    public func filtersChanged() async {
        await reload()
    }

    /// Kept so that existing callers submitting with Enter still work; it is
    /// the same load the text change already started.
    public func search() async {
        await reload()
    }

    private func reload() async {
        generation += 1
        let mine = generation
        state = .searching

        let query = CardQuery(
            text: queryText, filters: filters, limit: Self.batchSize, offset: 0)

        do {
            let outcome = try await repository.search(query)
            let count = try await counter.matchCount(for: query)
            guard mine == generation else { return }

            loadedCards = outcome.cards
            matchCount = count
            excludedUndated = try await undatedCount(for: query)
            await loadPresentationData(for: loadedCards)
            guard mine == generation else { return }
            rebuildItems()
        } catch {
            // A local query failing is not a network problem; there is nothing
            // to retry, so the browser reports nothing found rather than
            // pretending to be busy for ever.
            guard mine == generation else { return }
            loadedCards = []
            matchCount = 0
            excludedUndated = 0
            state = .noMatches
        }
    }

    private func loadPresentationData(for cards: [Card]) async {
        loadedArtwork = [:]
        loadedBanStatuses = [:]
        let format = filters.format ?? .tcg

        // With a list chosen, the status shown is the one that list gave, not
        // today's. The two sources never mix.
        var historical: [CardIdentifier: BanStatus] = [:]
        if let selection = filters.publishedList, let publishedLists {
            let entries = (try? publishedLists.list(
                selection.format, effectiveDate: selection.effectiveDate)) ?? []
            for entry in entries {
                if let cardID = entry.cardID {
                    historical[CardIdentifier(cardID)] = entry.status.banStatus
                }
            }
            unmatchedOnList = entries.filter { $0.cardID == nil }.count
        } else {
            unmatchedOnList = 0
        }

        for card in cards {
            if let first = card.artworks.first {
                loadedArtwork[card.id] = await artworkPresentation(for: first, card: card)
            }
            if let onList = historical[card.id] {
                loadedBanStatuses[card.id] = onList
            } else {
                loadedBanStatuses[card.id] =
                    (try? await banStatusProvider.banStatus(for: card.id, in: format)) ?? .unlimited
            }
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
                subtitle: Vocabulary.cardKind(card.humanReadableType),
                isUntranslated: text.isFallbackToEnglish,
                artwork: presentation,
                banStatus: loadedBanStatuses[card.id] ?? .unlimited,
                frame: card.frame)
        }

        state = .results(items)
        if selectedIndex == nil { selectedIndex = 0 }
        selectedIndex = selectedIndex.map { min($0, items.count - 1) }
    }

    /// The difference a year range made, counted rather than estimated: the
    /// same query with the year clause dropped.
    private func undatedCount(for query: CardQuery) async throws -> Int {
        guard query.filters.releaseYears != nil else { return 0 }
        var withoutYears = query
        withoutYears.filters.releaseYears = nil
        let all = try await counter.matchCount(for: withoutYears)
        return max(0, all - matchCount)
    }

    // MARK: - Paging

    /// How many of the matching cards the grid currently holds.
    public var shownCount: Int { loadedCards.count }

    /// Whether a further batch exists. False at the end, so the interface can
    /// stop offering an advance that would return nothing.
    public var canShowMore: Bool { loadedCards.count < matchCount }

    /// Adds the next batch to the ones already shown.
    ///
    /// The batch is tagged with the load that asked for it: if the query
    /// changed while it was in flight, it belongs to a different result and is
    /// discarded rather than appended to this one.
    public func showMore() async {
        guard canShowMore else { return }
        let mine = generation

        let query = CardQuery(
            text: queryText, filters: filters,
            limit: Self.batchSize, offset: loadedCards.count)

        do {
            let outcome = try await repository.search(query)
            guard mine == generation else { return }

            // Upstream paging is by offset, so a card already held would be a
            // duplicate row rather than a new one.
            let held = Set(loadedCards.map(\.id))
            let fresh = outcome.cards.filter { !held.contains($0.id) }
            guard !fresh.isEmpty else { return }

            loadedCards += fresh
            await loadPresentationData(for: loadedCards)
            guard mine == generation else { return }
            rebuildItems()
        } catch {
            // The batch is lost; what is already shown is not.
        }
    }

    /// The card behind the highlighted tile, which is what the detail panel
    /// opens on. The grid holds presentation; this is the card itself.
    public var selectedCard: Card? {
        guard let selectedIndex, loadedCards.indices.contains(selectedIndex) else { return nil }
        return loadedCards[selectedIndex]
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
