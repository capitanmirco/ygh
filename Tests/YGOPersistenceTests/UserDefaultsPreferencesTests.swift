import Foundation
import Testing
@testable import YGOPersistence
import YGOCore

@Suite("UserDefaultsPreferences")
struct UserDefaultsPreferencesTests {
    /// A suite of its own per test, removed afterwards, so nothing here can
    /// read or write the user's real preferences.
    private func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "YGODeckManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    /// Evidence for R4.AC1: a launch is a second store over the same suite,
    /// which is what "opens on the section you chose" means in practice.
    @Test func aChosenStartingSectionIsReadBackByALaterInstance() {
        withSuite { defaults in
            UserDefaultsPreferences(defaults: defaults)
                .save(Preferences(startingSection: .decks))

            let afterRelaunch = UserDefaultsPreferences(defaults: defaults).load()
            #expect(afterRelaunch.startingSection == .decks)
        }
    }

    /// Evidence for R4.AC2: the same for the language the catalog reads in.
    @Test func aChosenCardLanguageIsReadBackByALaterInstance() {
        withSuite { defaults in
            let store = UserDefaultsPreferences(defaults: defaults)
            store.save(Preferences(startingSection: .catalog, cardLanguage: .english))

            let afterRelaunch = UserDefaultsPreferences(defaults: defaults).load()
            #expect(afterRelaunch.cardLanguage == .english)
            #expect(afterRelaunch.startingSection == .catalog)

            // And a later write replaces it rather than accumulating.
            store.save(Preferences(startingSection: .decks, cardLanguage: .italian))
            let second = UserDefaultsPreferences(defaults: defaults).load()
            #expect(second.cardLanguage == .italian)
            #expect(second.startingSection == .decks)
        }
    }

    /// Evidence for R4.AC3: a machine that has never opened the settings.
    @Test func anEmptySuiteYieldsTheDefaults() {
        withSuite { defaults in
            let preferences = UserDefaultsPreferences(defaults: defaults).load()
            #expect(preferences == Preferences())
            #expect(preferences.startingSection == .catalog)
            #expect(preferences.cardLanguage == .italian)
        }
    }

    /// Evidence for R4.AC3: a stored value must not be able to stop a launch,
    /// whether it is a section this build lost or bytes that are not JSON.
    @Test func aSuiteHoldingAnUnknownSectionYieldsTheDefaults() {
        withSuite { defaults in
            let unknown = #"{"startingSection":"wardrobe","cardLanguage":"it"}"#
            defaults.set(Data(unknown.utf8), forKey: UserDefaultsPreferences.key)
            #expect(UserDefaultsPreferences(defaults: defaults).load().startingSection == .catalog)

            defaults.set(Data("not json at all".utf8), forKey: UserDefaultsPreferences.key)
            #expect(UserDefaultsPreferences(defaults: defaults).load() == Preferences())

            defaults.set("a string where a blob belongs", forKey: UserDefaultsPreferences.key)
            #expect(UserDefaultsPreferences(defaults: defaults).load() == Preferences())
        }
    }

    /// The date survives the encoder the store actually uses, which the
    /// in-memory round trip in `PreferencesTests` does not observe.
    @Test func theLastCheckTimeSurvivesTheStore() {
        withSuite { defaults in
            let checked = Date(timeIntervalSince1970: 1_758_365_359)
            UserDefaultsPreferences(defaults: defaults)
                .save(Preferences(lastCheckedAt: checked))

            let restored = UserDefaultsPreferences(defaults: defaults).load().lastCheckedAt
            #expect(restored == checked)
        }
    }
}
