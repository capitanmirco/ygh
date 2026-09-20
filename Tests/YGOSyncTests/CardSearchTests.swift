import Foundation
import GRDB
import Testing
import YGOCore
import YGONetworking
import YGOPersistence
@testable import YGOSync

@Suite("Card search")
struct CardSearchTests {
    private func seededRepository() async throws
        -> (SQLiteCardRepository, [CatalogCardPayload], [CatalogCardPayload]) {
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

    /// Evidence for R5.AC1: one card is reachable through either stored
    /// language. A duelist who knows a card by its Italian name and one who
    /// knows it in English both find it.
    @Test func findsSameCardByItalianOnlyAndEnglishOnlySubstrings() async throws {
        let (repository, _, italian) = try await seededRepository()

        // A card whose two names share no word, so each query can only match
        // through its own language column.
        let target = try #require(italian.first { card in
            guard let english = card.nameEn else { return false }
            let italianWords = Set(card.name.lowercased().split(separator: " ").map(String.init))
            let englishWords = Set(english.lowercased().split(separator: " ").map(String.init))
            return italianWords.isDisjoint(with: englishWords)
                && !italianWords.isEmpty && !englishWords.isEmpty
        })
        let italianWord = try #require(target.name.split(separator: " ")
            .map(String.init).max(by: { $0.count < $1.count }))
        let englishName = try #require(target.nameEn)
        let englishWord = try #require(englishName.split(separator: " ")
            .map(String.init).max(by: { $0.count < $1.count }))

        let byItalian = try await repository.search(CardQuery(text: italianWord))
        let byEnglish = try await repository.search(CardQuery(text: englishWord))

        #expect(byItalian.cards.contains { $0.id == CardIdentifier(target.id) },
                "query italiana '\(italianWord)' non ha trovato \(target.name)")
        #expect(byEnglish.cards.contains { $0.id == CardIdentifier(target.id) },
                "query inglese '\(englishWord)' non ha trovato \(englishName)")
    }

    /// Evidence for R5.AC1: Italian card names carry accents that nobody types
    /// into a search box. Without `remove_diacritics 2` on the tokenizer this
    /// returns nothing.
    @Test func matchesAccentedNameFromUnaccentedQuery() async throws {
        let (repository, _, italian) = try await seededRepository()

        let accented = try #require(italian.first { card in
            card.name.contains { "àèéìòùÀÈÉÌÒÙ".contains($0) }
        })
        let accentedWord = try #require(accented.name
            .split(separator: " ").map(String.init)
            .first { $0.contains { "àèéìòùÀÈÉÌÒÙ".contains($0) } })

        let folded = accentedWord.folding(
            options: [.diacriticInsensitive], locale: Locale(identifier: "it_IT"))
        #expect(folded != accentedWord, "la parola scelta deve avere un accento")

        let outcome = try await repository.search(CardQuery(text: folded))

        #expect(outcome.cards.contains { $0.id == CardIdentifier(accented.id) },
                "query '\(folded)' non ha trovato '\(accented.name)'")
    }

    /// Evidence for R5.AC2: a card named after the query comes before cards
    /// that merely mention those words in their effect text.
    @Test func ranksExactNameMatchAboveEffectTextMatches() async throws {
        let (repository, english, _) = try await seededRepository()

        // Pick a card whose exact name also appears inside other cards' text.
        let candidates = english.filter { card in
            english.contains { other in
                other.id != card.id
                    && other.desc.localizedCaseInsensitiveContains(card.name)
            }
        }
        let target = try #require(candidates.first,
                                  "la fixture deve contenere una carta citata nel testo di un'altra")

        let outcome = try await repository.search(CardQuery(text: target.name))
        let cards = outcome.cards

        #expect(cards.count > 1, "servono più risultati perché l'ordinamento significhi qualcosa")
        #expect(cards.first?.id == CardIdentifier(target.id),
                "atteso '\(target.name)' per primo, ricevuto '\(cards.first?.englishName ?? "-")'")
    }

    /// Names beat effect text even without an exact hit: a partial word in a
    /// card's name outranks the same word buried in another card's rules.
    @Test func ranksNameMatchesAboveEffectTextMatchesGenerally() async throws {
        let (repository, english, _) = try await seededRepository()

        let target = try #require(english.first { card in
            let word = card.name.split(separator: " ").first.map(String.init) ?? ""
            return word.count >= 5 && english.contains { other in
                other.id != card.id && other.desc.localizedCaseInsensitiveContains(word)
            }
        })
        let word = try #require(target.name.split(separator: " ").first.map(String.init))

        let cards = try await repository.search(CardQuery(text: word)).cards
        let namedMatches = cards.prefix { card in
            card.englishName.localizedCaseInsensitiveContains(word)
                || (card.italianName?.localizedCaseInsensitiveContains(word) ?? false)
        }

        // Every card whose name carries the word appears before the first one
        // that only mentions it in its text.
        let allNamed = cards.filter { card in
            card.englishName.localizedCaseInsensitiveContains(word)
                || (card.italianName?.localizedCaseInsensitiveContains(word) ?? false)
        }
        #expect(namedMatches.count == allNamed.count)
    }

    /// Search text is user input, not SQL. A quote or an asterisk is FTS5
    /// syntax and would otherwise throw or silently mean something else.
    @Test func treatsPunctuationInQueryTextAsHarmless() async throws {
        let (repository, _, _) = try await seededRepository()

        for hostile in ["\"", "*", "dark \"magician\"", "a:b", "-- drop", "()", "   "] {
            let outcome = try await repository.search(CardQuery(text: hostile))
            // The point is that it answers rather than throwing.
            _ = outcome.cards
        }

        // A query of punctuation alone is a settled empty answer.
        let empty = try await repository.search(CardQuery(text: "***"))
        #expect(empty == .noMatches)
    }

    /// Prefix matching: a partial word still finds the card.
    @Test func matchesOnWordPrefixes() async throws {
        let (repository, english, _) = try await seededRepository()

        let target = try #require(english.first { $0.name.count >= 8 })
        let firstWord = try #require(target.name.split(separator: " ").first.map(String.init))
        guard firstWord.count >= 5 else { return }
        let prefix = String(firstWord.prefix(4))

        let cards = try await repository.search(CardQuery(text: prefix)).cards
        #expect(cards.contains { $0.id == CardIdentifier(target.id) },
                "prefisso '\(prefix)' non ha trovato '\(target.name)'")
    }
}
