/// How many cards a player holds when they first act.
///
/// A figure computed against the wrong hand size is wrong for every card in
/// the deck, so the size is derived from the format rather than passed in by
/// a caller who might not know the rule.
public struct OpeningHand: Hashable, Sendable {
    public let size: Int
    public let format: CardFormat
    public let playingFirst: Bool

    public init(format: CardFormat, playingFirst: Bool) {
        self.format = format
        self.playingFirst = playingFirst
        // The player going second always draws. The player going first draws
        // only in the formats that predate the modern rule.
        self.size = playingFirst ? (format.firstPlayerDraws ? 6 : 5) : 6
    }

    public static func size(format: CardFormat, playingFirst: Bool) -> Int {
        OpeningHand(format: format, playingFirst: playingFirst).size
    }

    /// What a reported probability says it assumed, so a reader never has to
    /// know their format's first-turn rule to interpret a figure.
    public var description: String {
        let order = playingFirst ? "giocando per primo" : "giocando per secondo"
        return "mano da \(size) carte, \(order), formato \(format.rawValue)"
    }
}
