import Foundation

/// Where a card sits in a deck.
public enum DeckSection: String, Hashable, Sendable, Codable, CaseIterable {
    case main
    case extra
    case side

    /// The rules cap each section differently, and the main section is the
    /// only one with a floor.
    public var permittedRange: ClosedRange<Int> {
        switch self {
        case .main: 40...60
        case .extra, .side: 0...15
        }
    }
}

/// One entry in a deck: a number of copies of one printing.
///
/// Keyed by artwork rather than by card, because a deck may hold two copies of
/// a card under two different printings and an export has to give back the
/// printing the user actually holds.
public struct DeckSlot: Hashable, Sendable, Identifiable {
    public let artwork: ArtworkIdentifier
    public let card: CardIdentifier
    public let section: DeckSection
    public let quantity: Int

    public var id: ArtworkIdentifier { artwork }

    public init(
        artwork: ArtworkIdentifier,
        card: CardIdentifier,
        section: DeckSection,
        quantity: Int
    ) {
        self.artwork = artwork
        self.card = card
        self.section = section
        self.quantity = max(0, quantity)
    }
}

/// A deck as stored: its identity, the format it is built for, and its slots.
public struct Deck: Hashable, Sendable, Identifiable {
    public let id: Int64
    public var name: String
    public var format: CardFormat
    public var folderID: Int64?
    public var notes: String?
    public var slots: [DeckSlot]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64,
        name: String,
        format: CardFormat,
        folderID: Int64? = nil,
        notes: String? = nil,
        slots: [DeckSlot] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.folderID = folderID
        self.notes = notes
        self.slots = slots
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func slots(in section: DeckSection) -> [DeckSlot] {
        slots.filter { $0.section == section }
    }

    /// How many cards a section holds, counting copies rather than entries.
    public func count(in section: DeckSection) -> Int {
        slots(in: section).reduce(0) { $0 + $1.quantity }
    }

    public var totalCount: Int {
        slots.reduce(0) { $0 + $1.quantity }
    }
}
