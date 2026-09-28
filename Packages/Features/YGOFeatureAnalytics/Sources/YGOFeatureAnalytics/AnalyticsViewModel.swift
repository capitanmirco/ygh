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

    /// Nil means the deck's own format. Set means "read it as if it were
    /// played here", which changes every figure without changing the deck.
    public private(set) var assumedFormat: CardFormat?

    private var index = DeckCardIndex(entries: [])

    /// The library, so the screen can say which deck it is about rather than
    /// describing whichever one the window last selected.
    private let library: (any DeckRepository)?

    /// Every stored deck, in the order the library lists them.
    public private(set) var decks: [Deck] = []
    /// True once the library has been read and held nothing. An empty chooser
    /// beside empty figures leaves the reader looking for a deck they never
    /// made.
    public private(set) var libraryIsEmpty = false

    /// Judges the chosen deck against a published list, and reads the lists
    /// there are. Absent means the screen shows figures and no verdict.
    private let judging: (any DeckListJudging)?
    private let lists: (any BanlistHistoryReading)?

    /// Every stored list, newest first inside its format.
    public private(set) var availableLists: [BanlistRevision] = []
    public private(set) var chosenList: BanlistRevision?
    /// What that list makes of the chosen deck. One line of it is shown here;
    /// the per-card panel belongs to the editor, where a card can be changed.
    public private(set) var verdict: DeckListVerdict?
    /// True when the deck's format is played under no published list. An
    /// answer, not a gap.
    public private(set) var formatHasNoList = false

    public var canChooseDeck: Bool { library != nil }
    public var canMeasure: Bool { judging != nil && lists != nil }

    public init(
        library: (any DeckRepository)? = nil,
        judging: (any DeckListJudging)? = nil,
        lists: (any BanlistHistoryReading)? = nil
    ) {
        self.library = library
        self.judging = judging
        self.lists = lists
    }

    // MARK: - Measured against a list

    public func loadLists() async {
        guard let lists else { return }
        var stored: [BanlistRevision] = []
        for format in BanlistFormat.allCases {
            stored += (try? lists.revisions(for: format)) ?? []
        }
        availableLists = stored.sorted { left, right in
            if left.format == right.format {
                return left.effectiveDate > right.effectiveDate
            }
            return left.format.rawValue < right.format.rawValue
        }
    }

    /// Measures the chosen deck against a list. Reads only: the verdict is
    /// `deck-legality`'s, and nothing here can change a deck.
    public func measure(against list: BanlistRevision) async {
        guard let judging, let deck else { return }
        chosenList = list
        formatHasNoList = false
        let cards = (try? await judging.judge(
            deck.id, against: list.format, effectiveDate: list.effectiveDate)) ?? []
        verdict = DeckListVerdict(list: list, cards: cards)
    }

    /// Measures against whatever the deck's own format is played under, or
    /// reports that nothing is.
    public func measureAgainstImpliedList() async {
        guard canMeasure, let deck else { return }
        if availableLists.isEmpty { await loadLists() }

        guard let list = BanlistRevision.implied(for: deck.format, in: availableLists) else {
            chosenList = nil
            verdict = nil
            formatHasNoList = true
            return
        }
        await measure(against: list)
    }

    // MARK: - Which deck

    public func loadDecks() async {
        guard let library else { return }
        decks = (try? await library.allDecks()) ?? []
        libraryIsEmpty = decks.isEmpty
    }

    /// Reads a deck and its index, and makes the figures about it.
    public func choose(deckID: Int64) async {
        guard let library else { return }
        guard let chosen = try? await library.deck(with: deckID),
              let index = try? await library.cardIndex(for: chosen) else { return }

        // A hand dealt from the deck before is not evidence about this one.
        dealtHand = []
        selectedIndex = nil
        load(deck: chosen, index: index)

        // A verdict about the previous deck is not about this one.
        verdict = nil
        formatHasNoList = false
        if canMeasure {
            if let list = chosenList {
                await measure(against: list)
            } else {
                await measureAgainstImpliedList()
            }
        }
    }

    /// The deck the screen was asked to open on and could not read.
    ///
    /// Nil when it was asked for none: opening with nothing selected is a
    /// request to choose, not a failure. The composition root treated the two
    /// alike, so opening the statistics before touching the deck list reported
    /// a deck that "was not read" and hid the chooser that would have fixed it.
    public private(set) var unreadableStartingDeck: Int64?

    /// Opens on a deck chosen elsewhere in the application.
    public func start(on deckID: Int64?) async {
        await loadDecks()
        unreadableStartingDeck = nil
        guard let deckID else { return }
        await choose(deckID: deckID)
        if deck?.id != deckID { unreadableStartingDeck = deckID }
    }

    /// What the screen says in place of figures when it has no deck, or nil
    /// when it has one.
    public var noDeckMessage: String? {
        guard deck == nil else { return nil }
        return libraryIsEmpty
            ? "Nessun mazzo salvato: non c'è niente da analizzare."
            : "Scegli un mazzo dal menu qui sopra per vederne le statistiche."
    }

    // MARK: - Loading

    public func load(deck: Deck, index: DeckCardIndex) {
        self.deck = deck
        self.index = index
        recompute()
    }

    // MARK: - Reading it in another format

    /// The deck as the figures read it: the chosen deck with the assumed
    /// format substituted.
    ///
    /// The format reaches the arithmetic by travelling inside the deck value —
    /// `OpeningHand` takes it from there — so assuming another one needs no
    /// change to `YGOAnalytics` at all. This is a value, and nothing writes it
    /// back: the stored deck is read, never written.
    private var readingDeck: Deck? {
        guard var reading = deck else { return nil }
        if let assumedFormat { reading.format = assumedFormat }
        return reading
    }

    /// The format every figure on screen was computed under.
    public var readingFormat: CardFormat? { assumedFormat ?? deck?.format }

    /// True when the figures are not about the deck's own format, which the
    /// screen has to say out loud: a figure that does not state its assumption
    /// is a figure nobody can check.
    public var isReadingAnotherFormat: Bool {
        guard let assumedFormat, let deck else { return false }
        return assumedFormat != deck.format
    }

    /// Reads the deck as though it were played in another format, or, with
    /// nil, as the deck's own again.
    public func assume(format: CardFormat?) {
        guard format != assumedFormat else { return }
        assumedFormat = format
        // A hand dealt under the previous rules would be six cards under a
        // five-card rule, and it would look like evidence.
        dealtHand = []
        recompute()
    }

    /// Going second is a different question, so every figure is recomputed
    /// rather than adjusted.
    public func setPlayingFirst(_ value: Bool) {
        guard value != playingFirst else { return }
        playingFirst = value
        // The same rule as every other choice: a hand dealt under the previous
        // one is not evidence about this one.
        dealtHand = []
        recompute()
    }

    private func recompute() {
        guard let deck = readingDeck else {
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
        guard let deck = readingDeck, let selected = selectedOdds else {
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
    public var hand: OpeningHand? { odds.first?.hand ?? readingDeck.map {
        OpeningHand(format: $0.format, playingFirst: playingFirst)
    } }

    // MARK: - Dealing

    /// Deals a hand so a percentage becomes something to look at.
    public func dealHand(seed: UInt64 = UInt64.random(in: 0..<UInt64.max)) {
        guard let deck = readingDeck else { return }
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
