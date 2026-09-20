import Foundation
import GRDB
import YGOCore
import YGONetworking
import YGOPersistence

/// The user's own deck files, validated against the cards they actually use.
///
/// The catalog fixture holds a sample chosen for structural edge cases; these
/// two decks draw on sixty-six cards that are mostly not in it, so they carry
/// their own fixture. The passcodes come from the files unchanged.
enum RealDeck {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let names = ["Lockdown Burn", "LR-Chaos Turbo"]

    static func cards() throws -> [CatalogCardPayload] {
        try YGOProDeckCatalogClient.decodeDataset(
            Data(contentsOf: root.appending(path: "fixtures/deck-cards-en.json")))
    }

    /// A minimal reader, kept in the tests on purpose: the production one is
    /// built and proven separately, and these assertions must not depend on it.
    static func passcodes(in file: String) throws -> [DeckSection: [Int]] {
        let text = try String(contentsOf: root.appending(path: "fixtures/\(file).ydk"),
                              encoding: .utf8)
        var result: [DeckSection: [Int]] = [:]
        var section: DeckSection?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            switch line {
            case "#main": section = .main
            case "#extra": section = .extra
            case "!side": section = .side
            default:
                if line.hasPrefix("#") || line.hasPrefix("!") { section = nil }
                else if let passcode = Int(line), let section { result[section, default: []].append(passcode) }
            }
        }
        return result
    }

    /// Seeds a catalog with the cards these decks use and returns a repository.
    static func seededRepository() throws -> (DatabaseQueue, SQLiteDeckRepository) {
        let database = try SyncFixture.migratedDatabase()
        try database.write { db in
            try CatalogWriter().writeEnglishDataset(
                try cards(), observedAt: SyncFixture.observedAt, into: db)
        }
        return (database, SQLiteDeckRepository(database: database,
                                               now: { SyncFixture.observedAt }))
    }

    /// Builds one of the user's decks in the given format.
    static func build(
        _ name: String,
        format: CardFormat,
        using repository: SQLiteDeckRepository
    ) async throws -> Deck {
        let deck = try await repository.createDeck(name: name, format: format)
        for (section, passcodes) in try passcodes(in: name) {
            for passcode in passcodes {
                try await repository.addCard(
                    artwork: ArtworkIdentifier(passcode), section: section, to: deck.id)
            }
        }
        return try await repository.deck(with: deck.id)!
    }
}
