import Foundation
import Observation
import YGOCore

/// Drives the panel beside the results.
///
/// It holds the card being read and nothing about the grid, which is what lets
/// a second selection replace the panel without the results moving.
@MainActor
@Observable
public final class CardDetailViewModel {
    public private(set) var detail: CardDetail?
    public private(set) var isLoading = false
    /// The artwork currently shown, largest variant the store has.
    public private(set) var artwork: ArtworkPresentation?
    public private(set) var selectedArtworkIndex = 0
    /// Where the keyboard is in the panel. Every section is reachable without
    /// a pointer, in the order the panel reads.
    public private(set) var focusedRegion: CardDetailFocusRegion = .artwork

    private let loader: CardDetailLoader
    private let artworkProvider: any ArtworkProviding
    private let format: BanlistFormat
    /// A second selection supersedes the first, so an answer for a card the
    /// user has moved past never lands in the panel.
    private var generation = 0

    public init(
        loader: CardDetailLoader,
        artwork: any ArtworkProviding,
        format: BanlistFormat = .tcg
    ) {
        self.loader = loader
        self.artworkProvider = artwork
        self.format = format
    }

    /// The card's artworks, in catalog order. A card with one has no chooser
    /// to offer; 124 of 14,566 have more.
    public var artworkChoices: [ArtworkIdentifier] {
        detail?.card.artworks ?? []
    }

    public var offersArtworkChooser: Bool { artworkChoices.count > 1 }

    public var isEmpty: Bool { detail == nil }

    public func select(_ card: Card, language: CardLanguage) async {
        generation += 1
        let mine = generation
        isLoading = true
        selectedArtworkIndex = 0

        let loaded = await loader.load(card, language: language, format: format)
        guard mine == generation else { return }

        detail = loaded
        artwork = await presentation(for: card.artworks.first, card: loaded)
        guard mine == generation else { return }
        isLoading = false
    }

    /// Shows another of the card's artworks. Out-of-range is refused rather
    /// than clamped, because a chooser that silently lands elsewhere is worse
    /// than one that does nothing.
    public func showArtwork(at index: Int) async {
        guard let detail, artworkChoices.indices.contains(index) else { return }
        selectedArtworkIndex = index
        artwork = await presentation(for: artworkChoices[index], card: detail)
    }

    public func focus(_ region: CardDetailFocusRegion) {
        focusedRegion = region
    }

    /// Steps through the sections. Stops at the ends rather than wrapping, so
    /// a held key does not cycle silently.
    public func moveFocus(by offset: Int) {
        let regions = CardDetailFocusRegion.allCases
        guard let current = regions.firstIndex(of: focusedRegion) else { return }
        let next = min(max(current + offset, 0), regions.count - 1)
        focusedRegion = regions[next]
    }

    public func clear() {
        generation += 1
        detail = nil
        artwork = nil
        selectedArtworkIndex = 0
        isLoading = false
    }

    private func presentation(
        for identifier: ArtworkIdentifier?, card detail: CardDetail
    ) async -> ArtworkPresentation {
        let name = detail.text.name
        guard let identifier else { return .placeholder(cardName: name) }

        // The full image is what a detail is for. It may not be stored yet -
        // only thumbnails are prefetched - so the thumbnail stands in until
        // the catalog's own retrieval has put the full one on disk.
        if let full = await artworkProvider.storedArtworkPath(for: identifier, variant: .full) {
            return .stored(path: full)
        }
        if let thumb = await artworkProvider.storedArtworkPath(for: identifier, variant: .thumbnail) {
            return .stored(path: thumb)
        }
        return .placeholder(cardName: name)
    }
}
