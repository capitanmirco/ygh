import SwiftUI
import YGOCore
import YGOValidation
import YGODesignSystem

/// The deck editor: the three sections, the cards in them, and what is wrong.
///
/// The view holds no rules. Which section a card belongs to, what a violation
/// says and where the keyboard goes are all decided in the model, so the same
/// decisions are asserted in tests without rendering anything.
public struct DeckEditorView: View {
    /// The card detail beside the deck. Supplied by the composition root,
    /// because the panel is `card-detail`'s and this screen only gives it a
    /// card and a column.
    private let preview: AnyView?

    @State private var model: DeckEditorViewModel
    @FocusState private var focus: DeckEditorFocusRegion?
    @State private var chosenSection: DeckSection = .main

    public init(model: DeckEditorViewModel, preview: AnyView? = nil) {
        _model = State(wrappedValue: model)
        self.preview = preview
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                Divider()
                HStack(spacing: 0) {
                    HSplitView {
                        cardList
                        VStack(spacing: 0) {
                            if model.canAddCards { picker; Divider() }
                            report
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // One panel beside the deck, two things it can show. A
                    // sheet would be a second presentation competing with the
                    // deletion dialog, which is how this project has already
                    // lost a rename and a deletion.
                    if model.isHistoryVisible {
                        Divider()
                        DeckHistoryPanel(model: model) { versionID in
                            model.askRestore(versionID)
                        }
                        .frame(width: Theme.Inspector.width(
                            forWindowWidth: geometry.size.width))
                    } else if let preview, model.isPreviewVisible {
                        Divider()
                        preview
                            .frame(width: Theme.Inspector.width(
                                forWindowWidth: geometry.size.width))
                    }
                }
            }
        }
        .background(Theme.Palette.surface)
        // An arrow key through the deck list is what this feature exists to
        // make useful, so the selection drives the panel.
        .onChange(of: model.selectedIndex) { _, _ in
            Task { await model.previewSelection() }
        }
        .onChange(of: model.focusedRegion) { _, region in focus = region }
        .onChange(of: focus) { _, region in
            if let region, region != model.focusedRegion { model.focusRegion(region) }
        }
        // On its own level, not stacked with the deletion dialog below:
        // presentations on one view compete and SwiftUI shows the first.
        .background {
            Color.clear
                // The version is captured while the alert is built. Tapping a
                // button dismisses it first, and the dismissal runs this
                // binding's setter, so the action would find nothing armed.
                .alert("Ripristinare questa versione?", isPresented: Binding(
                    get: { model.pendingRestore != nil },
                    set: { if !$0 { model.cancelRestore() } })
                ) {
                    let pending = model.pendingRestore
                    Button("Annulla", role: .cancel) { model.cancelRestore() }
                    Button("Ripristina", role: .destructive) {
                        guard let pending else { return }
                        Task { await model.confirmRestore(pending) }
                    }
                } message: {
                    Text("Le carte attuali del mazzo vengono sostituite. "
                        + "Lo stato che sostituisci resta recuperabile come versione.")
                }
        }
        // The deck is captured while the dialog is built rather than read
        // inside the button's action. Tapping a dialog button dismisses it
        // first, and the dismissal runs this binding's setter — so the action
        // found nothing pending and `confirmDeletion()` returned false
        // without deleting anything.
        .confirmationDialog(
            "Eliminare questo mazzo?",
            isPresented: Binding(
                get: { model.pendingDeletion != nil },
                set: { if !$0 { model.cancelDeletion() } })
        ) {
            let pending = model.pendingDeletion
            Button("Elimina", role: .destructive) {
                guard let pending else { return }
                Task {
                    // Re-assert what the user confirmed: the dismissal has
                    // already cleared it.
                    model.requestDeletion(pending)
                    await model.confirmDeletion()
                }
            }
            Button("Annulla", role: .cancel) { model.cancelDeletion() }
        } message: {
            Text("Un mazzo eliminato non può essere recuperato.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.regular) {
            if preview != nil {
                Button {
                    model.isPreviewVisible ? model.dismissPreview() : model.restorePreview()
                } label: {
                    Image(systemName: model.isPreviewVisible
                          ? "sidebar.trailing" : "sidebar.right")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("i", modifiers: .command)
                .help(model.isPreviewVisible
                      ? "Nascondi il dettaglio carta"
                      : "Mostra il dettaglio carta")
                .accessibilityLabel(model.isPreviewVisible
                                    ? "Nascondi il dettaglio carta"
                                    : "Mostra il dettaglio carta")
            }

            if model.canUseHistory {
                Button {
                    if model.isHistoryVisible {
                        model.hideHistory()
                    } else {
                        Task { await model.showHistory() }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .help(model.isHistoryVisible ? "Nascondi la cronologia" : "Mostra la cronologia")
                .accessibilityLabel(
                    model.isHistoryVisible ? "Nascondi la cronologia" : "Mostra la cronologia")
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                Text(model.deck?.name ?? "Nessun mazzo")
                    .font(Theme.Typography.sectionTitle)
                // The format is no longer a label to read: it is the control
                // that sets it, beside the deck's own words for itself.
                DeckLabelControls(model: model)
            }

            Spacer()
            sectionPicker
            legalityBadge
        }
        .padding(.horizontal, Theme.Spacing.regular)
        .padding(.vertical, Theme.Spacing.snug)
    }

    private var sectionPicker: some View {
        Picker("Sezione", selection: $chosenSection) {
            ForEach(DeckSection.allCases, id: \.self) { section in
                Text("\(section.italianName) (\(model.deck?.count(in: section) ?? 0))")
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .focused($focus, equals: .sections)
        .accessibilityLabel("Sezioni del mazzo")
    }

    @ViewBuilder
    private var legalityBadge: some View {
        if let legality = model.legality {
            HStack(spacing: Theme.Spacing.tight) {
                Image(systemName: legality.isLegal ? "checkmark.seal" : "exclamationmark.triangle")
                Text(legality.isLegal ? "Legale" : "\(legality.violations.count) problemi")
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(legality.isLegal ? Theme.Palette.secondaryText : Theme.Palette.limited)
            // A restriction the user maintains is not a published one, and the
            // interface must not let the badge imply otherwise.
            .help(legality.restrictionsAreUserMaintained
                  ? "Questo formato non ha una banlist ufficiale: le restrizioni sono quelle che hai inserito tu."
                  : "Restrizioni dalla banlist ufficiale del formato.")
        }
    }

    // MARK: - Cards

    private var cardList: some View {
        List(selection: Binding(
            get: { model.selectedItem?.id },
            set: { id in
                guard let id, let index = model.items.firstIndex(where: { $0.id == id })
                else { return }
                model.moveSelection(by: index - (model.selectedIndex ?? 0))
            })
        ) {
            ForEach(DeckSection.allCases, id: \.self) { section in
                sectionRows(section)
            }
        }
        .focused($focus, equals: .cardList)
        .accessibilityLabel("Carte del mazzo")
        .frame(minWidth: 320)
    }

    /// One section of the list, with its rows and its drop target.
    ///
    /// Split out of the list body: the whole thing in one expression was more
    /// than the type checker would take.
    @ViewBuilder
    private func sectionRows(_ section: DeckSection) -> some View {
        let entries = model.items.filter { $0.section == section }
        Section(sectionHeader(section)) {
            ForEach(entries) { item in
                row(item)
                    .draggable(DeckDragPayload.deckCard(
                        artwork: item.id, section: item.section, copies: 1))
            }
            if entries.isEmpty {
                Text("Trascina qui una carta")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
        }
        // The whole section is the drop target, empty included - which is
        // exactly when you most need to drop into it.
        .dropDestination(for: DeckDragPayload.self) { payloads, _ in
            guard let payload = payloads.first else { return false }
            Task { await model.drop(payload, on: section) }
            return true
        } isTargeted: { isTargeted in
            model.dragEntered(isTargeted ? section : nil)
        }
        .listRowBackground(dropHighlight(section))
    }

    private func dropHighlight(_ section: DeckSection) -> Color {
        model.dropTarget == section ? Theme.Palette.dropTarget : Color.clear
    }

    /// The section's name with what it holds, so the count is visible while
    /// dragging into it rather than only after.
    private func sectionHeader(_ section: DeckSection) -> String {
        "\(section.italianName) (\(model.deck?.count(in: section) ?? 0))"
    }

    private func row(_ item: DeckEntryItem) -> some View {
        HStack(spacing: Theme.Spacing.snug) {
            FrameMarker(item.frame, shape: .dot)
            Text("\(item.quantity)×")
                .font(Theme.Typography.cardSubtitle.monospacedDigit())
                .foregroundStyle(Theme.Palette.secondaryText)
            Text(item.title)
                .font(Theme.Typography.body)
            Spacer()
            if item.banStatus != .unlimited {
                Text(item.banStatus.italianName)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.limited)
            }

            // Everything the drag does, without a pointer.
            quantityStepper(item)
            moveMenu(item)
            removeButton(item)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.accessibilityLabel)
        .contextMenu {
            Button("Rimuovi una copia") {
                Task { await model.remove(artwork: item.id, from: item.section) }
            }
            Button("Rimuovi tutte le copie", role: .destructive) {
                Task { await model.setQuantity(0, of: item.id, in: item.section) }
            }
        }
    }

    /// Taking a card out was reachable only by stepping its count down to
    /// zero, which is not something an interface should expect to be guessed.
    private func removeButton(_ item: DeckEntryItem) -> some View {
        Button {
            Task { await model.remove(artwork: item.id, from: item.section) }
        } label: {
            Image(systemName: item.quantity > 1 ? "minus.circle" : "trash")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.Palette.forbidden)
        .help(item.quantity > 1
              ? "Rimuovi una copia di \(item.title)"
              : "Togli \(item.title) dal mazzo")
        .accessibilityLabel(item.quantity > 1
                            ? "Rimuovi una copia di \(item.title)"
                            : "Togli \(item.title) dal mazzo")
    }

    /// Split out of `row`: the whole row in one expression was more than the
    /// type checker would take.
    private func quantityStepper(_ item: DeckEntryItem) -> some View {
        Stepper {
            // A hidden label leaves the control unexplained; the count beside
            // it is what the buttons are changing.
            Text("\(item.quantity)")
                .font(Theme.Typography.cardSubtitle.monospacedDigit())
                .frame(minWidth: 16)
        } onIncrement: {
            Task { await model.setQuantity(item.quantity + 1, of: item.id, in: item.section) }
        } onDecrement: {
            Task { await model.setQuantity(item.quantity - 1, of: item.id, in: item.section) }
        }
        .accessibilityLabel("Copie di \(item.title)")
    }

    private func moveMenu(_ item: DeckEntryItem) -> some View {
        let targets = DeckSection.allCases.filter { $0 != item.section }
        return Menu("Sposta") {
            ForEach(targets, id: \.self) { target in
                Button(target.italianName) {
                    Task {
                        await model.move(item.id, from: item.section,
                                         to: target, copies: item.quantity)
                    }
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Sposta \(item.title) in un'altra sezione")
    }

    // MARK: - Adding cards

    /// Searching the catalog and adding what it finds. A deck builder that can
    /// only remove is not a deck builder.
    private var picker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack(spacing: Theme.Spacing.tight) {
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .accessibilityHidden(true)
                TextField("Cerca una carta da aggiungere", text: $model.catalogueQuery)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .accessibilityLabel("Cerca una carta da aggiungere al mazzo")
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
                .frame(maxHeight: 200)
            }
        }
        .padding(Theme.Spacing.regular)
    }

    private func candidateRow(_ card: Card) -> some View {
        let text = card.text(in: .italian)
        // The section is the validator's own placement rule, so a card added
        // here is never then reported for being where it was put.
        let target = DeckValidator.defaultSection(for: card.frame)

        return Button {
            Task { await model.add(card) }
        } label: {
            HStack(spacing: Theme.Spacing.tight) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text.name).font(Theme.Typography.body)
                    Text(Vocabulary.cardKind(card.humanReadableType))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                Spacer()
                Text(target.italianName)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                Image(systemName: "plus.circle")
            }
            .contentShape(Rectangle())
            .padding(.vertical, Theme.Spacing.hair)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aggiungi \(text.name) a \(target.italianName)")
    }

    // MARK: - Report

    private var report: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            Text("Controllo legalità")
                .font(Theme.Typography.sectionTitle)

            if let legality = model.legality, legality.isLegal {
                Label("Nessun problema in \(model.deck?.format.rawValue ?? "")",
                      systemImage: "checkmark.circle")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
            } else {
                // One sentence per problem, in full: a duelist fixing a list
                // wants the whole picture, not one item at a time.
                ForEach(model.violationSentences, id: \.self) { sentence in
                    Label(sentence, systemImage: "exclamationmark.circle")
                        .font(Theme.Typography.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if model.legality?.restrictionsAreUserMaintained == true {
                Text("Le restrizioni di questo formato le mantieni tu.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.regular)
        .focused($focus, equals: .violationReport)
        .accessibilityLabel("Report di legalità")
        .frame(minWidth: 280)
    }
}
