import Foundation
import Observation
import YGOCore

/// Reads one Forbidden & Limited List at a time.
@MainActor
@Observable
public final class BanlistBrowserViewModel {
    public private(set) var format: BanlistFormat = .tcg
    /// The lists stored for the chosen format, newest first.
    ///
    /// Newest first, unlike the catalog's chooser: that one is a history to
    /// look back through, this one opens on the rules as they stand.
    public private(set) var availableLists: [BanlistRevision] = []
    public private(set) var selectedDate: String?
    public private(set) var groups: [BanlistGroup] = []
    public private(set) var unmatched = 0
    public private(set) var failure: String?

    /// The card the panel is showing, and why it has nothing to show.
    public private(set) var previewCard: Card?
    public private(set) var previewFailure: String?

    private let history: any BanlistHistoryReading
    private let catalog: (any CardRepository)?
    /// A list is walked with the arrow keys, so a read that answers after the
    /// selection moved on belongs to a card nobody is looking at.
    private var previewGeneration = 0

    public init(history: any BanlistHistoryReading, catalog: (any CardRepository)? = nil) {
        self.history = history
        self.catalog = catalog
    }

    /// True when nothing has been downloaded for this format yet, which the
    /// screen states rather than showing three empty groups.
    public var hasNoStoredLists: Bool { availableLists.isEmpty }

    /// What is on screen, named. A list without its date is an assertion
    /// about nothing in particular.
    public var heading: String {
        guard let selectedDate else { return "Nessuna lista scelta" }
        return "\(format.displayName) · \(selectedDate)"
    }

    /// A format frozen at a list names it, because GOAT's is remembered as
    /// April 2005 and the source dates it 2005-03-01.
    public func label(for date: String) -> String {
        let frozen = CardFormat.allCases.first {
            $0.banlistFormat == format && $0.definingListDate == date
        }
        return frozen.map { "\(date) — lista \($0.rawValue)" } ?? date
    }

    public func load(format: BanlistFormat = .tcg) async {
        self.format = format
        do {
            availableLists = try history.revisions(for: format).reversed()
            failure = nil
        } catch {
            availableLists = []
            failure = "Liste non leggibili: \(error)"
        }

        if let newest = availableLists.first {
            await select(newest.effectiveDate)
        } else {
            selectedDate = nil
            groups = BanlistListing.groups(from: [])
            unmatched = 0
        }
    }

    public func select(_ date: String) async {
        selectedDate = date
        do {
            let entries = try history.list(format, effectiveDate: date)
            groups = BanlistListing.groups(from: entries)
            unmatched = BanlistListing.unmatched(in: entries)
            failure = nil
        } catch {
            groups = BanlistListing.groups(from: [])
            unmatched = 0
            failure = "Lista non leggibile: \(error)"
        }
    }

    /// Every card the chosen list names and the catalog can show.
    public var totalShown: Int { groups.reduce(0) { $0 + $1.count } }

    // MARK: - Reading a card

    public func preview(_ entry: BanlistListEntry) async {
        guard let catalog, let cardID = entry.cardID else {
            previewCard = nil
            previewFailure = entry.cardID == nil
                ? "Questa voce non corrisponde a nessuna carta del catalogo."
                : "Questa schermata non può aprire il dettaglio delle carte."
            return
        }

        previewGeneration += 1
        let mine = previewGeneration

        do {
            let card = try await catalog.card(with: CardIdentifier(cardID))
            guard mine == previewGeneration else { return }
            previewCard = card
            previewFailure = card == nil ? "\(entry.displayName) non è più nel catalogo." : nil
        } catch {
            guard mine == previewGeneration else { return }
            previewCard = nil
            previewFailure = "Carta non leggibile: \(error)"
        }
    }
}
