import Foundation
import Testing
@testable import YGOCore

@Suite("Preferences")
struct PreferencesTests {
    private func decode(_ json: String) throws -> Preferences {
        try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
    }

    /// Evidence for R4.AC3: what the application opens on before anyone has
    /// chosen anything.
    @Test func defaultPreferencesOpenTheCatalogInItalian() {
        let preferences = Preferences()
        #expect(preferences.startingSection == .catalog)
        #expect(preferences.cardLanguage == .italian)
        #expect(preferences.lastCheckedAt == nil)
        #expect(AppSection.fallback == .catalog)
    }

    /// Evidence for R4.AC3: a section this build does not have costs the
    /// preference, not the launch.
    @Test func anUnknownSectionDecodesToTheDefault() throws {
        let preferences = try decode(#"{"startingSection":"wardrobe","cardLanguage":"en"}"#)
        #expect(preferences.startingSection == .catalog)
        #expect(preferences.cardLanguage == .english, "solo il campo illeggibile ricade")

        let known = try decode(#"{"startingSection":"decks","cardLanguage":"en"}"#)
        #expect(known.startingSection == .decks)
    }

    /// Evidence for R4.AC3: the same leniency for a language the catalog does
    /// not store.
    @Test func anUnknownLanguageDecodesToTheDefault() throws {
        let preferences = try decode(#"{"startingSection":"banlist","cardLanguage":"de"}"#)
        #expect(preferences.cardLanguage == .italian)
        #expect(preferences.startingSection == .banlist, "solo il campo illeggibile ricade")

        let empty = try decode("{}")
        #expect(empty.startingSection == .catalog)
        #expect(empty.cardLanguage == .italian)
        #expect(empty.lastCheckedAt == nil)
    }

    /// Evidence for R4.AC1, R4.AC2 and R4.AC3: every field survives the
    /// encoding the store writes, including the one that may be absent.
    @Test func everyStoredFieldSurvivesACodableRoundTrip() throws {
        let checked = Date(timeIntervalSince1970: 1_758_365_359)
        let original = Preferences(
            startingSection: .value, cardLanguage: .english, lastCheckedAt: checked)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let restored = try decoder.decode(Preferences.self, from: encoder.encode(original))
        #expect(restored == original)

        let withoutDate = Preferences(startingSection: .decks, cardLanguage: .italian)
        let restoredWithout = try decoder.decode(
            Preferences.self, from: encoder.encode(withoutDate))
        #expect(restoredWithout == withoutDate)
        #expect(restoredWithout.lastCheckedAt == nil)

        // Every section the window offers survives the trip, so a preference
        // cannot be written for a case that cannot be read back.
        for section in AppSection.allCases {
            let one = Preferences(startingSection: section)
            let back = try decoder.decode(Preferences.self, from: encoder.encode(one))
            #expect(back.startingSection == section)
        }
    }
}
