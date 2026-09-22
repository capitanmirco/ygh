import SwiftUI
import YGOComposition
import YGOCore
import YGODesignSystem
import UniformTypeIdentifiers
import YGOFeatureBanlist
import YGOFeatureBrowser
import YGOFeatureCardDetail
import YGOFeatureAnalytics
import YGOFeatureCollection
import YGOFeatureDeckBuilder
import YGOFeaturePricing
import YGOFeatureSettings
import YGOPersistence
import YGOPricing

/// The application entry point. It builds the object graph once and hands each
/// feature the protocols it needs; no policy lives here.
@main
struct YGODeckManagerApp: SwiftUI.App {
    @State private var launch = LaunchState()

    var body: some Scene {
        WindowGroup("YGO Deck Manager") {
            Group {
                if let environment = launch.environment {
                    RootView(
                        environment: environment,
                        progress: launch.progress,
                        preferences: launch.preferences)
                } else if let failure = launch.failure {
                    LaunchFailureView(message: failure)
                } else {
                    LaunchProgressView(progress: launch.progress)
                }
            }
            .task { await launch.start() }
        }
        .defaultSize(width: 1180, height: 800)

        // The platform's own settings window: it is what ⌘, opens, and asking
        // for it twice brings the open one forward rather than making a second.
        Settings {
            if let model = launch.settings {
                SettingsView(model: model)
            } else {
                LaunchProgressView(progress: launch.progress)
                    .frame(width: 520, height: 380)
            }
        }
    }
}

/// What the three built features are reachable through.
///
/// The body is split into small views on purpose: SwiftUI builds one generic
/// type out of a view hierarchy, and a single body holding the whole window
/// grows a type the compiler cannot link.
struct RootView: View {
    let environment: CatalogEnvironment
    let progress: String?
    let preferences: Preferences

    init(environment: CatalogEnvironment, progress: String?, preferences: Preferences) {
        self.environment = environment
        self.progress = progress
        self.preferences = preferences
        _section = State(wrappedValue: preferences.startingSection)
        _library = State(wrappedValue: DeckLibraryViewModel(
            repository: environment.deckRepository,
            listing: environment.deckRepository,
            library: environment.deckRepository))
    }

    /// The sections live in `YGOCore` so that a preference can name one.
    /// Their titles and symbols come with `YGOFeatureSettings`.
    typealias Section = AppSection

    @State private var section: Section
    @State private var selectedDeck: Int64?
    @State private var importing = false
    @State private var library: DeckLibraryViewModel
    @State private var importReport: String?

    var body: some View {
        NavigationSplitView {
            Sidebar(section: $section, selectedDeck: $selectedDeck,
                    importing: $importing, progress: progress, library: library)
        } detail: {
            Detail(
                section: section, environment: environment, selectedDeck: selectedDeck,
                language: preferences.cardLanguage)
        }
        .task(id: section) { await reloadDecks() }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: true) { outcome in
            Task { await importDecks(outcome) }
        }
        .alert("Import", isPresented: Binding(
            get: { importReport != nil },
            set: { if !$0 { importReport = nil } })
        ) {
            Button("Ok") { importReport = nil }
        } message: {
            Text(importReport ?? "")
        }
    }

    /// One source for the list, read straight from the library.
    ///
    /// A copy kept in step by comparing counts was worse than no copy at all:
    /// it missed a rename, because renaming does not change how many decks
    /// there are.
    private func reloadDecks() async {
        await library.load()
    }

    /// A .ydk carries no format, so the importer proposes the one the deck
    /// holds fewest violations in, and the report says which it chose.
    private func importDecks(_ outcome: Result<[URL], any Error>) async {
        guard case .success(let urls) = outcome else {
            importReport = "Import annullato."
            return
        }

        var lines: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            do {
                let result = try await environment.deckImporter.importFile(at: url)
                var line = "\(result.deck.name): \(result.deck.totalCount) carte, "
                    + "formato proposto \(result.proposedFormat.rawValue)"
                if !result.isComplete {
                    line += " — \(result.unresolvedPasscodes.count) passcode non risolti"
                }
                lines.append(line)
            } catch {
                lines.append("\(url.lastPathComponent): non leggibile")
            }
        }

        await reloadDecks()
        selectedDeck = library.decks.last?.id
        importReport = lines.joined(separator: "\n")
    }
}

