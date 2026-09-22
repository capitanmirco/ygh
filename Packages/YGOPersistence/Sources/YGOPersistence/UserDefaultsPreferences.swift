import Foundation
import YGOCore

/// Keeps preferences in `UserDefaults` rather than in the catalog database.
///
/// Two reasons, both of them about the database rather than about preferences.
/// A table for three fields is a schema migration, and a migration makes the
/// bootstrapper write the pre-migration backup this feature exists to let the
/// user reclaim. And a user who deletes `library.sqlite` to rebuild the catalog
/// from upstream should not also lose which section the window opens on.
///
/// `UserDefaults` is documented as safe to use from several threads, which is
/// why the unchecked conformance is honest here; nothing else about this type
/// carries state.
public struct UserDefaultsPreferences: PreferenceStoring, @unchecked Sendable {
    /// One key holding one encoded value, so a partially written set of
    /// preferences is not a state this type can be in.
    static let key = "preferences"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Anything unreadable — absent, not JSON, or naming a section this build
    /// does not have — yields the defaults. `Preferences` decodes leniently
    /// field by field; this catches the case where the whole value is rubble.
    public func load() -> Preferences {
        guard let data = defaults.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return Preferences() }
        return stored
    }

    public func save(_ preferences: Preferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
