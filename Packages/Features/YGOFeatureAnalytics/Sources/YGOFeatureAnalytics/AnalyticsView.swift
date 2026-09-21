import SwiftUI
import YGOAnalytics
import YGOCore
import YGODesignSystem

/// How a deck behaves: its shape, its odds, and a hand it would really deal.
public struct AnalyticsView: View {
    @State private var model: AnalyticsViewModel
    @FocusState private var focus: AnalyticsFocusRegion?

    public init(model: AnalyticsViewModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                shape
                odds
            }
        }
        .background(Theme.Palette.surface)
        .onChange(of: model.focusedRegion) { _, region in focus = region }
        .onChange(of: focus) { _, region in
            if let region, region != model.focusedRegion { model.focusRegion(region) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.regular) {
            Picker("Turno", selection: Binding(
                get: { model.playingFirst },
                set: { model.setPlayingFirst($0) }
            )) {
                Text("Vado primo").tag(true)
                Text("Vado secondo").tag(false)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .focused($focus, equals: .playOrder)
            .accessibilityLabel("Ordine di gioco")

            if let hand = model.hand {
                // The hand size is stated rather than assumed: a GOAT deck
                // opens on six and a TCG deck on five, and that is 5.7 points.
                Text(hand.description)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }

            Spacer()

            Button("Pesca una mano") { model.dealHand() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, Theme.Spacing.regular)
        .padding(.vertical, Theme.Spacing.snug)
    }

    // MARK: - Shape

    private var shape: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                if let main = model.mainBreakdown {
                    kindCounts(main)
                    levelCurve(main)
                }
                if !model.dealtHand.isEmpty { dealtHand }
                Spacer()
            }
            .padding(Theme.Spacing.regular)
        }
        .focused($focus, equals: .breakdowns)
        .accessibilityLabel("Composizione del mazzo")
        .frame(minWidth: 300)
    }

    private func kindCounts(_ breakdown: DeckBreakdown) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text("Composizione").font(Theme.Typography.sectionTitle)
            ForEach(DeckBreakdown.Kind.allCases, id: \.self) { kind in
                let count = breakdown.byKind[kind] ?? 0
                if count > 0 {
                    HStack {
                        // The colour of the frame the category is mostly made
                        // of, so a breakdown reads like the cards it counts.
                        FrameMarker(BreakdownPalette.frame(forKind: kind.rawValue),
                                    shape: .dot)
                        Text(kind.italianName).font(Theme.Typography.body)
                        Spacer()
                        Text("\(count)")
                            .font(Theme.Typography.figure)
                            .foregroundStyle(Theme.Palette.primaryText)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(kind.italianName): \(count) carte")
                }
            }
        }
    }

    private func levelCurve(_ breakdown: DeckBreakdown) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text("Curva dei livelli").font(Theme.Typography.sectionTitle)
            let curve = breakdown.levelCurve
            let peak = curve.map(\.count).max() ?? 1

            ForEach(curve, id: \.level) { entry in
                HStack(spacing: Theme.Spacing.tight) {
                    Text("Lv \(entry.level)")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .frame(width: 44, alignment: .leading)
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: Theme.Radius.control)
                            .fill(Theme.Palette.chartFill)
                            .frame(width: geometry.size.width
                                   * CGFloat(entry.count) / CGFloat(peak))
                    }
                    .frame(height: 14)
                    Text("\(entry.count)")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .frame(width: 24, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Livello \(entry.level): \(entry.count) carte")
            }
        }
    }

    private var dealtHand: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text("Una mano possibile").font(Theme.Typography.sectionTitle)
            ForEach(Array(model.dealtHand.enumerated()), id: \.offset) { _, name in
                Text(name).font(Theme.Typography.body)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mano pescata: \(model.dealtHand.joined(separator: ", "))")
    }

    // MARK: - Odds

    private var odds: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding(
                get: { model.selectedOdds?.card },
                set: { card in
                    guard let card,
                          let index = model.odds.firstIndex(where: { $0.card == card })
                    else { return }
                    model.moveSelection(by: index - (model.selectedIndex ?? 0))
                })
            ) {
                ForEach(model.odds, id: \.card) { entry in
                    HStack {
                        Text(entry.cardName).font(Theme.Typography.body)
                        Spacer()
                        Text(String(format: "%.1f%%", entry.atLeastOne * 100))
                            .font(Theme.Typography.figure)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(entry.sentence)
                }
            }
            .focused($focus, equals: .cardList)
            .accessibilityLabel("Probabilità di apertura per carta")

            Divider()
            copyTable
        }
        .frame(minWidth: 320)
    }

    @ViewBuilder
    private var copyTable: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            if let table = model.table {
                Text("Quante copie di \(table.cardName)")
                    .font(Theme.Typography.sectionTitle)
                // Three rows rather than one figure, because the question is
                // a decision and one number does not answer it.
                ForEach(table.rows, id: \.copies) { row in
                    Text(row.sentence)
                        .font(Theme.Typography.body)
                        .accessibilityLabel(row.sentence)
                }
            } else {
                Text("Scegli una carta per vedere cosa cambia con più copie.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.regular)
        .focused($focus, equals: .probabilityTable)
        .accessibilityLabel("Tabella delle copie")
    }
}