/// Hosts the new-deck sheet on its own level, so it does not compete with the
/// rename alert, the delete alert and the exporter for the one presentation
/// SwiftUI will show at a time.
private struct CreateDeckSheet<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Sheet

    func body(content base: Content) -> some View {
        base.sheet(isPresented: $isPresented) { self.content() }
    }
}

/// Carries a deck's `.ydk` text to the save panel.
///
/// A document rather than a URL write, because that is what a file exporter
/// takes and it puts the sandbox's permission where the user granted it.
private struct DeckFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct Sidebar: View {
    @Binding var section: RootView.Section
    @Binding var selectedDeck: Int64?
    @Binding var importing: Bool
    let progress: String?
    /// Creating, renaming, duplicating, exporting and deleting. The sidebar is
    /// where a deck is chosen, so it is where a deck is managed.
    let library: DeckLibraryViewModel

    @State private var creatingDeck = false
    @State private var newDeckName = ""
    @State private var newDeckFormat: CardFormat = .tcg
    @State private var exportingDeck: Int64?
    @State private var renamingDeck: Int64?
    @State private var renameText = ""

    var body: some View {
        List(selection: $section) {
            ForEach(RootView.Section.allCases, id: \.self) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }

            if section == .decks {
                deckSection
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        .safeAreaInset(edge: .bottom) { footer }
        // Each presentation sits on its own level. Stacked on one view,
        // SwiftUI shows the first and silently drops the rest — which is why
        // a deck could be renamed and not deleted.
        .modifier(CreateDeckSheet(
            isPresented: $creatingDeck, content: { newDeckSheet }))
        .background {
            Color.clear
                // Captured while the alert is built, for the same reason as
                // the deletion below: the dismissal clears it before the
                // action runs.
                .alert("Rinomina il mazzo", isPresented: Binding(
                    get: { renamingDeck != nil },
                    set: { if !$0 { renamingDeck = nil } })
                ) {
                    let pending = renamingDeck
                    TextField("Nome", text: $renameText)
                    Button("Rinomina") {
                        guard let pending else { return }
                        let name = renameText
                        Task { await library.rename(pending, to: name) }
                    }
                    Button("Annulla", role: .cancel) { renamingDeck = nil }
                }
        }
        // Deliberately an alert on the sidebar itself rather than a
        // confirmation dialog on the List: a dialog raised from a context
        // menu is presented as the menu's host is being dismissed, and never
        // appears — which is why a deck could not be deleted.
        // The deck is captured while the alert is built, not read inside the
        // button's action. Tapping an alert button dismisses it first, and
        // the dismissal runs this binding's setter — so by the time the
        // action ran, `pendingDeletion` was already nil and
        // `confirmDeletion()` returned false without deleting anything.
        .alert("Eliminare questo mazzo?", isPresented: Binding(
            get: { library.pendingDeletion != nil },
            set: { if !$0 { library.cancelDeletion() } })
        ) {
            let pending = library.pendingDeletion
            Button("Elimina", role: .destructive) {
                guard let pending else { return }
                Task {
                    // Re-assert what the user confirmed: the dismissal has
                    // already cleared it.
                    library.requestDeletion(pending)
                    if await library.confirmDeletion(), selectedDeck == pending {
                        selectedDeck = nil
                    }
                }
            }
            Button("Annulla", role: .cancel) { library.cancelDeletion() }
        } message: {
            Text("L'operazione non si può annullare.")
        }
        .background {
            Color.clear
                .fileExporter(
                    isPresented: Binding(
                        get: { exportingDeck != nil },
                        set: { if !$0 { exportingDeck = nil } }),
                    document: DeckFileDocument(
                        text: library.exportText(for: exportingDeck) ?? ""),
                    contentType: .data,
                    defaultFilename: library.exportName(for: exportingDeck)
                ) { _ in exportingDeck = nil }
        }
    }

    @ViewBuilder
    private var deckSection: some View {
        SwiftUI.Section("I tuoi mazzi") {
            Button {
                newDeckName = ""
                newDeckFormat = .tcg
                creatingDeck = true
            } label: {
                Label("Nuovo mazzo", systemImage: "plus")
            }
            .buttonStyle(.plain)

            Button { importing = true } label: {
                Label("Importa un .ydk", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.plain)

            ForEach(library.decks) { deck in
                Button { selectedDeck = deck.id } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(deck.name).font(Theme.Typography.body)
                        Text("\(deck.format.rawValue) · \(deck.count(in: .main)) carte")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu { deckMenu(deck) }
            }
        }
    }

    /// Naming a deck and choosing its format, which is everything needed to
    /// start one. Leaving the name empty is allowed: the library names it.
    private var newDeckSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
            Text("Nuovo mazzo").font(Theme.Typography.sectionTitle)

            TextField("Nome", text: $newDeckName)
                .textFieldStyle(.roundedBorder)

            Picker("Formato", selection: $newDeckFormat) {
                ForEach(CardFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }

            HStack {
                Spacer()
                Button("Annulla") { creatingDeck = false }
                Button("Crea") {
                    Task {
                        if let deck = await library.createDeck(
                            named: newDeckName, format: newDeckFormat) {
                            selectedDeck = deck.id
                            section = .decks
                        }
                        creatingDeck = false
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.loose)
        .frame(width: 340)
    }

    /// Everything a deck can have done to it, in one place: the sidebar is
    /// where a deck is chosen, so it is where a deck is managed.
    @ViewBuilder
    private func deckMenu(_ deck: Deck) -> some View {
        Button("Rinomina…") {
            renameText = deck.name
            renamingDeck = deck.id
        }
        Button("Duplica") {
            Task { await library.duplicate(deck.id) }
        }
        Button("Esporta come .ydk…") { exportingDeck = deck.id }
        Divider()
        Button("Elimina…", role: .destructive) {
            library.requestDeletion(deck.id)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let progress {
            Text(progress)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .padding(.horizontal, Theme.Spacing.snug)
                .padding(.vertical, Theme.Spacing.tight)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The grid and the panel beside it, sharing one selection.
///
/// An inspector column rather than a sheet: selecting the next card is one
/// click, and the results keep their order and their place while the panel
/// changes.
private struct CatalogSection: View {
    let environment: CatalogEnvironment

    @State private var browser: BrowserViewModel
    @State private var panel: CardDetailViewModel
    @State private var filters: FilterPanelModel
    @State private var banlists: BanlistSyncCoordinator

    init(environment: CatalogEnvironment, language: CardLanguage) {
        self.environment = environment
        _browser = State(wrappedValue: BrowserViewModel(
            repository: environment.repository,
            counter: environment.repository,
            artwork: environment.artworkStore,
            banStatusProvider: environment.repository,
            publishedLists: environment.banlistHistory,
            language: language))
        _panel = State(wrappedValue: CardDetailViewModel(
            loader: CardDetailLoader(
                catalog: environment.repository,
                details: environment.cardDetails,
                usage: environment.cardUsage,
                priceLookup: environment.prices,
                history: environment.banlistHistory,
                provenance: environment.banlistHistory),
            artwork: environment.artworkStore))
        _filters = State(wrappedValue: FilterPanelModel(vocabulary: environment.repository))
        _banlists = State(wrappedValue: BanlistSyncCoordinator(environment: environment))
    }

    var body: some View {
        // The detail is an inspector, not a second half: it takes at most a
        // quarter of the window, so opening the filters does not squeeze the
        // grid between two panels.
        GeometryReader { geometry in
            HStack(spacing: 0) {
                BrowserView(model: browser, filters: filters)
                    .frame(maxWidth: .infinity)
                Divider()
                CardDetailView(model: panel)
                    .frame(width: Theme.Inspector.width(forWindowWidth: geometry.size.width))
            }
        }
        .onChange(of: browser.selectedCard) { _, card in
            guard let card else { return }
            Task { await panel.select(card, language: browser.language) }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await banlists.synchronize() }
                } label: {
                    Label(banlists.isRunning ? "Scaricamento…" : "Scarica banlist",
                          systemImage: "arrow.down.circle")
                }
                .disabled(banlists.isRunning)
                .help(banlists.summary)
            }
        }
    }
}

private struct Detail: View {
    let section: RootView.Section
    let environment: CatalogEnvironment
    let selectedDeck: Int64?
    let language: CardLanguage

    var body: some View {
        switch section {
        case .catalog:
            CatalogSection(environment: environment, language: language)
        case .collection:
            CollectionView(model: CollectionViewModel(
                reader: environment.collection,
                writer: environment.collection,
                catalogue: environment.repository))
        case .banlist:
            BanlistSection(environment: environment)
        case .analytics:
            analyticsDetail
        case .value:
            PricingLoader(environment: environment)
        case .decks:
            deckDetail
        }
    }

    /// Analytics needs a deck. Without one there is nothing to be statistical
    /// about, and saying so beats an empty chart.
    @ViewBuilder
    private var analyticsDetail: some View {
        if let selectedDeck {
            AnalyticsLoader(environment: environment, deckID: selectedDeck)
                .id(selectedDeck)
        } else {
            ContentUnavailableView(
                "Nessun mazzo scelto",
                systemImage: "chart.bar",
                description: Text("Scegli un mazzo dalla sezione Mazzi per vederne le statistiche."))
        }
    }

    @ViewBuilder
    private var deckDetail: some View {
        if let selectedDeck {
            DeckEditorLoader(environment: environment, deckID: selectedDeck)
                .id(selectedDeck)
        } else {
            ContentUnavailableView(
                "Nessun mazzo",
                systemImage: "rectangle.stack",
                description: Text("Importa un file .ydk per iniziare."))
        }
    }
}

@MainActor
@Observable
final class LaunchState {
    private(set) var environment: CatalogEnvironment?
    private(set) var failure: String?
    private(set) var progress: String?
    /// Read before the window is built: the starting section and the card
    /// language are both needed at the first draw.
    private(set) var preferences = UserDefaultsPreferences().load()
    private(set) var settings: SettingsViewModel?

    /// One activity for the launch and for the settings panel, so both report
    /// the same synchronisation rather than each keeping its own idea of one.
    private let activity = CatalogSyncActivity()

    func start() async {
        guard environment == nil, failure == nil else { return }

        // Takes an optional so a finished stage clears the line rather than
        // leaving the last count on screen.
        let report: @Sendable (String?) -> Void = { [weak self] line in
            Task { @MainActor in self?.progress = line }
        }

        do {
            let environment = try CatalogEnvironment.live(
                observeSync: { [activity] sync in
                    // One mapping of a stage to a sentence, shared with the
                    // settings panel rather than written twice.
                    report(CatalogSyncActivity.line(for: sync))
                    activity.observe(sync)
                },
                observePrefetch: { artwork in
                    report("Immagini: \(artwork.stored) di \(artwork.total)")
                })

            // The window appears before synchronisation finishes; a first run
            // downloads about 41 MB of card data and then fills in thumbnails
            // behind the interface.
            self.environment = environment
            self.settings = Self.makeSettings(
                environment: environment, activity: activity,
                onPreferencesChange: { [weak self] in self?.preferences = $0 })
            await environment.start()
            progress = nil
        } catch {
            failure = String(describing: error)
        }
    }

    /// Binds the four settings seams to the concrete types that satisfy them.
    /// This is the only place that knows which is which.
    private static func makeSettings(
        environment: CatalogEnvironment,
        activity: CatalogSyncActivity,
        onPreferencesChange: @escaping @MainActor (Preferences) -> Void
    ) -> SettingsViewModel {
        let container = (try? CatalogEnvironment.defaultContainerURL())
            ?? URL(filePath: NSTemporaryDirectory())
        return SettingsViewModel(
            status: environment.catalogStore,
            refresher: environment,
            inventory: FileStorageInventory(
                configuration: .init(containerURL: container),
                artwork: environment.artworkStore),
            preferences: ObservingPreferences(
                wrapped: UserDefaultsPreferences(),
                onChange: { preferences in
                    // The main window's copy is refreshed from the stored one,
                    // which remains the single source of truth.
                    Task { @MainActor in onPreferencesChange(preferences) }
                }),
            activity: activity)
    }
}

/// Reports a saved preference back to the launch state, so a choice made in
/// the settings window is visible to the main window without a relaunch —
/// while the stored value remains the single source of truth.
private struct ObservingPreferences: PreferenceStoring {
    let wrapped: UserDefaultsPreferences
    let onChange: @Sendable (Preferences) -> Void

    func load() -> Preferences { wrapped.load() }

    func save(_ preferences: Preferences) {
        wrapped.save(preferences)
        onChange(preferences)
    }
}

struct LaunchProgressView: View {
    let progress: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.snug) {
            ProgressView()
            Text(progress ?? "Apertura del catalogo…")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LaunchFailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.snug) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Theme.Palette.secondaryText)
            Text("Impossibile aprire il catalogo").font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.Palette.secondaryText)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding(Theme.Spacing.section)
        .frame(maxWidth: 520)
    }
}

/// Loads a deck and its card snapshot, then hands both to the analytics view.
private struct AnalyticsLoader: View {
    let environment: CatalogEnvironment
    let deckID: Int64

