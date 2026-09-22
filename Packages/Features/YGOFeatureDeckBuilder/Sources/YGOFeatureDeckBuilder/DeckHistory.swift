import Foundation
import YGOCore

/// One saved state, as the panel reads it.
///
/// A row rather than the stored value: what a screen needs is a name, a
/// moment and a size, and a version with no label has to read as when it was
/// taken rather than as a blank.
public struct DeckVersionRow: Hashable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let moment: String
    public let cardCount: Int
    public let isReadable: Bool

    public init(id: Int64, name: String, moment: String, cardCount: Int, isReadable: Bool) {
        self.id = id
        self.name = name
        self.moment = moment
        self.cardCount = cardCount
        self.isReadable = isReadable
    }

    /// What a screen reader says about the row: what it is, when it was taken
    /// and how large it is, in one sentence.
    public var announcement: String {
        isReadable
            ? "\(name), \(moment), \(cardCount) carte"
            : "\(name), \(moment), non leggibile"
    }
}

extension DeckVersionRow {
    /// The moment a version was taken, in the form the rest of the interface
    /// uses for a date carrying a time.
    static func moment(_ date: Date) -> String {
        date.formatted(
            .dateTime.day().month(.wide).year().hour().minute()
                .locale(Locale(identifier: "it_IT")))
    }

    init(_ version: DeckVersion) {
        let moment = Self.moment(version.createdAt)
        self.init(
            id: version.id,
            // An unnamed version reads as when it was taken: a blank row is
            // not a name, and the moment is the only thing that tells two
            // unnamed versions apart.
            name: version.label ?? moment,
            moment: moment,
            cardCount: version.cardCount,
            isReadable: version.isReadable)
    }
}
