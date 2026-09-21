import SwiftUI
import YGOCore
import YGODesignSystem

/// The card browser: a search field, a filter strip, and a grid of cards.
///
/// The view holds no policy. Language resolution, artwork fallback, focus order
/// and selection all live in the model, so what is drawn here is already
/// decided and can be asserted without rendering.
public struct BrowserView: View {
    @State private var model: BrowserViewModel
    @FocusState private var focus: BrowserFocusRegion?

    public init(model: BrowserViewModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBar
            resultSummary
            Divider()
            content
        }
        .background(Theme.Palette.surface)
        // The catalog opens showing cards. Waiting for a query would withhold
        // something an unnarrowed search already pays for in 3.9 ms.
        .task { await model.start() }
        .onChange(of: model.queryText) { _, _ in
            Task { await model.queryChanged() }
        }
        .onChange(of: model.focusedRegion) { _, region in focus = region }
        .onChange(of: focus) { _, region in
            if let region, region != model.focusedRegion { model.focusRegion(region) }
        }
    }

    // MARK: - Search

    /// Two numbers, not one: how many cards match, and how many of them the
    /// grid is holding. Showing 200 of 14,566 without saying so would read as
    /// a catalog of 200.
    @ViewBuilder
    private var resultSummary: some View {
        if case .results = model.state {
            HStack {
                Text(model.shownCount < model.matchCount
                     ? "\(model.matchCount) carte · mostrate \(model.shownCount)"
                     : "\(model.matchCount) carte")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.regular)
            .padding(.bottom, Theme.Spacing.snug)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(model.matchCount) carte corrispondono, \(model.shownCount) mostrate")
        }
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.snug) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Palette.secondaryText)
                .accessibilityHidden(true)

            TextField("Cerca una carta", text: $model.queryText)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .focused($focus, equals: .searchField)
                .accessibilityLabel("Campo di ricerca carte")
                .onSubmit { Task { await model.search() } }

            languagePicker
        }
        .padding(.horizontal, Theme.Spacing.regular)
        .padding(.vertical, Theme.Spacing.snug)
    }

    private var languagePicker: some View {
        Picker("Lingua", selection: Binding(
            get: { model.language },
            set: { model.setLanguage($0) }
        )) {
            Text("Italiano").tag(CardLanguage.italian)
            Text("English").tag(CardLanguage.english)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .focused($focus, equals: .filters)
        .accessibilityLabel("Lingua delle carte")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            message("Cerca una carta per iniziare")
        case .searching:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Ricerca in corso")
        case .noMatches:
            // Distinct from the progress state above, so an empty grid is never
            // mistaken for one that is still filling.
            message("Nessuna carta corrisponde ai filtri")
        case .results(let items):
            grid(items)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grid(_ items: [CardGridItem]) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(
                    .adaptive(minimum: Theme.Grid.minimumTileWidth),
                    spacing: Theme.Grid.spacing)],
                spacing: Theme.Grid.spacing
            ) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    CardTile(item: item, isSelected: model.selectedIndex == index)
                        .onTapGesture { model.moveSelection(by: index - (model.selectedIndex ?? 0)) }
                }
            }
            .padding(Theme.Spacing.regular)

            if model.canShowMore {
                Button("Mostra altre \(BrowserViewModel.batchSize)") {
                    Task { await model.showMore() }
                }
                .buttonStyle(.link)
                .font(Theme.Typography.body)
                .padding(.bottom, Theme.Spacing.regular)
                .accessibilityHint("Aggiunge le carte successive a quelle gi\u{00e0} mostrate")
            }
        }
        .focused($focus, equals: .grid)
        .accessibilityLabel("Griglia carte, \(items.count) risultati")
        .onMoveCommand { direction in
            switch direction {
            case .left: model.moveSelection(by: -1)
            case .right: model.moveSelection(by: 1)
            case .up: model.moveSelection(by: -columnsHint)
            case .down: model.moveSelection(by: columnsHint)
            @unknown default: break
            }
        }
    }

    /// The grid is adaptive, so the row width is not known here. Six is a
    /// reasonable step for vertical arrow movement at a typical window size.
    private var columnsHint: Int { 6 }
}

/// One card in the grid.
struct CardTile: View {
    let item: CardGridItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            artwork
                .aspectRatio(Theme.Grid.cardAspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay(alignment: .topTrailing) { restrictionBadge }

            Text(item.title)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(2)

            Text(item.subtitle)
                .font(Theme.Typography.cardSubtitle)
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
        }
        .padding(Theme.Spacing.tight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(isSelected ? Theme.Palette.accent.opacity(0.18) : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(isSelected ? Theme.Palette.accent : .clear, lineWidth: 2))
        // One element per card, so the grid is read card by card rather than
        // label by label.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var artwork: some View {
        switch item.artwork {
        case .stored(let path):
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable()
            } else {
                placeholder
            }
        case .placeholder:
            placeholder
        }
    }

    /// A card whose image has not arrived is still identifiable, which is what
    /// keeps the grid usable before the prefetch has finished or offline.
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card)
            .fill(Theme.Palette.raisedSurface)
            .overlay {
                Text(item.title)
                    .font(Theme.Typography.cardSubtitle)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Spacing.tight)
            }
    }

    @ViewBuilder
    private var restrictionBadge: some View {
        if item.banStatus != .unlimited {
            Text(badgeText)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.tight)
                .padding(.vertical, Theme.Spacing.hair)
                .background(Capsule().fill(badgeColour))
                .padding(Theme.Spacing.tight)
                // Already spoken as part of the tile's own label.
                .accessibilityHidden(true)
        }
    }

    private var badgeText: String {
        switch item.banStatus {
        case .forbidden: "0"
        case .limited: "1"
        case .semiLimited: "2"
        case .unlimited: ""
        }
    }

    private var badgeColour: Color {
        switch item.banStatus {
        case .forbidden: Theme.Palette.forbidden
        case .limited: Theme.Palette.limited
        case .semiLimited: Theme.Palette.semiLimited
        case .unlimited: .clear
        }
    }
}
