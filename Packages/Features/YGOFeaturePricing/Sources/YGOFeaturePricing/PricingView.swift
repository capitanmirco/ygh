import SwiftUI
import YGOCore
import YGODesignSystem
import YGOPricing

/// What a collection is worth, and how much to trust the figure.
public struct PricingView: View {
    @State private var model: PricingViewModel
    @FocusState private var focus: PricingFocusRegion?

    public init(model: PricingViewModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.collectionValue == nil {
                ContentUnavailableView(
                    "Niente da valutare",
                    systemImage: "eurosign.circle",
                    description: Text("Registra qualche carta in collezione."))
            } else {
                HSplitView { totals; ranking }
            }
        }
        .background(Theme.Palette.surface)
        .onChange(of: model.focusedRegion) { _, region in focus = region }
        .onChange(of: focus) { _, region in
            if let region, region != model.focusedRegion { model.focusRegion(region) }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.regular) {
            Picker("Fonte", selection: Binding(
                get: { model.source },
                set: { source in Task { await model.setSource(source) } }
            )) {
                ForEach(PriceSource.allCases, id: \.self) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .fixedSize()
            .focused($focus, equals: .sourcePicker)
            .accessibilityLabel("Fonte dei prezzi")

            // Two of the five publish what sellers ask, not what cards change
            // hands for. Saying so beside the picker is cheaper than a user
            // discovering it from a wrong total.
            if model.source.carriesAskingPrices {
                Label("Prezzi richiesti, non di mercato", systemImage: "exclamationmark.triangle")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.limited)
            }

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.regular)
        .padding(.vertical, Theme.Spacing.snug)
    }

    private var totals: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                if let value = model.collectionValue {
                    headline(value)
                    breakdown("Per rarità", model.valueByRarity)
                    breakdown("Per posizione", model.valueByLocation)
                }
                Spacer()
            }
            .padding(Theme.Spacing.regular)
        }
        .focused($focus, equals: .totals)
        .accessibilityLabel("Valore della collezione")
        .frame(minWidth: 300)
    }

    private func headline(_ value: Valuation) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(value.total.formatted)
                .font(.system(size: 34, weight: .semibold).monospacedDigit())

            if let gain = model.gainOverSpend, let spend = model.recordedSpend {
                Text("Speso \(spend.formatted), differenza \(gain.formatted)")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }

            // The qualifications travel with the figure rather than being
            // left to whoever draws it.
            Text(value.sentence)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(value.estimateReason)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.sentence)
    }

    private func breakdown(_ title: String, _ parts: [String?: Valuation]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(title).font(Theme.Typography.sectionTitle)
            ForEach(parts.sorted { ($0.value.total.cents) > ($1.value.total.cents) },
                    id: \.key) { key, value in
                HStack {
                    Text(key ?? "Non specificato").font(Theme.Typography.body)
                    Spacer()
                    Text(value.total.formatted)
                        .font(Theme.Typography.body.monospacedDigit())
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(key ?? "Non specificato"): \(value.total.formatted)")
            }
        }
    }

    private var ranking: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Le più preziose")
                .font(Theme.Typography.sectionTitle)
                .padding(Theme.Spacing.regular)

            List(selection: Binding(
                get: { model.selectedCard?.card },
                set: { card in
                    guard let card,
                          let index = model.mostValuable.firstIndex(where: { $0.card == card })
                    else { return }
                    model.moveSelection(by: index - (model.selectedIndex ?? 0))
                })
            ) {
                ForEach(model.mostValuable) { card in
                    HStack(spacing: Theme.Spacing.tight) {
                        Text("\(card.copies)×")
                            .font(Theme.Typography.caption.monospacedDigit())
                            .foregroundStyle(Theme.Palette.secondaryText)
                        Text(card.cardName).font(Theme.Typography.body)
                        if card.isDisputed {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.Palette.limited)
                        }
                        Spacer()
                        Text(card.totalValue.formatted)
                            .font(Theme.Typography.body.monospacedDigit())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(card.sentence)
                }
            }
            .focused($focus, equals: .mostValuable)
            .accessibilityLabel("Carte più preziose")
        }
        .frame(minWidth: 320)
    }
}
