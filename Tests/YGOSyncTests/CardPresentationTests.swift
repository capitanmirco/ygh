import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOSync

/// Reads real cards back out of a seeded catalog, so these assertions cover the
/// stored columns and the fallback rule together rather than a hand-built value.
@Suite("Card presentation")
struct CardPresentationTests {
    private func repository() async throws -> (SQLiteCardRepository, [CatalogCardPayload], [CatalogCardPayload]) {
        let database = try SyncFixture.migratedDatabase()
        let english = try SyncFixture.cards("catalog-en.json")
        let italian = try SyncFixture.cards("catalog-it.json")

        _ = try await CatalogSynchronizer(
            client: StubCatalogClient(
                version: CatalogVersion(databaseVersion: "147.04", lastUpdate: ""),
                english: english, italian: italian),
            store: SQLiteCatalogStore(database: database),
            now: { SyncFixture.observedAt }).synchronize()

        return (SQLiteCardRepository(database: database), english, italian)
    }

    /// Evidence for R3.AC2: a translated card reads in Italian.
    @Test func presentsItalianTextWhenTranslationExists() async throws {
        let (repository, _, italian) = try await self.repository()
        let expected = try #require(italian.first)

        let card = try #require(try await repository.card(with: CardIdentifier(expected.id)))
        let text = card.text(in: .italian)

        #expect(text.name == expected.name)
        #expect(text.effect == expected.desc)
        #expect(!text.isFallbackToEnglish)
        // The English text is still there, unchanged, underneath.
        #expect(card.text(in: .english).name == expected.nameEn)
    }

    /// Evidence for R3.AC3: an untranslated card reads in complete English,
    /// never as an empty or placeholder value.
    @Test func presentsCompleteEnglishTextWhenTranslationIsAbsent() async throws {
        let (repository, english, italian) = try await self.repository()
        let translatedIDs = Set(italian.map(\.id))
        let untranslated = try #require(english.first { !translatedIDs.contains($0.id) })

        let card = try #require(try await repository.card(with: CardIdentifier(untranslated.id)))
        let text = card.text(in: .italian)

        #expect(text.name == untranslated.name)
        #expect(text.effect == untranslated.desc)
        #expect(!text.name.isEmpty)
        #expect(!text.effect.isEmpty)
    }

    /// Evidence for R3.AC4: the interface can tell the two cases apart without
    /// inspecting the card's stored columns itself.
    @Test func marksFallbackTextAsUntranslated() async throws {
        let (repository, english, italian) = try await self.repository()
        let translatedIDs = Set(italian.map(\.id))

        let translatedID = try #require(italian.first).id
        let untranslatedID = try #require(english.first { !translatedIDs.contains($0.id) }).id

        let translated = try #require(try await repository.card(with: CardIdentifier(translatedID)))
        let untranslated = try #require(
            try await repository.card(with: CardIdentifier(untranslatedID)))

        #expect(translated.text(in: .italian).isFallbackToEnglish == false)
        #expect(untranslated.text(in: .italian).isFallbackToEnglish == true)

        // English is never a fallback to itself.
        #expect(translated.text(in: .english).isFallbackToEnglish == false)
        #expect(untranslated.text(in: .english).isFallbackToEnglish == false)
    }
}
