import Foundation

/// A saved state of a deck, recoverable later.
///
/// It lives here rather than in the persistence module because a feature
/// module has to name it, and a feature module must not import persistence.
public struct DeckVersion: Hashable, Sendable, Identifiable {
    public let id: Int64
    public let deckID: Int64
    public let label: String?
    public let createdAt: Date
    public let slots: [DeckSlot]
    /// False when the stored snapshot could not be read. The slots are then
    /// empty, which is not the same thing as a version of an empty deck — and
    /// telling the two apart is the difference between a history that is
    /// honest and one that offers to restore nothing.
    public let isReadable: Bool

    /// `isReadable` defaults to true so that every existing caller keeps
    /// describing what it always described: a version that was read.
    public init(
        id: Int64,
        deckID: Int64,
        label: String?,
        createdAt: Date,
        slots: [DeckSlot],
        isReadable: Bool = true
    ) {
        self.id = id
        self.deckID = deckID
        self.label = label
        self.createdAt = createdAt
        self.slots = slots
        self.isReadable = isReadable
    }

    /// How many cards the version holds, counting copies.
    public var cardCount: Int { slots.reduce(0) { $0 + $1.quantity } }
}

/// Saving, listing and restoring a deck's versions.
///
/// One protocol rather than a reading and a writing half: the collection is
/// split that way because a read-only collection screen exists, and no
/// read-only history screen does. It can be split when one appears.
public protocol DeckHistorying: Sendable {
    @discardableResult
    func saveVersion(of deckID: Int64, label: String?) async throws -> Int64

    /// Every version of one deck, oldest first as stored.
    func versions(of deckID: Int64) async throws -> [DeckVersion]

    /// Restores a version into the deck it belongs to, and refuses otherwise.
    ///
    /// The unguarded form reads the version's own deck and restores into it,
    /// so a foreign identifier rewrites a deck nobody was looking at.
    func restoreVersion(_ versionID: Int64, of deckID: Int64) async throws
}

/// Why a restore was refused before it touched anything.
public enum DeckHistoryError: Error, Hashable, Sendable {
    case versionNotFound(Int64)
    case versionBelongsToAnotherDeck(versionID: Int64, deckID: Int64)
}
