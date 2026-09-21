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
            HSplitView {
                VStack(spacing: 0) {
                    if model.canEdit { picker; Divider() }
                    if model.items.isEmpty {
                        ContentUnavailableView(
                            "Collezione vuota",
                            systemImage: "tray",
                            description: Text("Cerca una carta qui sopra per registrarla."))
                    } else {
                        ownedList
                    }
                }
                shortfallReport
            }
        }
        .background(Theme.Palette.surface)
        .task { await model.reload() }
        .confirmationDialog(
            "Rimuovere tutte le copie?",
            isPresented: Binding(
                get: { model.pendingRemoval != nil },
                set: { if !$0 { model.cancelRemoval() } })
        ) {
            Button("Rimuovi", role: .destructive) {
                Task { await model.removeConfirmedCard() }
            }
            Button("Annulla", role: .cancel) { model.cancelRemoval() }
        } message: {
            Text("Le copie registrate a mano non si recuperano riscaricando nulla.")
        }
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

    /// Searching the catalog and recording what it finds. A collection you
    /// cannot add to is a list you will not keep.
    private var picker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack(spacing: Theme.Spacing.tight) {
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .accessibilityHidden(true)
                TextField("Cerca una carta da registrare", text: $model.catalogueQuery)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .accessibilityLabel("Cerca una carta da registrare in collezione")
                    .onSubmit { Task { await model.searchCatalogue() } }
            }

            if !model.candidates.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.candidates) { card in
                            candidateRow(card)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(Theme.Spacing.regular)
    }

    private func candidateRow(_ card: Card) -> some View {
        let text = card.text(in: .italian)
        return Button {
            // Recorded against no printing: which one it is can be set later,
            // and 552 catalog cards have none at all.
            Task { await model.recordCopy(of: card.id) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text.name).font(Theme.Typography.body)
                    Text(card.humanReadableType)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                Spacer()
                Image(systemName: "plus.circle")
            }
            .contentShape(Rectangle())
            .padding(.vertical, Theme.Spacing.hair)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Registra una copia di \(text.name)")
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
                OwnedRow(
                    item: item,
                    canEdit: model.canEdit,
                    setCopies: { count in Task { await model.setCopies(count, of: item.id) } },
                    requestRemoval: { model.requestRemoval(of: item.id) })
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

/// One owned card. Extracted because a row carrying a stepper, a count and a
/// context menu grows a type SwiftUI cannot check inside a list builder.
private struct OwnedRow: View {
    let item: OwnedCardItem
    let canEdit: Bool
    let setCopies: (Int) -> Void
    let requestRemoval: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            FrameMarker(item.frame, shape: .dot)
            Text(item.name).font(Theme.Typography.body)
            Spacer()
            if canEdit {
                Stepper("", value: binding, in: 0...99)
                    .labelsHidden()
                    .fixedSize()
            }
            Text("×\(item.copies)")
                .font(Theme.Typography.cardSubtitle.monospacedDigit())
                .foregroundStyle(Theme.Palette.secondaryText)
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .contextMenu {
            if canEdit {
                Button("Rimuovi tutte le copie", role: .destructive, action: requestRemoval)
            }
        }
    }

    private var binding: Binding<Int> {
        Binding(get: { item.copies }, set: setCopies)
    }
}
