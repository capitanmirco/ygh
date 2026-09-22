import SwiftUI
import YGOCore
import YGODesignSystem

/// The deck's saved states, beside the deck.
///
/// It takes the preview's place rather than opening a sheet: this project's
/// recorded failures are all presentations competing on one view, and the
/// editor is already holding a confirmation dialog.
struct DeckHistoryPanel: View {
    let model: DeckEditorViewModel
    /// Asks the window to arm its confirmation for this version. The panel
    /// never restores by itself.
    let onRestore: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if model.versionRows.isEmpty {
                empty
            } else {
                list
            }
        }
        .background(Theme.Palette.surface)
    }

    private var header: some View {
        HStack {
            Text("Cronologia")
                .font(Theme.Typography.sectionTitle)
            Spacer()
            Button {
                Task { await model.saveVersion() }
            } label: {
                Label("Salva versione", systemImage: "clock.arrow.circlepath")
            }
            .help("Marca lo stato attuale del mazzo")
            .disabled(!model.canUseHistory)

            Button { model.hideHistory() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Chiudi la cronologia")
        }
        .padding(Theme.Spacing.snug)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            Text("Questo mazzo non ha versioni.")
                .font(Theme.Typography.body)
            Text("Una versione è uno stato del mazzo che puoi ritrovare più tardi: "
                + "salvane una prima di provare qualcosa.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(Theme.Spacing.regular)
    }

    private var list: some View {
        List(model.versionRows, selection: Binding(
            get: { model.selectedVersion },
            set: { if let id = $0 { model.selectVersion(id) } })
        ) { row in
            VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                Text(row.name).font(Theme.Typography.body)
                Text(row.isReadable ? "\(row.moment) · \(row.cardCount) carte"
                                    : "\(row.moment) · non leggibile")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            .tag(row.id)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.announcement)
            .contextMenu {
                Button("Ripristina questa versione") { onRestore(row.id) }
                    .disabled(!row.isReadable)
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var footer: some View {
        HStack {
            Button("Ripristina") {
                if let selected = model.selectedVersion { onRestore(selected) }
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!canRestoreSelection)
            Spacer()
        }
        .padding(Theme.Spacing.snug)
    }

    /// An unreadable version is listed and cannot be chosen: restoring one
    /// would empty the deck it claims to recover.
    private var canRestoreSelection: Bool {
        guard let selected = model.selectedVersion else { return false }
        return model.versionRows.first { $0.id == selected }?.isReadable ?? false
    }
}
