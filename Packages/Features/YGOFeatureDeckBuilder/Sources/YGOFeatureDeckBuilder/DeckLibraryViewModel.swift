import Foundation
import Observation
import YGOCore
import YGODeckIO

/// The decks themselves: starting one, taking one out, and keeping the list
/// tidy.
///
/// Every operation it calls was already implemented and certified and had no
/// caller. This is the caller.
@MainActor
@Observable
public final class DeckLibraryViewModel {
    /// The default a deck gets when the user names it nothing. Storing a blank
    /// name would make the list unreadable a week later.
    public static let defaultName = "Nuovo mazzo"

    public private(set) var decks: [Deck] = []
    public private(set) var lastFailure: String?
    /// Set by `requestDeletion`. A deck is irreplaceable, so the confirmation
    /// is a separate step the interface has to take deliberately.
    public private(set) var pendingDeletion: Int64?
    /// The deck a creation or duplication just produced, so the interface can
    /// open it rather than leaving the user to find it.
    public private(set) var deckToOpen: Int64?

    private let repository: any DeckBuilding
    /// Reads the list. A separate dependency rather than a cast of
    /// `repository`: casting made listing work only when the two happened to
    /// be the same object, and failed silently when they were not.
    private let listing: any DeckRepository
    private let library: (any DeckLibraryWriting)?
    /// Formats and tags. Absent means the list can show labels but not change
    /// them, the same way `library` absent means it cannot delete.
    private let labels: (any DeckLabelling)?

    /// The tag the list is narrowed to, or nil for the whole library.
    public private(set) var tagFilter: String?
    /// Every tag in use, for offering rather than retyping.
    public private(set) var availableTags: [String] = []

    public init(
        repository: any DeckBuilding,
        listing: any DeckRepository,
        library: (any DeckLibraryWriting)? = nil,
        labels: (any DeckLabelling)? = nil
    ) {
        self.repository = repository
        self.listing = listing
        self.library = library
        self.labels = labels
    }

    public var canLabel: Bool { labels != nil }

    /// The formats a deck can be set to.
    public var offeredFormats: [CardFormat] { CardFormat.allCases }

    /// The list as it should be read right now.
    ///
    /// A predicate over `decks` rather than a second array kept in step: this
    /// project has already been bitten by a stale copy of this list, which
    /// missed a rename because renaming does not change how many decks there
    /// are.
    public var visibleDecks: [Deck] {
        guard let tagFilter else { return decks }
        return decks.filter { deck in
            deck.tags.contains { $0.caseInsensitiveCompare(tagFilter) == .orderedSame }
        }
    }

    /// True when a filter is hiding everything. Different from an empty
    /// library, and the interface has to say so differently.
    public var filterMatchesNothing: Bool {
        tagFilter != nil && visibleDecks.isEmpty && !decks.isEmpty
    }

    public func filter(byTag tag: String?) {
        tagFilter = tag
    }

    public func loadTags() async {
        guard let labels else { return }
        availableTags = (try? await labels.allTags()) ?? []
    }

    public func addTag(_ name: String, to deckID: Int64) async {
        guard let labels else { return }
        do {
            try await labels.addTag(name, to: deckID)
            lastFailure = nil
        } catch {
            lastFailure = "Etichetta non aggiunta: \(error)"
        }
        await reload()
        await loadTags()
    }

    public func removeTag(_ name: String, from deckID: Int64) async {
        guard let labels else { return }
        do {
            try await labels.removeTag(name, from: deckID)
            lastFailure = nil
        } catch {
            lastFailure = "Etichetta non rimossa: \(error)"
        }
        await reload()
        await loadTags()
        // A filter on a tag nobody carries any more would hide everything for
        // a reason the user cannot see.
        if let tagFilter, !availableTags.contains(where: {
            $0.caseInsensitiveCompare(tagFilter) == .orderedSame
        }) {
            self.tagFilter = nil
        }
    }

    /// The list as stored. Clears a previous failure, because this is the
    /// user asking to start again rather than the tail of a write.
    public func load() async {
        lastFailure = nil
        await reload()
    }

    /// Re-reads the list without touching a failure a write has just
    /// reported. `load` clearing it was why a refused creation reported
    /// nothing: the reload that followed wiped the message on its way out.
    private func reload() async {
        do {
            decks = try await allDecks()
        } catch {
            lastFailure = "Elenco non leggibile: \(error)"
        }
    }

    private func allDecks() async throws -> [Deck] {
        try await listing.allDecks()
    }

    // MARK: - Starting one

