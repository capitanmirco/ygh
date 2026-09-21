import SwiftUI
import YGOBanlistHistory
import YGOCore
import YGODesignSystem

/// The inspector beside the results.
public struct CardDetailView: View {
    @State private var model: CardDetailViewModel

    public init(model: CardDetailViewModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        Group {
            if let detail = model.detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
                        header(detail)
                        artworkChooser
                        effect(detail)
                        releaseRow(detail)
                        historySection(detail)
                        printingsSection(detail)
                        pricesSection(detail)
                        holdingsSection(detail)
                        deckSection(detail)
                    }
                    .padding(Theme.Spacing.regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Seleziona una carta per vederne il dettaglio")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.Palette.surface)
    }

    // MARK: - Identity

    @ViewBuilder
    private func header(_ detail: CardDetail) -> some View {
        artworkImage(detail)

        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(detail.text.name)
                .font(Theme.Typography.screenTitle)
                .accessibilityLabel("Carta \(detail.text.name)")
            HStack(spacing: Theme.Spacing.tight) {
                // The same colour the grid tile carried, so a card looks like
                // itself wherever it appears.
                FrameMarker(detail.card.frame, shape: .dot)
                Text(Vocabulary.cardKind(detail.card.humanReadableType))
            }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
            if detail.isUntranslated {
                Text("Testo non tradotto: mostrato in inglese")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func artworkImage(_ detail: CardDetail) -> some View {
        switch model.artwork {
        case .stored(let path):
            AsyncImage(url: URL(filePath: path)) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                ProgressView()
            }
            .frame(maxWidth: 320)
            .accessibilityLabel("Illustrazione di \(detail.text.name)")
        case .placeholder, .none:
            // A placeholder carries the card's name, which is what makes a
            // missing image an identifiable element rather than a blank one.
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.Palette.raisedSurface)
                .frame(maxWidth: 320, minHeight: 200)
                .overlay(Text(detail.text.name)
                    .font(Theme.Typography.caption)
                    .padding(Theme.Spacing.snug))
                .accessibilityLabel("Illustrazione non disponibile per \(detail.text.name)")
        }
    }

    @ViewBuilder
    private var artworkChooser: some View {
        if model.offersArtworkChooser {
            HStack(spacing: Theme.Spacing.tight) {
                ForEach(Array(model.artworkChoices.enumerated()), id: \.element) { index, _ in
                    Button("\(index + 1)") {
                        Task { await model.showArtwork(at: index) }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Illustrazione \(index + 1) di \(model.artworkChoices.count)")
                }
            }
        }
    }

    @ViewBuilder
    private func effect(_ detail: CardDetail) -> some View {
        section("Effetto") {
            Text(detail.text.effect)
                .font(Theme.Typography.body)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func releaseRow(_ detail: CardDetail) -> some View {
        section("Uscita") {
            switch detail.release {
            case .unknown:
                Text("Data di uscita sconosciuta")
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .accessibilityLabel("Data di uscita sconosciuta")
            case let .known(tcg, ocg):
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    if let tcg { Text("TCG: \(tcg)").accessibilityLabel("Uscita TCG \(tcg)") }
                    if let ocg { Text("OCG: \(ocg)").accessibilityLabel("Uscita OCG \(ocg)") }
                }
                .font(Theme.Typography.body)
            }
        }
    }

    // MARK: - History

    @ViewBuilder
    private func historySection(_ detail: CardDetail) -> some View {
        section("Banlist") {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text("Stato attuale: \(statusName(detail.currentStatus))")
                    .accessibilityLabel("Stato attuale \(statusName(detail.currentStatus))")

                switch detail.history {
                case .neverRestricted:
                    Text("Mai limitata in questo formato")
                        .foregroundStyle(Theme.Palette.secondaryText)
                case .unavailable(let reason):
                    Text("Storico non disponibile. \(reason)")
                        .foregroundStyle(Theme.Palette.secondaryText)
                case .timeline:
                    let changes = detail.history.changes
                    if changes.isEmpty {
                        Text("Nessun cambiamento registrato")
                            .foregroundStyle(Theme.Palette.secondaryText)
                    } else {
                        ForEach(changes, id: \.self) { change in
                            Text("\(change.effectiveDate): da \(statusName(change.from)) a \(statusName(change.to))")
                                .accessibilityLabel(CardDetailNarration.change(
                                    BanlistChangeNarration(
                                        date: change.effectiveDate,
                                        from: change.from, to: change.to)))
                        }
                    }
                }

                if let disagreement = detail.disagreement {
                    Text("Le due fonti non concordano: il catalogo dice "
                         + "\(statusName(disagreement.catalogStatus)), "
                         + "\(disagreement.historySource) dice "
                         + "\(statusName(disagreement.historyStatus)) "
                         + "dal \(disagreement.historyEffectiveDate).")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }
            .font(Theme.Typography.body)
        }
    }

    private func statusName(_ status: BanStatus) -> String {
        CardDetailNarration.status(status)
    }

    // MARK: - Printings, prices, copies

    @ViewBuilder
    private func printingsSection(_ detail: CardDetail) -> some View {
        section("Stampe") {
            switch detail.printings {
            case .loaded(let printings):
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    ForEach(printings, id: \.setCode) { printing in
                        Text("\(printing.setName) · \(printing.setCode) · \(printing.rarity)")
                            .accessibilityLabel(CardDetailNarration.printing(printing))
                    }
                }
                .font(Theme.Typography.body)
            case .empty(let reason), .failed(let reason):
                Text(reason).foregroundStyle(Theme.Palette.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func pricesSection(_ detail: CardDetail) -> some View {
        section("Prezzi") {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                ForEach(detail.prices, id: \.source) { line in
                    Text(priceSentence(line))
                        .accessibilityLabel(priceSentence(line))
                }
                if let observed = detail.pricesObservedAt {
                    Text("Rilevati il \(observed.formatted(date: .abbreviated, time: .shortened))")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                Text(CardDetail.priceScopeNotice)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            .font(Theme.Typography.body)
        }
    }

    private func priceSentence(_ line: CardPriceLine) -> String {
        CardDetailNarration.price(line)
    }

    @ViewBuilder
    private func holdingsSection(_ detail: CardDetail) -> some View {
        section("Le tue copie") {
            switch detail.holdings {
            case .loaded(let holdings):
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    ForEach(holdings, id: \.self) { holding in
                        Text("\(holding.quantity)× in \(holding.locationName)")
                            .accessibilityLabel(CardDetailNarration.holding(holding))
                    }
                }
                .font(Theme.Typography.body)
            case .empty(let reason), .failed(let reason):
                Text(reason).foregroundStyle(Theme.Palette.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func deckSection(_ detail: CardDetail) -> some View {
        section("Nei tuoi mazzi") {
            switch detail.deckUses {
            case .loaded(let uses):
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    ForEach(uses, id: \.self) { use in
                        Text("\(use.deckName) · \(sectionName(use.section)) · \(use.quantity)×")
                            .accessibilityLabel(CardDetailNarration.deckUse(use))
                    }
                }
                .font(Theme.Typography.body)
            case .empty(let reason), .failed(let reason):
                Text(reason).foregroundStyle(Theme.Palette.secondaryText)
            }
        }
    }

    private func sectionName(_ section: DeckSection) -> String {
        CardDetailNarration.sectionName(section)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
