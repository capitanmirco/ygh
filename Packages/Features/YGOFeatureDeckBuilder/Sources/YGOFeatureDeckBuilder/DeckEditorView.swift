import SwiftUI
import YGOCore
import YGODesignSystem

/// The deck editor: the three sections, the cards in them, and what is wrong.
///
/// The view holds no rules. Which section a card belongs to, what a violation
/// says and where the keyboard goes are all decided in the model, so the same
/// decisions are asserted in tests without rendering anything.
public struct DeckEditorView: View {
    @State private var model: DeckEditorViewModel
    @FocusState private var focus: DeckEditorFocusRegion?
    @State private var chosenSection: DeckSection = .main

    public init(model: DeckEditorViewModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                cardList
                report
            }
        }
        .background(Theme.Palette.surface)
        .onChange(of: model.focusedRegion) { _, region in focus = region }
        .onChange(of: focus) { _, region in
            if let region, region != model.focusedRegion { model.focusRegion(region) }
        }
        .confirmationDialog(
            "Eliminare questo mazzo?",
            isPresented: Binding(
                get: { model.pendingDeletion != nil },
                set: { if !$0 { model.cancelDeletion() } })
        ) {
            Button("Elimina", role: .destructive) { Task { await model.confirmDeletion() } }
            Button("Annulla", role: .cancel) { model.cancelDeletion() }
        } message: {
            Text("Un mazzo eliminato non può essere recuperato.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.regular) {
            VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                Text(model.deck?.name ?? "Nessun mazzo")
                    .font(Theme.Typography.sectionTitle)
                Text(model.deck?.format.rawValue ?? "—")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
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
                let entries = model.items.filter { $0.section == section }
                if !entries.isEmpty {
                    Section(section.italianName) {
                        ForEach(entries) { item in
                            row(item)
                        }
                    }
                }
            }
        }
        .focused($focus, equals: .cardList)
        .accessibilityLabel("Carte del mazzo")
        .frame(minWidth: 320)
    }

    private func row(_ item: DeckEntryItem) -> some View {
        HStack(spacing: Theme.Spacing.snug) {
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
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
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
