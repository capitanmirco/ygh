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
    /// What the card is. A deck list is where frame colour earns its keep:
    /// seven extra-deck frames sorted into one section, told apart without
    /// reading a word.
    public let frame: CardFrame

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
    /// What the last edit failed with, or `nil` when it succeeded.
    ///
    /// The editor used to call the repository with `try?`, so an edit that
    /// threw left the deck unchanged and said nothing - indistinguishable from
    /// one that succeeded and did nothing.
    public private(set) var lastFailure: String?

    private let repository: any DeckBuilding
    private let validator: any DeckValidating
    /// Finds cards to add. Absent means the editor can only remove.
    private let catalogue: (any CardSearching)?
    private var index = DeckCardIndex(entries: [])

    /// What a search of the catalog turned up, ready to be added.
    public private(set) var candidates: [Card] = []
    public var catalogueQuery: String = ""
    /// One page of candidates. The panel is narrow; the deck is the point.
    public static let candidateLimit = 40
    private var candidateGeneration = 0
    /// Undo and redo for as long as this deck is open.
    private(set) var history = DeckEditHistory()

    /// Rearranging: counts and moves. Absent means the editor can add and
    /// remove but not rearrange.
    private let editing: (any DeckEditing)?
    /// Resolves a deck entry's identifier into the card the preview panel
    /// needs. Absent means entries do not preview; candidates still do,
    /// because they are already cards.
    private let reader: (any CardRepository)?
    /// Bumped by every preview. Walking a deck with the arrow keys issues a
    /// read per row, and one that answers after the selection moved on
    /// belongs to a card the user is no longer looking at.
    private var previewGeneration = 0

    /// Saved states of this deck. Absent means the editor cannot offer a
    /// history, the same way `editing` absent means it cannot rearrange.
    ///
    /// Stored under a different name from the undo stack above, which is also
    /// called history and is a different thing: that one lasts as long as the
    /// editor is open, this one outlives the application.
    private let versioning: (any DeckHistorying)?

    /// The deck's format and tags. Absent means the editor shows the labels
    /// but cannot change them, the same shape as `editing` and `history`.
    private let labelling: (any DeckLabelling)?

    /// Judges the deck against a published list. Absent means the editor can
    /// show a deck but not ask what a list makes of it.
    private let judging: (any DeckListJudging)?
    /// The stored lists, for choosing among them.
    private let lists: (any BanlistHistoryReading)?

    public init(
        repository: any DeckBuilding,
        validator: any DeckValidating,
        catalogue: (any CardSearching)? = nil,
        editing: (any DeckEditing)? = nil,
        reader: (any CardRepository)? = nil,
        history: (any DeckHistorying)? = nil,
        labels: (any DeckLabelling)? = nil,
        judging: (any DeckListJudging)? = nil,
        lists: (any BanlistHistoryReading)? = nil,
        language: CardLanguage = .italian
    ) {
        self.repository = repository
        self.validator = validator
        self.catalogue = catalogue
        self.editing = editing
        self.reader = reader
        self.versioning = history
        self.labelling = labels
        self.judging = judging
        self.lists = lists
        self.language = language
    }

    public var canAddCards: Bool { catalogue != nil }
    public var canRearrange: Bool { editing != nil }

    // MARK: - Loading

    public func load(deckID: Int64) async {
        // Opening a different deck discards the undo history of the one
        // before it, so a ⌘Z cannot reach the wrong deck.
        if deck?.id != deckID { history.clear() }
        guard let loaded = try? await repository.deck(with: deckID) else { return }
        await refresh(with: loaded)
        // The editor opens with something to add. Waiting for the user to type
        // withholds a query that costs a few milliseconds.
        await searchCatalogue()
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
            .map { slot in
                let entry = index[slot.card]
                return DeckEntryItem(
                    id: slot.artwork,
                    card: slot.card,
                    title: entry?.name ?? "Carta \(slot.card.rawValue)",
                    section: slot.section,
                    quantity: slot.quantity,
                    banStatus: entry?.banStatus ?? .unlimited,
                    frame: entry?.frame ?? .token)
            }
            .sorted(by: Self.precedes)

        legality = validator.legality(of: deck, using: index)

        if items.isEmpty { selectedIndex = nil }
        else { selectedIndex = min(selectedIndex ?? 0, items.count - 1) }
    }

    /// Sections in the order they are drawn, then monsters, spells and traps,
    /// then name.
    ///
    /// Sorts the built items rather than the slots: a slot carries an artwork
    /// and a count, and neither the kind nor the name a reader sorts by.
    ///
    /// The section comes first even though the list draws each section
    /// separately, because keyboard selection walks `items` in this order and
    /// would otherwise jump between sections in a different order than the
    /// eye does.
    static func precedes(_ lhs: DeckEntryItem, _ rhs: DeckEntryItem) -> Bool {
        if lhs.section != rhs.section {
            return lhs.section.listingOrder < rhs.section.listingOrder
        }

        let left = lhs.frame.cardType.listingOrder
        let right = rhs.frame.cardType.listingOrder
        if left != right { return left < right }

        let byName = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if byName != .orderedSame { return byName == .orderedAscending }

        // Two printings of one card: ordered by artwork so that the list does
        // not reshuffle them from one edit to the next.
        return lhs.id.rawValue < rhs.id.rawValue
    }

    /// Re-evaluates without touching storage, for measuring the edit budget.
    public func reevaluate() {
        rebuild()
    }

    // MARK: - Editing

    /// Searches the catalog for a card to add.
    /// Offers cards to add, narrowed by the text and by the deck's format.
    ///
    /// An empty query offers the format's pool rather than nothing: browsing
    /// for something to add is how a deck gets built. The format filter is
    /// what stops a GOAT deck being offered a card it could never hold.
    public func searchCatalogue() async {
        guard let catalogue, let deck else {
            candidates = []
            return
        }

        candidateGeneration += 1
        let mine = candidateGeneration

        var filters = CardFilters()
        filters.format = deck.format
        let query = CardQuery(
            text: catalogueQuery, filters: filters, limit: Self.candidateLimit)

        let outcome = try? await catalogue.search(query)
        // A result for text the user has moved past belongs to a question no
        // longer being asked.
        guard mine == candidateGeneration else { return }
        candidates = outcome?.cards ?? []
    }

    /// Adds a card, placing it by its frame unless a section was chosen.
    ///
    /// The placement rule is the validator's own, so a card the editor puts
    /// somewhere is never then reported for being there.
    public func add(_ card: Card, to section: DeckSection? = nil) async {
        guard let deck, let artwork = card.artworks.first else { return }
        let target = section ?? DeckValidator.defaultSection(for: card.frame)
        await add(artwork: artwork, to: target)
    }

    /// Adding and removing go through `DeckBuilding`, which is what an editor
    /// built without the rearranging port still has. Only counts and moves
    /// need `DeckEditing`.
    public func add(artwork: ArtworkIdentifier, to section: DeckSection) async {
        guard let deck else { return }
        let before = quantity(of: artwork, in: section)
        await perform(
            { try await self.repository.addCard(
                artwork: artwork, section: section, to: deck.id) },
            recording: .quantity(artwork: artwork, section: section,
                                 from: before, to: before + 1),
            in: deck.id)
    }

    public func remove(artwork: ArtworkIdentifier, from section: DeckSection) async {
        guard let deck else { return }
        let before = quantity(of: artwork, in: section)
        guard before > 0 else { return }
        await perform(
            { try await self.repository.removeCard(
                artwork: artwork, section: section, from: deck.id) },
            recording: .quantity(artwork: artwork, section: section,
                                 from: before, to: before - 1),
            in: deck.id)
    }

    /// Makes a section hold exactly this many copies.
    public func setQuantity(
        _ copies: Int, of artwork: ArtworkIdentifier, in section: DeckSection
    ) async {
        guard let deck else { return }
        let before = quantity(of: artwork, in: section)
        guard copies != before else { return }
        await apply(.quantity(artwork: artwork, section: section,
                              from: before, to: max(0, copies)), in: deck.id)
    }

    /// Moves copies from one section to another.
    public func move(
        _ artwork: ArtworkIdentifier, from source: DeckSection,
        to destination: DeckSection, copies: Int = 1
    ) async {
        guard let deck, source != destination else { return }
        let held = quantity(of: artwork, in: source)
        let moving = min(copies, held)
        guard moving > 0 else { return }
        await apply(.move(artwork: artwork, from: source,
                          to: destination, copies: moving), in: deck.id)
    }

    // MARK: - Preview

    /// The card the panel is showing.
    public private(set) var previewCard: Card?
    /// Why the panel has nothing to show, when that is a failure rather than
    /// an absence. "Nothing selected" invites a selection; "this could not be
    /// read" reports a problem, and a screen has to say different things.
    public private(set) var previewFailure: String?
    /// Whether the panel is on screen. Dismissing keeps the card, so bringing
    /// it back is not a second search for something already found.
    public private(set) var isPreviewVisible = true

    public func previewEntry(_ item: DeckEntryItem) async {
        guard let reader else {
            previewFailure = "Questo editor non può aprire il dettaglio delle carte."
            return
        }

        previewGeneration += 1
        let mine = previewGeneration

        do {
            let card = try await reader.card(with: item.card)
            guard mine == previewGeneration else { return }
            if let card {
                previewCard = card
                previewFailure = nil
            } else {
                previewCard = nil
                previewFailure = "\(item.title) non è più nel catalogo."
            }
        } catch {
            guard mine == previewGeneration else { return }
            previewCard = nil
            previewFailure = "Carta non leggibile: \(error)"
        }
    }

    /// A search result is already a card, so this needs no read at all.
    public func previewCandidate(_ card: Card) {
        previewGeneration += 1
        previewCard = card
        previewFailure = nil
        isPreviewVisible = true
    }

    /// Previews whatever is selected now, which is what an arrow key does.
    public func previewSelection() async {
        guard let item = selectedItem else { return }
        await previewEntry(item)
    }

    public func dismissPreview() {
        isPreviewVisible = false
    }

    public func restorePreview() {
        isPreviewVisible = true
    }

    // MARK: - Dropping

    /// The section a drag is currently over, or `nil` when nothing is being
    /// dragged. The view highlights it; nothing else depends on it.
    public private(set) var dropTarget: DeckSection?

    public func dragEntered(_ section: DeckSection?) {
        dropTarget = section
    }

    /// Applies a drop.
    ///
    /// This is the part a proof can reach: given what was dragged and where it
    /// landed, it moves or adds. What no proof here covers is SwiftUI
    /// delivering the drag to it, which is checked by hand.
    @discardableResult
    public func drop(_ payload: DeckDragPayload, on section: DeckSection) async -> Bool {
        dropTarget = nil
        switch payload {
        case let .deckCard(artwork, source, copies):
            guard source != section else { return false }
            await move(artwork, from: source, to: section, copies: copies)
            return lastFailure == nil
        case let .candidate(artwork):
            await add(artwork: artwork, to: section)
            return lastFailure == nil
        }
    }

    // MARK: - Keyboard

    /// Moves the selected card to another section without a pointer.
    public func moveSelection(to section: DeckSection, copies: Int = 1) async {
        guard let item = selectedItem else { return }
        await move(item.id, from: item.section, to: section, copies: copies)
    }

    /// Changes the selected card's count without a pointer.
    public func changeSelectedQuantity(by delta: Int) async {
        guard let item = selectedItem else { return }
        await setQuantity(item.quantity + delta, of: item.id, in: item.section)
    }

    // MARK: - Judged against a published list

    /// Every stored list, newest first within its format.
    public private(set) var availableLists: [BanlistRevision] = []
    /// The list the deck is being judged against.
    public private(set) var chosenList: BanlistRevision?
    /// What that list makes of the deck.
    public private(set) var verdict: DeckListVerdict?
    public private(set) var isLegalityVisible = false
    public private(set) var selectedJudgedCard: CardIdentifier?
    /// True when the deck's format is played under no published list. An
    /// answer, not a gap: judging it against the current TCG list would look
    /// authoritative and be wrong.
    public private(set) var formatHasNoList = false

    public var canJudge: Bool { judging != nil && lists != nil && deck != nil }

    /// Reads the stored lists, newest first inside each format.
    public func loadLists() async {
        guard let lists else { return }
        let stored = BanlistFormat.allCases.flatMap { format in
            (try? lists.revisions(for: format)) ?? []
        }
        availableLists = stored.sorted { left, right in
            left.format == right.format
                ? left.effectiveDate > right.effectiveDate
                : left.format.rawValue < right.format.rawValue
        }
    }

    /// The list a deck's format implies, resolved against what is stored.
    ///
    /// A format naming no date means the newest list that format has.
    public func impliedList(for format: CardFormat) -> BanlistRevision? {
        guard let implied = format.impliedList else { return nil }
        let ofFormat = availableLists.filter { $0.format == implied.format }
        guard let date = implied.effectiveDate else { return ofFormat.first }
        return ofFormat.first { $0.effectiveDate == date } ?? ofFormat.first
    }

    /// Judges the open deck against a list, leaving the deck untouched.
    public func judge(against list: BanlistRevision) async {
        guard let judging, let deck else { return }
        chosenList = list
        formatHasNoList = false
        do {
            let cards = try await judging.judge(
                deck.id, against: list.format, effectiveDate: list.effectiveDate)
            verdict = DeckListVerdict(list: list, cards: cards)
            if let selectedJudgedCard,
               !cards.contains(where: { $0.card == selectedJudgedCard }) {
                self.selectedJudgedCard = nil
            }
        } catch {
            verdict = nil
            lastFailure = "Lista non applicata: \(error)"
        }
    }

    /// Judges against whatever the deck's own format implies, or reports that
    /// nothing does.
    public func judgeAgainstImpliedList() async {
        guard canJudge, let deck else { return }
        if availableLists.isEmpty { await loadLists() }

        guard let list = impliedList(for: deck.format) else {
            chosenList = nil
            verdict = nil
            formatHasNoList = true
            return
        }
        await judge(against: list)
    }

    public func showLegality() async {
        guard canJudge else { return }
        await loadLists()
        if verdict == nil && !formatHasNoList { await judgeAgainstImpliedList() }
        isLegalityVisible = true
        if selectedJudgedCard == nil { selectedJudgedCard = verdict?.cards.first?.card }
    }

    public func hideLegality() {
        isLegalityVisible = false
    }

    /// Steps through the judged cards, stopping at the ends rather than
    /// wrapping, as every other list in this editor does.
    public func moveJudgedSelection(by offset: Int) {
        guard let cards = verdict?.cards, !cards.isEmpty else { return }
        let identifiers = cards.map(\.card)
        guard let current = selectedJudgedCard,
              let index = identifiers.firstIndex(of: current) else {
            selectedJudgedCard = identifiers.first
            return
        }
        selectedJudgedCard = identifiers[min(max(index + offset, 0), identifiers.count - 1)]
    }

    // MARK: - Labels

    public var canLabel: Bool { labelling != nil && deck != nil }

    /// The deck's tags, as stored with it.
    public var tags: [String] { deck?.tags ?? [] }

    /// Every tag in use anywhere, for offering rather than retyping.
    public private(set) var availableTags: [String] = []

    public func loadTags() async {
        guard let labelling else { return }
        availableTags = (try? await labelling.allTags()) ?? []
    }

    /// Sets the deck's format, and re-judges it against the new one.
    ///
    /// The reload is the same `load(deckID:)` every edit uses, which is what
    /// makes the new verdict immediate rather than a second refresh path. A
    /// deck can become illegal here; nothing is removed from it when it does.
    public func changeFormat(to format: CardFormat) async {
        guard let labelling, let deck else { return }
        do {
            try await labelling.changeFormat(deck.id, to: format)
            lastFailure = nil
        } catch {
            lastFailure = "Formato non cambiato: \(error)"
        }
        await load(deckID: deck.id)
    }

    public func addTag(_ name: String) async {
        guard let labelling, let deck else { return }
        do {
            try await labelling.addTag(name, to: deck.id)
            lastFailure = nil
        } catch {
            lastFailure = "Etichetta non aggiunta: \(error)"
        }
        await load(deckID: deck.id)
        await loadTags()
    }

    public func removeTag(_ name: String) async {
        guard let labelling, let deck else { return }
        do {
            try await labelling.removeTag(name, from: deck.id)
            lastFailure = nil
        } catch {
            lastFailure = "Etichetta non rimossa: \(error)"
        }
        await load(deckID: deck.id)
        await loadTags()
    }

    // MARK: - Version history

    /// This deck's saved states, newest first.
    public private(set) var versions: [DeckVersion] = []
    /// Whether the panel beside the deck is showing the history.
    public private(set) var isHistoryVisible = false
    /// Which version the keyboard is on.
    public private(set) var selectedVersion: Int64?

    /// Offering a history the editor cannot serve is worse than not offering
    /// one, so the affordance follows the port and the open deck.
    public var canUseHistory: Bool { versioning != nil && deck != nil }

    /// Whether this deck has never been marked. Distinct from a history that
    /// has not been read yet, which is why the panel loads before it opens.
    public private(set) var hasLoadedVersions = false

    public var versionRows: [DeckVersionRow] { versions.map(DeckVersionRow.init) }

    /// Reads every version of the open deck in one call.
    ///
    /// Storage returns them oldest first; the panel wants the newest at the
    /// top, so the order is reversed here rather than by changing a query
    /// `deck-builder` certified. Ties inside one second break on identifier,
    /// so a save immediately after a restore reads in the order it happened.
    public func loadVersions() async {
        guard let versioning, let deck else { return }
        do {
            let stored = try await versioning.versions(of: deck.id)
            versions = stored.sorted { left, right in
                left.createdAt == right.createdAt
                    ? left.id > right.id
                    : left.createdAt > right.createdAt
            }
            hasLoadedVersions = true
            if let selectedVersion, !versions.contains(where: { $0.id == selectedVersion }) {
                self.selectedVersion = nil
            }
        } catch {
            lastFailure = "Cronologia non leggibile: \(error)"
        }
    }

    /// Marks where the deck is now.
    ///
    /// The label may be absent: an unnamed version reads as the moment it was
    /// taken, which is what `DeckVersionRow` does with it.
    public func saveVersion(named label: String? = nil) async {
        guard let versioning, let deck else { return }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await versioning.saveVersion(
                of: deck.id, label: (trimmed?.isEmpty ?? true) ? nil : trimmed)
            lastFailure = nil
            await loadVersions()
        } catch {
            lastFailure = "Versione non salvata: \(error)"
        }
    }

    /// Opens the panel on the history, reading it first so it never appears
    /// empty and then fills.
    public func showHistory() async {
        guard canUseHistory else { return }
        await loadVersions()
        isHistoryVisible = true
        if selectedVersion == nil { selectedVersion = versions.first?.id }
    }

    public func hideHistory() {
        isHistoryVisible = false
    }

    public func selectVersion(_ versionID: Int64) {
        selectedVersion = versionID
    }

    /// Steps through the versions. Stops at the ends rather than wrapping, so
    /// a held key does not cycle silently — the same rule the card detail's
    /// focus stepping follows.
    public func moveVersionSelection(by offset: Int) {
        guard !versions.isEmpty else { return }
        let identifiers = versions.map(\.id)
        guard let current = selectedVersion,
              let index = identifiers.firstIndex(of: current) else {
            selectedVersion = identifiers.first
            return
        }
        let next = min(max(index + offset, 0), identifiers.count - 1)
        selectedVersion = identifiers[next]
    }

    /// The version a restore was asked for and not yet confirmed.
    ///
    /// A restore replaces every card in a deck, and a deck is the one thing
    /// here that cannot be downloaded again, so the model asks rather than acts.
    public private(set) var pendingRestore: Int64?

    public func askRestore(_ versionID: Int64) {
        pendingRestore = versionID
    }

    public func cancelRestore() {
        pendingRestore = nil
    }

    /// Restores the version the user confirmed.
    ///
    /// It **takes** the identifier rather than reading `pendingRestore`: an
    /// alert's dismissal clears the armed value before the button's action
    /// runs, which is how a confirmed deletion quietly did nothing in the deck
    /// library, the deck editor, the collection screen and the settings window.
    public func confirmRestore(_ versionID: Int64) async {
        guard let versioning, let deck else { return }
        pendingRestore = nil

        guard versions.first(where: { $0.id == versionID })?.isReadable ?? true else {
            lastFailure = "Questa versione non è leggibile e non può essere ripristinata."
            return
        }

        do {
            try await versioning.restoreVersion(versionID, of: deck.id)
            lastFailure = nil
        } catch {
            lastFailure = "Ripristino non riuscito: \(error)"
        }

        // Reloaded either way, through the same path every edit uses: what is
        // shown must be what is stored, whichever of the two the user expected.
        await load(deckID: deck.id)
        await loadVersions()
    }

    // MARK: - Undo

    /// Undo replays edits through the rearranging port, so an editor built
    /// without one cannot offer it.
    public var canUndo: Bool { editing != nil && history.canUndo }
    public var canRedo: Bool { editing != nil && history.canRedo }

    /// Puts the deck back the way it was before the last edit.
    @discardableResult
    public func undo() async -> Bool {
        guard let deck else { return false }
        guard let inverse = history.takeUndo() else {
            lastFailure = "Non c'è niente da annullare."
            return false
        }
        // Recorded already: applying the inverse must not become a new edit.
        return await apply(inverse, in: deck.id, recordingHistory: false)
    }

    @discardableResult
    public func redo() async -> Bool {
        guard let deck else { return false }
        guard let edit = history.takeRedo() else {
            lastFailure = "Non c'è niente da ripetere."
            return false
        }
        return await apply(edit, in: deck.id, recordingHistory: false)
    }

    /// How many copies a section holds of an artwork right now.
    public func quantity(of artwork: ArtworkIdentifier, in section: DeckSection) -> Int {
        deck?.slots.first { $0.artwork == artwork && $0.section == section }?.quantity ?? 0
    }

    /// The one place an edit reaches storage.
    ///
    /// It catches, reports, and reloads the deck from storage afterwards, so
    /// what is shown is what is stored rather than what was hoped for.
    @discardableResult
    private func perform(
        _ write: () async throws -> Void,
        recording edit: DeckEdit?,
        in deckID: Int64
    ) async -> Bool {
        do {
            try await write()
            lastFailure = nil
            if let edit { history.record(edit) }
            await load(deckID: deckID)
            return true
        } catch {
            lastFailure = "Modifica non riuscita: \(error)"
            // Reloaded even on failure: what is shown must be what is stored,
            // whichever of the two the user was expecting.
            await load(deckID: deckID)
            return false
        }
    }

    @discardableResult
    func apply(_ edit: DeckEdit, in deckID: Int64, recordingHistory: Bool = true) async -> Bool {
        guard let editing else {
            lastFailure = "Questo editor non può riorganizzare il mazzo."
            return false
        }

        return await perform({
            switch edit {
            case let .quantity(artwork, section, _, to):
                try await editing.setQuantity(
                    artwork: artwork, section: section, to: to, in: deckID)
            case let .move(artwork, from, to, copies):
                try await editing.move(
                    artwork: artwork, from: from, to: to, copies: copies, in: deckID)
            }
        }, recording: recordingHistory ? edit : nil, in: deckID)
    }

    /// Asks rather than acts. A deck is irreplaceable, so the confirmation is
    /// a separate step the interface has to take deliberately.
    public func requestDeletion() {
        pendingDeletion = deck?.id
    }

    /// Re-asserts a deletion the user has already confirmed.
    ///
    /// A dialog dismisses itself before running its button's action, and the
    /// dismissal clears what was pending — so the action has to put back the
    /// deck it captured while the dialog was being built.
    public func requestDeletion(_ deckID: Int64) {
        pendingDeletion = deckID
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
