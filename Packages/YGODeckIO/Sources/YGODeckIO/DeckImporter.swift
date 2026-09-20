import Foundation
import YGOCore

/// What an import produced.
public struct DeckImportResult: Sendable {
    public let deck: Deck
    /// Passcodes the catalog does not hold. The rest of the deck was imported
    /// anyway: losing thirty-nine cards because of one is not a service.
    public let unresolvedPasscodes: [Int]
    public let proposedFormat: CardFormat

    public var isComplete: Bool { unresolvedPasscodes.isEmpty }
}

/// Turns a deck file or link into a stored deck.
///
/// Both formats decode to a `DeckList` first, so resolution, alternate artwork
/// handling, naming and the format proposal are written once.
public struct DeckImporter: Sendable {
    /// Which format to propose when several are equally clean. Ordered by how
    /// likely a downloaded list is to belong to each.
    public static let formatPreference: [CardFormat] = [
        .tcg, .ocg, .goat, .edison, .masterDuel, .ocgGoat,
        .duelLinks, .speedDuel, .commonCharity,
    ]

    private let repository: any DeckBuilding
    private let validator: any DeckValidating

    public init(repository: any DeckBuilding, validator: any DeckValidating) {
        self.repository = repository
        self.validator = validator
    }

    // MARK: - Entry points

    /// Imports a `.ydk` file, naming the deck after it.
    ///
    /// The file records no name of its own, so the filename is the only thing
    /// there is to go on.
    public func importFile(at url: URL) async throws -> DeckImportResult {
        let list = try YDKFile.read(contentsOf: url)
        return try await store(list, named: url.deletingPathExtension().lastPathComponent)
    }

    public func importLink(_ link: String, named name: String) async throws -> DeckImportResult {
        let list = try YDKeCodec.decode(link)
        return try await store(list, named: name)
    }

    // MARK: - Storing

    /// Nothing is written until the whole list has been decoded, so a malformed
    /// file cannot leave half a deck behind.
    private func store(_ list: DeckList, named name: String) async throws -> DeckImportResult {
        var unresolved: [Int] = []
        var resolved: [(ArtworkIdentifier, DeckSection)] = []

        for section in DeckSection.allCases {
            for passcode in list[section] {
                let artwork = ArtworkIdentifier(passcode)
                if try await repository.resolveArtwork(artwork) != nil {
                    resolved.append((artwork, section))
                } else {
                    unresolved.append(passcode)
                }
            }
        }

        let deck = try await repository.createDeck(
            name: name, format: Self.formatPreference[0])
        for (artwork, section) in resolved {
            try await repository.addCard(artwork: artwork, section: section, to: deck.id)
        }

        let stored = try await repository.deck(with: deck.id) ?? deck
        let proposed = try await proposeFormat(for: stored)
        if proposed != stored.format {
            try await repository.changeFormat(stored.id, to: proposed)
        }

        let final = try await repository.deck(with: deck.id) ?? stored
        return DeckImportResult(
            deck: final, unresolvedPasscodes: unresolved, proposedFormat: proposed)
    }

    // MARK: - Format proposal

    /// The format in which the deck holds fewest violations.
    ///
    /// A `.ydk` file records no format, so without this a retro deck opens
    /// covered in violations it does not really have, and the duelist is left
    /// to guess which of nine formats the list was built for.
    ///
    /// Section sizes are ignored here: they are the same in every format and
    /// would only dilute the comparison.
    public func proposeFormat(for deck: Deck) async throws -> CardFormat {
        var best = Self.formatPreference[0]
        var fewest = Int.max

        for format in Self.formatPreference {
            var candidate = deck
            candidate.format = format

            let index = try await repository.cardIndex(for: candidate)
            let count = validator.violations(in: candidate, using: index)
                .filter { violation in
                    switch violation {
                    case .sectionSize, .misplacedCard: false
                    case .overCopyLimit, .outsideFormatPool: true
                    }
                }
                .count

            if count < fewest {
                fewest = count
                best = format
                if count == 0 { break }
            }
        }

        return best
    }
}