    @discardableResult
    public func createDeck(named name: String, format: CardFormat) async -> Deck? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = trimmed.isEmpty ? Self.defaultName : trimmed

        do {
            let deck = try await repository.createDeck(name: chosen, format: format)
            await reload()
            lastFailure = nil
            // Created to be filled, so it opens rather than joining a list.
            deckToOpen = deck.id
            return deck
        } catch {
            await reload()
            lastFailure = "Mazzo non creato: \(error)"
            return nil
        }
    }

    public func clearDeckToOpen() {
        deckToOpen = nil
    }

    // MARK: - Keeping the list tidy

    public func rename(_ deckID: Int64, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let library, !trimmed.isEmpty else {
            lastFailure = trimmed.isEmpty
                ? "Un mazzo senza nome non si ritrova."
                : "Questo elenco non può rinominare i mazzi."
            return
        }

        do {
            try await library.rename(deckID, to: trimmed)
            await reload()
            lastFailure = nil
        } catch {
            await reload()
            lastFailure = "Rinomina non riuscita: \(error)"
        }
    }

    @discardableResult
    public func duplicate(_ deckID: Int64) async -> Deck? {
        guard let library else {
            lastFailure = "Questo elenco non può duplicare i mazzi."
            return nil
        }

        let original = decks.first { $0.id == deckID }
        let name = "\(original?.name ?? Self.defaultName) (copia)"

        do {
            let copy = try await library.duplicate(deckID, named: name)
            await reload()
            lastFailure = nil
            deckToOpen = copy.id
            return copy
        } catch {
            await reload()
            lastFailure = "Duplicazione non riuscita: \(error)"
            return nil
        }
    }

    public func changeFormat(_ deckID: Int64, to format: CardFormat) async {
        do {
            if let labels {
                try await labels.changeFormat(deckID, to: format)
            } else {
                try await repository.changeFormat(deckID, to: format)
            }
            await reload()
            lastFailure = nil
        } catch {
            await reload()
            lastFailure = "Formato non cambiato: \(error)"
        }
    }

    public func requestDeletion(_ deckID: Int64) {
        pendingDeletion = deckID
    }

    public func cancelDeletion() {
        pendingDeletion = nil
    }

    @discardableResult
    public func confirmDeletion() async -> Bool {
        guard let deckID = pendingDeletion else { return false }
        pendingDeletion = nil

        do {
            try await repository.delete(deckID, confirmed: true)
            await reload()
            lastFailure = nil
            return true
        } catch {
            await reload()
            lastFailure = "Eliminazione non riuscita: \(error)"
            return false
        }
    }

    // MARK: - Taking one out

    public func ydkText(for deckID: Int64) async -> String? {
        guard let deck = await deck(deckID) else { return nil }
        return DeckExporter.ydkText(for: deck)
    }

    public func ydkeLink(for deckID: Int64) async -> String? {
        guard let deck = await deck(deckID) else { return nil }
        return DeckExporter.ydkeLink(for: deck)
    }

    /// Writes the deck to a file the user chose.
    ///
    /// Legality is not judged: an unfinished deck is exactly the kind a
    /// duelist carries between machines.
    @discardableResult
    public func export(_ deckID: Int64, to url: URL) async -> Bool {
        guard let deck = await deck(deckID) else {
            lastFailure = "Mazzo non trovato."
            return false
        }

        do {
            try DeckExporter.write(deck, to: url)
            lastFailure = nil
            return true
        } catch {
            lastFailure = "Esportazione non riuscita: \(error)"
            return false
        }
    }

    private func deck(_ deckID: Int64) async -> Deck? {
        do {
            return try await repository.deck(with: deckID)
        } catch {
            lastFailure = "Mazzo non leggibile: \(error)"
            return nil
        }
    }
}

extension DeckLibraryViewModel {
    /// The `.ydk` text for a deck already in the list.
    ///
    /// Synchronous because a file exporter asks for its document while it is
    /// being presented, and the list it reads from is already loaded.
    public func exportText(for deckID: Int64?) -> String? {
        guard let deckID, let deck = decks.first(where: { $0.id == deckID }) else { return nil }
        return DeckExporter.ydkText(for: deck)
    }

    /// What the saved file is called. The deck's own name, because a `.ydk`
    /// carries none and the file name is the only place it survives.
    public func exportName(for deckID: Int64?) -> String {
        guard let deckID, let deck = decks.first(where: { $0.id == deckID }) else {
            return Self.defaultName
        }
        return deck.name
    }
}
