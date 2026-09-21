/// Everything the rules need to know about the cards one deck holds.
///
/// A deck holds at most ninety distinct cards, so this is built once when the
/// deck is opened and refreshed for the single card an edit touches. Validation
/// then performs no lookups beyond this dictionary, which is what keeps a
/// re-evaluation inside its budget without a cache that could drift.
public struct DeckCardIndex: Hashable, Sendable {
    /// What the rules need about one card.
    public struct Entry: Hashable, Sendable {
        public let card: CardIdentifier
        public let name: String
        /// The name this card's copies count against, which is not always its
        /// own: `Harpie Lady 1`, `2` and `3` share one.
        public let limitName: String
        public let frame: CardFrame
        public let formats: Set<CardFormat>
        public let banStatus: BanStatus

        /// The catalog's own wording, such as "Effect Monster" or "Normal Spell".
        public let type: String
        /// Absent for spells, traps and link monsters, which have no level.
        public let level: Int?
        public let attribute: CardAttribute?
        public let race: String

        public init(
            card: CardIdentifier,
            name: String,
            limitName: String,
            frame: CardFrame,
            formats: Set<CardFormat>,
            banStatus: BanStatus,
            type: String = "",
            level: Int? = nil,
            attribute: CardAttribute? = nil,
            race: String = ""
        ) {
            self.card = card
            self.name = name
            self.limitName = limitName
            self.frame = frame
            self.formats = formats
            self.banStatus = banStatus
            self.type = type
            self.level = level
            self.attribute = attribute
            self.race = race
        }
    }

    private let entries: [CardIdentifier: Entry]

    public init(entries: [Entry]) {
        self.entries = Dictionary(entries.map { ($0.card, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public subscript(card: CardIdentifier) -> Entry? { entries[card] }

    public var count: Int { entries.count }
}

/// Produces the violations a deck holds.
public protocol DeckValidating: Sendable {
    func violations(in deck: Deck, using index: DeckCardIndex) -> [DeckViolation]
}

extension DeckValidating {
    /// The verdict, including where its authority comes from.
    ///
    /// Default here so that callers never have to remember to check the format
    /// themselves and reach a confident-sounding conclusion from restrictions
    /// the user typed in.
    public func legality(of deck: Deck, using index: DeckCardIndex) -> DeckLegality {
        DeckLegality(
            violations: violations(in: deck, using: index),
            restrictionsAreUserMaintained: !deck.format.hasUpstreamBanList)
    }
}

/// Stores and retrieves decks.
public protocol DeckRepository: Sendable {
    func deck(with id: Int64) async throws -> Deck?
    func allDecks() async throws -> [Deck]
    func createDeck(name: String, format: CardFormat) async throws -> Deck

    /// Builds the index for a deck's own cards in one query.
    func cardIndex(for deck: Deck) async throws -> DeckCardIndex
}

/// The verdict on a deck.
///
/// Carries more than a list of problems, because a verdict reached against
/// restrictions the user typed in themselves does not mean what one reached
/// against a published ban list means, and the interface has to be able to say
/// so without inspecting the stored rows.
public struct DeckLegality: Hashable, Sendable {
    public let violations: [DeckViolation]
    /// True when the deck's format has no upstream ban list, so its
    /// restrictions are only as current as the user has kept them.
    public let restrictionsAreUserMaintained: Bool

    public init(violations: [DeckViolation], restrictionsAreUserMaintained: Bool) {
        self.violations = violations
        self.restrictionsAreUserMaintained = restrictionsAreUserMaintained
    }

    public var isLegal: Bool { violations.isEmpty }
}

/// The writing side of deck storage, as the importer needs it.
///
/// Declared here so that reading a deck file and turning it into a stored deck
/// can live in the interchange module without it knowing SQLite exists.
public protocol DeckBuilding: Sendable {
    func createDeck(name: String, format: CardFormat) async throws -> Deck
    func addCard(artwork: ArtworkIdentifier, section: DeckSection, to deckID: Int64) async throws
    func removeCard(artwork: ArtworkIdentifier, section: DeckSection, from deckID: Int64) async throws
    func deck(with id: Int64) async throws -> Deck?
    func cardIndex(for deck: Deck) async throws -> DeckCardIndex
    func changeFormat(_ deckID: Int64, to format: CardFormat) async throws
    func delete(_ deckID: Int64, confirmed: Bool) async throws

    /// The card an artwork depicts, or `nil` when the catalog holds no such
    /// printing.
    func resolveArtwork(_ artwork: ArtworkIdentifier) async throws -> CardIdentifier?
}

/// Rearranging a deck: setting how many copies a section holds, and moving
/// copies between sections.
///
/// A separate port rather than two more methods on `DeckBuilding`, which every
/// stub in `deck-builder`'s offline proofs conforms to. Adding to that
/// protocol would break each of them for operations they never call.
public protocol DeckEditing: Sendable {
    /// Makes `section` hold exactly `copies` of that artwork. Zero removes it.
    ///
    /// Permissive, like every other write here: a count that breaks a rule is
    /// applied and the validator reports it.
    func setQuantity(
        artwork: ArtworkIdentifier,
        section: DeckSection,
        to copies: Int,
        in deckID: Int64
    ) async throws

    /// Moves up to `copies` from one section to another, in one transaction.
    ///
    /// Returns how many actually moved, which is fewer when the source holds
    /// fewer. A remove followed by an add would leave the deck short between
    /// the two, and short for good if the second failed.
    @discardableResult
    func move(
        artwork: ArtworkIdentifier,
        from source: DeckSection,
        to destination: DeckSection,
        copies: Int,
        in deckID: Int64
    ) async throws -> Int
}

/// One reversible change to a deck.
///
/// Adding and removing are expressed as count changes, so the history has two
/// cases rather than four and every inverse is an edit of the same kind. That
/// is what lets undo reuse the two write operations instead of needing a third
/// way to put a deck into a given state.
public enum DeckEdit: Hashable, Sendable {
    case quantity(
        artwork: ArtworkIdentifier, section: DeckSection, from: Int, to: Int)
    case move(
        artwork: ArtworkIdentifier, from: DeckSection, to: DeckSection, copies: Int)

    public var inverse: DeckEdit {
        switch self {
        case let .quantity(artwork, section, from, to):
            .quantity(artwork: artwork, section: section, from: to, to: from)
        case let .move(artwork, from, to, copies):
            .move(artwork: artwork, from: to, to: from, copies: copies)
        }
    }
}

/// What is being dragged in the deck editor.
///
/// A value rather than a view type, so the drop it lands on is a function a
/// test can call. The gesture that carries it is not covered by any automated
/// proof, which `deck-editing`'s `C6` states.
public enum DeckDragPayload: Hashable, Sendable, Codable {
    /// A card already in the deck, dragged out of a section.
    case deckCard(artwork: ArtworkIdentifier, section: DeckSection, copies: Int)
    /// A card from the editor's candidate list.
    case candidate(artwork: ArtworkIdentifier)
}
