import SwiftUI
import YGOCore
import YGODesignSystem

/// A Forbidden & Limited List, read as a list.
public struct BanlistBrowserView: View {
    @State private var model: BanlistBrowserViewModel
    private let preview: AnyView?
    private let onSynchronise: (() -> Void)?

    public init(
        model: BanlistBrowserViewModel,
        preview: AnyView? = nil,
        onSynchronise: (() -> Void)? = nil
    ) {
        _model = State(wrappedValue: model)
        self.preview = preview
        self.onSynchronise = onSynchronise
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                Divider()
                HStack(spacing: 0) {
                    content.frame(maxWidth: .infinity)
                    if let preview, model.previewCard != nil || model.previewFailure != nil {
                        Divider()
                        preview.frame(width: Theme.Inspector.width(
                            forWindowWidth: geometry.size.width))
                    }
                }
            }
        }
        .background(Theme.Palette.surface)
        .task { await model.load() }
    }

    // MARK: - Choosing

    private var header: some View {
        HStack(spacing: Theme.Spacing.regular) {
            Picker("Formato", selection: Binding(
                get: { model.format },
                set: { value in Task { await model.load(format: value) } })) {
                ForEach(BanlistFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .frame(width: 180)

            if !model.hasNoStoredLists {
                Picker("Lista", selection: Binding(
                    get: { model.selectedDate },
                    set: { date in
                        if let date { Task { await model.select(date) } }
                    })) {
                    ForEach(model.availableLists, id: \.effectiveDate) { revision in
                        Text(model.label(for: revision.effectiveDate))
                            .tag(String?.some(revision.effectiveDate))
                    }
                }
                .frame(width: 280)
            }

            Spacer()

            Text(model.heading)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .padding(Theme.Spacing.regular)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lista mostrata: \(model.heading)")
    }

    // MARK: - Reading

    @ViewBuilder
    private var content: some View {
        if model.hasNoStoredLists {
            ContentUnavailableView {
                Label("Nessuna lista scaricata", systemImage: "arrow.down.circle")
            } description: {
                Text("Le liste pubblicate non sono ancora state scaricate.")
            } actions: {
                if let onSynchronise {
                    Button("Scarica le banlist", action: onSynchronise)
                }
            }
        } else {
            List {
                ForEach(model.groups) { group in
                    Section(header: groupHeader(group)) {
                        ForEach(group.cards, id: \.konamiID) { card in
                            row(card)
                        }
                        if group.cards.isEmpty {
                            Text("Nessuna carta in questo gruppo")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.secondaryText)
                        }
                    }
                }

                if model.unmatched > 0 {
                    // Counted rather than listed: a row reading an identifier
                    // among card names is noise.
                    Section {
                        Text("\(model.unmatched) carte della lista non sono nel catalogo")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                }
            }
        }
    }

    private func groupHeader(_ group: BanlistGroup) -> some View {
        HStack {
            Text(group.italianName).font(Theme.Typography.sectionTitle)
            Text("\(group.count)")
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.italianName): \(group.count) carte")
    }

    private func row(_ card: BanlistListEntry) -> some View {
        Button {
            Task { await model.preview(card) }
        } label: {
            HStack(spacing: Theme.Spacing.snug) {
                if let frame = card.frame {
                    FrameMarker(frame, shape: .dot)
                }
                Text(card.displayName).font(Theme.Typography.body)
                Spacer()
                if let frame = card.frame {
                    Text(frame.italianName)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BanlistListing.description(of: card))
        .accessibilityAddTraits(.isButton)
    }
}
