import Foundation
import YGOBanlistHistory
import YGOCore

/// Gathers a card's detail from the ports that already store it.
///
/// One load rather than seven independent ones: seven would give seven loading
/// states, seven cancellations when the selection changes, and no single
/// answer to what is missing. Each section catches its own failure, so a read
/// that fails costs its own section and nothing else.
public struct CardDetailLoader: Sendable {
    private let catalog: any CardRepository
    private let details: any CardDetailReading
    private let usage: any CardUsageReading
    private let priceLookup: any PriceLookup
    private let history: any BanlistHistoryReading
    private let provenance: any BanlistProvenanceReporting

    public init(
        catalog: any CardRepository,
        details: any CardDetailReading,
        usage: any CardUsageReading,
        priceLookup: any PriceLookup,
        history: any BanlistHistoryReading,
        provenance: any BanlistProvenanceReporting
    ) {
        self.catalog = catalog
        self.details = details
        self.usage = usage
        self.priceLookup = priceLookup
        self.history = history
        self.provenance = provenance
    }

    public func load(
        _ card: Card,
        language: CardLanguage,
        format: BanlistFormat = .tcg
    ) async -> CardDetail {
        let release = (try? await details.release(forCard: card.id)) ?? .unknown
        let konamiID = try? await details.konamiID(forCard: card.id)

        let currentStatus = (try? await catalog.banStatus(
            for: card.id, in: format.cardFormat ?? .tcg)) ?? .unlimited

        let historySection = historySection(
            for: card, konamiID: konamiID ?? nil, release: release, format: format)

        return CardDetail(
            card: card,
            language: language,
            text: card.text(in: language),
            release: release,
            printings: await printingsSection(card),
            prices: await priceLines(card),
            holdings: await holdingsSection(card),
            deckUses: await deckUseSection(card),
            currentStatus: currentStatus,
            history: historySection,
            disagreement: disagreement(
                card: card, konamiID: konamiID ?? nil,
                catalogStatus: currentStatus, history: historySection, format: format))
    }

    // MARK: - Sections

    private func printingsSection(_ card: Card) async -> DetailSection<[CardPrinting]> {
        do {
            let printings = try await details.printings(forCard: card.id)
            return printings.isEmpty
                ? .empty(reason: "Nessuna stampa registrata per questa carta.")
                : .loaded(printings)
        } catch {
            return .failed(reason: "Stampe non leggibili: \(error).")
        }
    }

    private func holdingsSection(_ card: Card) async -> DetailSection<[CardHolding]> {
        do {
            let holdings = try await usage.holdings(forCard: card.id)
            return holdings.isEmpty
                ? .empty(reason: "Non possiedi nessuna copia di questa carta.")
                : .loaded(holdings)
        } catch {
            return .failed(reason: "Collezione non leggibile: \(error).")
        }
    }

    private func deckUseSection(_ card: Card) async -> DetailSection<[DeckUse]> {
        do {
            let uses = try await usage.deckUses(forCard: card.id)
            return uses.isEmpty
                ? .empty(reason: "Nessun mazzo usa questa carta.")
                : .loaded(uses)
        } catch {
            return .failed(reason: "Mazzi non leggibili: \(error).")
        }
    }

    /// One line per source, always all five. A source with no figure says so,
    /// because leaving it out would let a partly priced card look fully priced.
    private func priceLines(_ card: Card) async -> [CardPriceLine] {
        let recorded = (try? await priceLookup.prices(forCards: [card.id]))?[card.id] ?? []
        let bySource = Dictionary(
            recorded.map { ($0.source, $0) }, uniquingKeysWith: { first, _ in first })

        return PriceSource.allCases.map { source in
            let price = bySource[source]
            return CardPriceLine(
                source: source, money: price?.money, observedAt: price?.observedAt)
        }
    }

    // MARK: - History

    private func historySection(
        for card: Card, konamiID: Int?, release: CardRelease, format: BanlistFormat
    ) -> CardHistorySection {
        guard let konamiID else {
            // 203 of 14,566 cards. Not "never restricted": unknowable.
            return .unavailable(
                reason: "Questa carta non ha un identificativo Konami, "
                    + "quindi non è collegabile alle liste pubblicate.")
        }

        do {
            let revisions = try history.revisions(for: format)
            guard !revisions.isEmpty else {
                return .unavailable(
                    reason: "Nessuna lista \(format.displayName) è ancora stata scaricata.")
            }

            let statuses = try history.statuses(forKonamiID: konamiID, format: format)
            guard !statuses.isEmpty else {
                return .neverRestricted(format: format)
            }

            return .timeline(BanlistTimelineBuilder.timeline(
                format: format,
                revisionDates: revisions.map(\.effectiveDate),
                statuses: statuses,
                releaseDate: release.date(for: format)))
        } catch {
            return .unavailable(reason: "Storico non leggibile: \(error).")
        }
    }

    /// Computed from what is already in hand rather than by scanning the whole
    /// catalog for disagreements: this panel is about one card.
    private func disagreement(
        card: Card, konamiID: Int?, catalogStatus: BanStatus,
        history section: CardHistorySection, format: BanlistFormat
    ) -> BanlistDisagreement? {
        guard let konamiID,
              let timeline = section.timelineValue,
              let newest = timeline.entries.last,
              newest.status != catalogStatus
        else { return nil }

        let source = (try? provenance.provenance(for: format))?.sources.first
            ?? "storico banlist"

        return BanlistDisagreement(
            cardID: card.id.rawValue,
            konamiID: konamiID,
            name: card.text(in: .italian).name,
            catalogStatus: catalogStatus,
            historyStatus: newest.status,
            historyEffectiveDate: newest.effectiveDate,
            historySource: source)
    }
}
