import SwiftUI
import YGOCore
import YGODesignSystem

/// What the user owns, and what a deck still needs.
///
/// The view holds no policy: totals, sentences and focus order are all decided
/// in the model, which is why each can be asserted without rendering anything.
public struct CollectionView: View {
    @State private var model: CollectionViewModel
    @FocusState private var focus: CollectionFocusRegion?

    public init(model: CollectionViewModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.items.isEmpty {
                ContentUnavailableView(
                    "Collezione vuota",
                    systemImage: "tray",
                    description: Text("Registra le carte che possiedi per sapere cosa ti manca."))
            } else {
                HSplitView {
                    ownedList
                    shortfallReport
                }
            }
        }
        .background(Theme.Palette.surface)
        .task { await model.reload() }
        .onChange(of: model.focusedRegion) { _, region in focus = region }
        .onChange(of: focus) { _, region in
            if let region, region != model.focusedRegion { model.focusRegion(region) }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.regular) {
            HStack(spacing: Theme.Spacing.tight) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .accessibilityHidden(true)
                TextField("Cerca nella collezione", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .focused($focus, equals: .search)
                    .accessibilityLabel("Cerca fra le carte possedute")
                    .onSubmit { Task { await model.reload() } }
            }

            Spacer()

            if let totals = model.totals {
                HStack(spacing: Theme.Spacing.regular) {
                    stat("\(totals.distinctCards)", "carte")
                    stat("\(totals.totalCopies)", "copie")
                    if totals.recordedSpend > 0 {
                        // A sum of what was entered, not a valuation: most
                        // collections are partly inherited or traded.
                        stat(String(format: "%.0f €", totals.recordedSpend), "registrati")
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.regular)
        .padding(.vertical, Theme.Spacing.snug)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(Theme.Typography.sectionTitle.monospacedDigit())
            Text(label).font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    private var ownedList: some View {
        List(selection: Binding(
            get: { model.selectedItem?.id },
            set: { id in
                guard let id, let index = model.items.firstIndex(where: { $0.id == id })
                else { return }
                model.moveSelection(by: index - (model.selectedIndex ?? 0))
            })
        ) {
            ForEach(model.items) { item in
                HStack {
                    Text(item.name).font(Theme.Typography.body)
                    Spacer()
                    Text("×\(item.copies)")
                        .font(Theme.Typography.cardSubtitle.monospacedDigit())
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.accessibilityLabel)
            }
        }
        .focused($focus, equals: .ownedList)
        .accessibilityLabel("Carte possedute")
        .frame(minWidth: 300)
    }

    @ViewBuilder
    private var shortfallReport: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            Text("Cosa manca").font(Theme.Typography.sectionTitle)

            if model.shortfall.isEmpty {
                Label("Niente da comprare per questo mazzo", systemImage: "checkmark.circle")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
            } else {
                // Worst shortfall first, so the list reads as a shopping order.
                ForEach(model.shortfallSentences, id: \.self) { sentence in
                    Label(sentence, systemImage: "cart")
                        .font(Theme.Typography.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.regular)
        .focused($focus, equals: .shortfall)
        .accessibilityLabel("Cosa manca per il mazzo scelto")
        .frame(minWidth: 300)
    }
}
