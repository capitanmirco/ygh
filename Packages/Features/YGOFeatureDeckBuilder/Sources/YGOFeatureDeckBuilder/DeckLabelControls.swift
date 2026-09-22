import SwiftUI
import YGOCore
import YGODesignSystem

/// The deck's two labels, where the deck is being worked on.
///
/// Menus and an inline field on purpose: the deck list already hosts a sheet,
/// two alerts and an exporter, and every recorded failure in this project is
/// presentations competing on one view. Nothing here presents anything.
struct DeckLabelControls: View {
    let model: DeckEditorViewModel
    @State private var newTag = ""
    @FocusState private var fieldIsFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            formatPicker
            tagChips
            addTagField
        }
    }

    private var formatPicker: some View {
        Picker("Formato", selection: Binding(
            get: { model.deck?.format ?? .tcg },
            set: { format in Task { await model.changeFormat(to: format) } })
        ) {
            ForEach(CardFormat.allCases, id: \.self) { format in
                Text(format.rawValue).tag(format)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 160)
        .disabled(!model.canLabel)
        .help("Il formato decide le restrizioni riportate su questo mazzo")
        .accessibilityLabel("Formato del mazzo")
    }

    private var tagChips: some View {
        ForEach(model.tags, id: \.self) { tag in
            HStack(spacing: Theme.Spacing.hair) {
                Text(tag).font(Theme.Typography.caption)
                Button {
                    Task { await model.removeTag(tag) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Togli l'etichetta \(tag)")
            }
            .padding(.horizontal, Theme.Spacing.tight)
            .padding(.vertical, Theme.Spacing.hair)
            .background(Theme.Palette.surface, in: Capsule())
            .accessibilityElement(children: .contain)
        }
    }

    private var addTagField: some View {
        HStack(spacing: Theme.Spacing.hair) {
            TextField("Etichetta", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 140)
                .focused($fieldIsFocused)
                .onSubmit { commit(newTag) }
                .disabled(!model.canLabel)
                .accessibilityLabel("Aggiungi un'etichetta")

            if !model.availableTags.isEmpty {
                Menu {
                    ForEach(model.availableTags, id: \.self) { tag in
                        Button(tag) { commit(tag) }
                            .disabled(model.tags.contains {
                                $0.caseInsensitiveCompare(tag) == .orderedSame
                            })
                    }
                } label: {
                    Image(systemName: "tag")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .help("Etichette già in uso")
                .accessibilityLabel("Etichette già in uso")
            }
        }
        .task { await model.loadTags() }
    }

    private func commit(_ tag: String) {
        let name = tag
        newTag = ""
        Task { await model.addTag(name) }
    }
}
