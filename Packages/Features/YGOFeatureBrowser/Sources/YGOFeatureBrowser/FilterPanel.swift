import SwiftUI
import YGOCore
import YGODesignSystem

/// The filters, beside the grid rather than over it.
public struct FilterPanel: View {
    @Bindable private var panel: FilterPanelModel
    @Bindable private var browser: BrowserViewModel

    public init(panel: FilterPanelModel, browser: BrowserViewModel) {
        self.panel = panel
        self.browser = browser
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
                appliedSummary
                cardTypeSection
                attributeSection
                levelSection
                vocabularySection
                statsSection
                eraSection
                formatSection
                publishedListSection
                ownedSection
            }
            .padding(Theme.Spacing.regular)
        }
        .frame(width: 260)
        .background(Theme.Elevation.raised)
        .task { await panel.load() }
    }

    // MARK: - What is applied

    @ViewBuilder
    private var appliedSummary: some View {
        if browser.hasFilters {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                ForEach(browser.appliedFilters, id: \.self) { applied in
                    Text(applied)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                Button("Azzera i filtri") { Task { await browser.clearFilters() } }
                    .buttonStyle(.link)
                    .font(Theme.Typography.caption)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Filtri attivi: \(browser.appliedFilters.joined(separator: ", "))")
        }
    }

    // MARK: - Sections

    private func section<Content: View>(
        _ region: FilterPanelModel.Region, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(region.title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(region.title)
    }

    private var cardTypeSection: some View {
        section(.cardType) {
            ForEach(CardType.allCases, id: \.self) { type in
                Toggle(type.italianName.capitalized, isOn: binding(for: type))
                    .toggleStyle(.checkbox)
            }
        }
    }

    private func binding(for type: CardType) -> Binding<Bool> {
        Binding(
            get: { browser.filters.cardTypes.contains(type) },
            set: { isOn in
                var filters = browser.filters
                if isOn { filters.cardTypes.insert(type) } else { filters.cardTypes.remove(type) }
                apply(filters)
            })
    }

    private var attributeSection: some View {
        section(.attribute) {
            ForEach(CardAttribute.allCases, id: \.self) { attribute in
                Toggle(attribute.rawValue, isOn: Binding(
                    get: { browser.filters.attributes.contains(attribute) },
                    set: { isOn in
                        var filters = browser.filters
                        if isOn { filters.attributes.insert(attribute) }
                        else { filters.attributes.remove(attribute) }
                        apply(filters)
                    }))
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var levelSection: some View {
        section(.level) {
            rangeRow(
                lower: browser.filters.levels?.lowerBound,
                upper: browser.filters.levels?.upperBound,
                bounds: 0...13) { low, high in
                    var filters = browser.filters
                    filters.levels = low.map { $0...(high ?? $0) }
                    apply(filters)
                }
        }
    }

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
            section(.monsterType) {
                completionField(
                    "Cerca un tipo", query: $panel.monsterTypeQuery,
                    suggestions: panel.monsterTypeSuggestions,
                    chosen: browser.filters.races) { value in
                        var filters = browser.filters
                        if filters.races.contains(value) { filters.races.remove(value) }
                        else { filters.races.insert(value) }
                        apply(filters)
                    }
            }
            section(.archetype) {
                completionField(
                    "Cerca un archetipo", query: $panel.archetypeQuery,
                    suggestions: panel.archetypeSuggestions,
                    chosen: browser.filters.archetypes) { value in
                        var filters = browser.filters
                        if filters.archetypes.contains(value) { filters.archetypes.remove(value) }
                        else { filters.archetypes.insert(value) }
                        apply(filters)
                    }
            }
        }
    }

    private var statsSection: some View {
        section(.stats) {
            Toggle("Attacco o difesa \"?\"", isOn: Binding(
                get: { browser.filters.unknownStatsOnly },
                set: { isOn in
                    var filters = browser.filters
                    filters.unknownStatsOnly = isOn
                    apply(filters)
                }))
                .toggleStyle(.checkbox)
            rangeRow(
                lower: browser.filters.attack?.lowerBound,
                upper: browser.filters.attack?.upperBound,
                bounds: 0...5000) { low, high in
                    var filters = browser.filters
                    filters.attack = low.map { $0...(high ?? 5000) }
                    apply(filters)
                }
        }
    }

    private var eraSection: some View {
        section(.era) {
            rangeRow(
                lower: browser.filters.releaseYears?.lowerBound,
                upper: browser.filters.releaseYears?.upperBound,
                bounds: 1999...2030) { low, high in
                    var filters = browser.filters
                    filters.releaseYears = low.map { $0...(high ?? $0) }
                    apply(filters)
                }
            if browser.excludedUndated > 0 {
                Text("\(browser.excludedUndated) carte senza data sono escluse")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
        }
    }

    private var formatSection: some View {
        section(.format) {
            Picker("Formato", selection: Binding(
                get: { browser.filters.format },
                set: { value in
                    var filters = browser.filters
                    filters.format = value
                    apply(filters)
                })) {
                Text("Tutti").tag(CardFormat?.none)
                ForEach(CardFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(CardFormat?.some(format))
                }
            }
            .labelsHidden()
        }
    }

    private var publishedListSection: some View {
        section(.publishedList) {
            let lists = browser.availableLists(for: .tcg)
            if lists.isEmpty {
                Text("Nessuna lista scaricata.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            } else {
                Picker("Banlist", selection: Binding(
                    get: { browser.filters.publishedList?.effectiveDate },
                    set: { date in
                        var filters = browser.filters
                        filters.publishedList = date.map {
                            PublishedListSelection(format: .tcg, effectiveDate: $0)
                        }
                        apply(filters)
                    })) {
                    Text("Nessuna").tag(String?.none)
                    ForEach(lists, id: \.effectiveDate) { revision in
                        Text(revision.effectiveDate).tag(String?.some(revision.effectiveDate))
                    }
                }
                .labelsHidden()
                if browser.unmatchedOnList > 0 {
                    Text("\(browser.unmatchedOnList) carte della lista non sono nel catalogo")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }
        }
    }

    private var ownedSection: some View {
        section(.owned) {
            Toggle("Solo carte che possiedo", isOn: Binding(
                get: { browser.filters.ownedOnly },
                set: { isOn in
                    var filters = browser.filters
                    filters.ownedOnly = isOn
                    apply(filters)
                }))
                .toggleStyle(.checkbox)
        }
    }

    // MARK: - Pieces

    private func completionField(
        _ prompt: String,
        query: Binding<String>,
        suggestions: [String],
        chosen: Set<String>,
        toggle: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            TextField(prompt, text: query)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Typography.caption)
            ForEach(Array(chosen).sorted(), id: \.self) { value in
                Button { toggle(value) } label: {
                    Label(value, systemImage: "checkmark")
                }
                .buttonStyle(.link)
                .font(Theme.Typography.caption)
            }
            if !query.wrappedValue.isEmpty {
                ForEach(suggestions.prefix(8), id: \.self) { value in
                    Button(value) { toggle(value) }
                        .buttonStyle(.link)
                        .font(Theme.Typography.caption)
                }
            }
        }
    }

    private func rangeRow(
        lower: Int?, upper: Int?, bounds: ClosedRange<Int>,
        onChange: @escaping (Int?, Int?) -> Void
    ) -> some View {
        HStack(spacing: Theme.Spacing.tight) {
            TextField("da", value: Binding(
                get: { lower }, set: { onChange($0, upper) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
            TextField("a", value: Binding(
                get: { upper }, set: { onChange(lower, $0) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
        }
        .font(Theme.Typography.caption)
    }

    private func apply(_ filters: CardFilters) {
        browser.filters = filters
        Task { await browser.filtersChanged() }
    }
}