    @State private var model = AnalyticsViewModel()
    @State private var loaded = false

    var body: some View {
        Group {
            if loaded {
                AnalyticsView(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            guard let deck = try? await environment.deckRepository.deck(with: deckID),
                  let index = try? await environment.deckRepository.cardIndex(for: deck)
            else { return }
            model.load(deck: deck, index: index)
            loaded = true
        }
    }
}

/// Loads the collection and hands it to the valuation view.
private struct PricingLoader: View {
    let environment: CatalogEnvironment

    @State private var model: PricingViewModel?

    var body: some View {
        Group {
            if let model {
                PricingView(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            let model = PricingViewModel(lookup: environment.prices)

            // Rarity comes from the printing and the binder from the location,
            // both resolved in one query rather than assembled here.
            let rows = (try? await environment.collection.valuationRows()) ?? []
            let items = rows.map {
                ValuationItem(card: $0.card, quantity: $0.quantity,
                              rarity: $0.rarity, location: $0.location)
            }
            let names = (try? await environment.collection
                .cardNames(for: Set(rows.map(\.card)))) ?? [:]
            let totals = try? await environment.collection.totals()

            await model.load(
                items: items, names: names,
                recordedSpend: totals.map { Money(amount: $0.recordedSpend, currency: .eur) })
            self.model = model
        }
    }
}

/// A Forbidden & Limited List, with the card detail beside it.
private struct BanlistSection: View {
    let environment: CatalogEnvironment

    @State private var model: BanlistBrowserViewModel
    @State private var panel: CardDetailViewModel
    @State private var sync: BanlistSyncCoordinator

    init(environment: CatalogEnvironment) {
        self.environment = environment
        _model = State(wrappedValue: BanlistBrowserViewModel(
            history: environment.banlistHistory,
            catalog: environment.repository))
        _panel = State(wrappedValue: CardDetailViewModel(
            loader: CardDetailLoader(
                catalog: environment.repository,
                details: environment.cardDetails,
                usage: environment.cardUsage,
                priceLookup: environment.prices,
                history: environment.banlistHistory,
                provenance: environment.banlistHistory),
            artwork: environment.artworkStore))
        _sync = State(wrappedValue: BanlistSyncCoordinator(environment: environment))
    }

    var body: some View {
        BanlistBrowserView(
            model: model,
            preview: AnyView(CardDetailView(model: panel)),
            onSynchronise: { Task { await sync.synchronize(); await model.load(format: model.format) } })
            .onChange(of: model.previewCard) { _, card in
                guard let card else { return }
                Task { await panel.select(card, language: .italian) }
            }
    }
}

/// Builds a deck editor and loads the chosen deck into it.
///
/// The view model starts empty and has to be told which deck to show; without
/// this the editor rendered an empty deck whichever one was selected.
private struct DeckEditorLoader: View {
    let environment: CatalogEnvironment
    let deckID: Int64

    @State private var model: DeckEditorViewModel?
    @State private var panel: CardDetailViewModel?

    var body: some View {
        Group {
            if let model, let panel {
                DeckEditorView(
                    model: model,
                    preview: AnyView(CardDetailView(model: panel)))
                    .onChange(of: model.previewCard) { _, card in
                        guard let card else { return }
                        Task { await panel.select(card, language: model.language) }
                    }
            } else {
                ProgressView()
            }
        }
        .task {
            let model = DeckEditorViewModel(
                repository: environment.deckRepository,
                validator: environment.deckValidator,
                catalogue: environment.repository,
                editing: environment.deckRepository,
                reader: environment.repository)
            self.panel = CardDetailViewModel(
                loader: CardDetailLoader(
                    catalog: environment.repository,
                    details: environment.cardDetails,
                    usage: environment.cardUsage,
                    priceLookup: environment.prices,
                    history: environment.banlistHistory,
                    provenance: environment.banlistHistory),
                artwork: environment.artworkStore)
            await model.load(deckID: deckID)
            self.model = model
        }
    }
}
