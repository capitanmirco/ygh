import Foundation

/// What the application remembers between launches.
///
/// Three small facts, none of which belongs to the catalog: the catalog is
/// replaceable and these are not derived from it. `lastCheckedAt` is here
/// rather than in `sync_state` because that row records when a dataset was
/// *stored*, and a check that finds nothing new stores nothing.
public struct Preferences: Hashable, Sendable, Codable {
    public var startingSection: AppSection
    public var cardLanguage: CardLanguage
    /// When an update check last finished, whatever it found.
    public var lastCheckedAt: Date?

    public init(
        startingSection: AppSection = .fallback,
        cardLanguage: CardLanguage = .italian,
        lastCheckedAt: Date? = nil
    ) {
        self.startingSection = startingSection
        self.cardLanguage = cardLanguage
        self.lastCheckedAt = lastCheckedAt
    }

    /// Decoding is lenient on purpose. A stored value naming a section this
    /// build no longer has must cost the user their preference, never their
    /// launch, so an unreadable field falls back instead of throwing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let section = try container.decodeIfPresent(String.self, forKey: .startingSection)
        let language = try container.decodeIfPresent(String.self, forKey: .cardLanguage)
        self.startingSection = section.flatMap(AppSection.init(rawValue:)) ?? .fallback
        self.cardLanguage = language.flatMap(CardLanguage.init(rawValue:)) ?? .italian
        self.lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
    }
}

/// Where preferences are kept.
///
/// Declared here so that the settings screen can read and write them without
/// knowing they are `UserDefaults`, and so that a test can substitute its own.
public protocol PreferenceStoring: Sendable {
    func load() -> Preferences
    func save(_ preferences: Preferences)
}
