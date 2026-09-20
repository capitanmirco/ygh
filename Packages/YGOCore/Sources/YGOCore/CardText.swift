/// A card's name and effect text in one language, plus whether that language is
/// the one the reader asked for.
///
/// Roughly a fifth of the pool has no Italian translation, so a fallback is the
/// normal case rather than an error, and the interface has to be able to say so.
public struct CardText: Hashable, Sendable {
    public let name: String
    public let effect: String
    public let isFallbackToEnglish: Bool

    public init(name: String, effect: String, isFallbackToEnglish: Bool) {
        self.name = name
        self.effect = effect
        self.isFallbackToEnglish = isFallbackToEnglish
    }
}

/// A language the catalog stores card text in.
public enum CardLanguage: String, Hashable, Sendable, Codable, CaseIterable {
    case italian = "it"
    case english = "en"
}
