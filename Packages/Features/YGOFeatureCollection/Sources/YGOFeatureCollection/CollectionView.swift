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
    /// The deck already chosen elsewhere in the window, where the "Cosa manca"
    /// report starts. Nil starts it on a request to choose one.
    private let startingDeck: Int64?

    public init(model: CollectionViewModel, startingDeck: Int64? = nil) {
        _model = State(wrappedValue: model)
        self.startingDeck = startingDeck
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
        .task {
            await model.startShortfall(on: startingDeck)
            await model.reload()
        }
        // The card is captured while the dialog is built rather than read
        // inside the button's action. Tapping a dialog button dismisses it
        // first, and the dismissal runs this binding's setter — so the action
        // found nothing pending and `removeConfirmedCard()` returned without
        // removing anything. The same trap the deck deletions already paid for.
        .confirmationDialog(
            "Rimuovere tutte le copie?",
            isPresented: Binding(
                get: { model.pendingRemoval != nil },
                set: { if !$0 { model.cancelRemoval() } })
        ) {
            let pending = model.pendingRemoval
            Button("Rimuovi", role: .destructive) {
                guard let pending else { return }
                Task {
                    // Re-assert what the user confirmed: the dismissal has
                    // already cleared it.
                    model.requestRemoval(of: pending)
                    await model.removeConfirmedCard()
                }
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
                    Text(Vocabulary.cardKind(card.humanReadableType))
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

    /// Which deck, then what the model knows about it. The panel draws the
    /// report and decides nothing: an empty list used to be drawn here as
    /// "nothing to buy", with no deck chosen at all.
    @ViewBuilder
    private var shortfallReport: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            Text("Cosa manca").font(Theme.Typography.sectionTitle)

            if model.canChooseShortfallDeck { shortfallDeckMenu }

            Label(model.shortfallReport.headline, systemImage: headlineSymbol)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            // Worst shortfall first, so the list reads as a shopping order. A
            // real deck can miss fifty cards, so the list scrolls.
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    ForEach(model.shortfall) { entry in
                        Label(entry.sentence, systemImage: "cart")
                            .font(Theme.Typography.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.regular)
        .focused($focus, equals: .shortfall)
        .accessibilityLabel("Cosa manca per il mazzo scelto")
        .frame(minWidth: 300)
    }
}

extension CollectionView {
    /// A menu rather than a picker or a sheet: it presents nothing, so it
    /// cannot compete with the removal dialog for the one presentation SwiftUI
    /// shows — and it is how the statistics screen chooses its deck too.
    fileprivate var shortfallDeckMenu: some View {
        Menu {
            ForEach(model.decks) { deck in
                Button("\(deck.name) · \(deck.format.rawValue)") {
                    Task { await model.chooseShortfallDeck(deck.id) }
                }
            }
        } label: {
            Label(model.chosenShortfallDeck?.name ?? "Scegli un mazzo",
                  systemImage: "rectangle.stack")
        }
        .disabled(model.decks.isEmpty)
        .accessibilityLabel("Mazzo confrontato con la collezione")
        .accessibilityValue(model.chosenShortfallDeck?.name ?? "nessuno")
    }

    fileprivate var headlineSymbol: String {
        switch model.shortfallReport {
        case .noDecks: "tray"
        case .chooseADeck: "rectangle.stack"
        case .unavailable: "exclamationmark.triangle"
        case .satisfied: "checkmark.circle"
        case .missing: "cart"
        }
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
