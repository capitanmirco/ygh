import SwiftUI
import YGOComposition
import YGOCore
import YGODesignSystem
import UniformTypeIdentifiers
import YGOFeatureBrowser
import YGOFeatureCardDetail
import YGOFeatureAnalytics
import YGOFeatureCollection
import YGOFeatureDeckBuilder
import YGOFeaturePricing
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
                    RootView(environment: environment, progress: launch.progress)
                } else if let failure = launch.failure {
                    LaunchFailureView(message: failure)
                } else {
                    LaunchProgressView(progress: launch.progress)
                }
            }
            .task { await launch.start() }
        }
        .defaultSize(width: 1180, height: 800)
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

    init(environment: CatalogEnvironment, progress: String?) {
        self.environment = environment
        self.progress = progress
        _library = State(wrappedValue: DeckLibraryViewModel(
            repository: environment.deckRepository,
            listing: environment.deckRepository,
            library: environment.deckRepository))
    }

    enum Section: String, CaseIterable, Identifiable {
        case catalog = "Catalogo"
        case decks = "Mazzi"
        case collection = "Collezione"
        case analytics = "Statistiche"
        case value = "Valore"
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .catalog: "square.grid.2x2"
            case .decks: "rectangle.stack"
            case .collection: "tray.full"
            case .analytics: "chart.bar"
            case .value: "eurosign.circle"
            }
        }
    }

    @State private var section: Section = .catalog
    @State private var selectedDeck: Int64?
    @State private var decks: [Deck] = []
    @State private var importing = false
    @State private var library: DeckLibraryViewModel
    @State private var importReport: String?

    var body: some View {
        NavigationSplitView {
            Sidebar(section: $section, decks: decks, selectedDeck: $selectedDeck,
                    importing: $importing, progress: progress, library: library)
        } detail: {
            Detail(section: section, environment: environment, selectedDeck: selectedDeck)
        }
        .task(id: section) { await reloadDecks() }
        // A deck created, duplicated or deleted from the sidebar changes the
        // library's list; the sidebar follows it.
        .onChange(of: library.decks.count) { _, _ in decks = library.decks }
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

    /// One source for the list. The library owns it, and the sidebar shows
    /// what the library holds — two loaders would drift the first time a deck
    /// was created from one of them.
    private func reloadDecks() async {
        await library.load()
        decks = library.decks
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
        selectedDeck = decks.last?.id
        importReport = lines.joined(separator: "\n")
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
    let decks: [Deck]
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
            ForEach(RootView.Section.allCases) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }

            if section == .decks {
                deckSection
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        .safeAreaInset(edge: .bottom) { footer }
        .sheet(isPresented: $creatingDeck) { newDeckSheet }
        .alert("Rinomina il mazzo", isPresented: Binding(
            get: { renamingDeck != nil },
            set: { if !$0 { renamingDeck = nil } })) {
            TextField("Nome", text: $renameText)
            Button("Rinomina") {
                if let id = renamingDeck {
                    Task { await library.rename(id, to: renameText) }
                }
                renamingDeck = nil
            }
            Button("Annulla", role: .cancel) { renamingDeck = nil }
        }
        .confirmationDialog(
            "Eliminare questo mazzo?",
            isPresented: Binding(
                get: { library.pendingDeletion != nil },
                set: { if !$0 { library.cancelDeletion() } }),
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) {
                Task {
                    let deleted = library.pendingDeletion
                    if await library.confirmDeletion(), selectedDeck == deleted {
                        selectedDeck = nil
                    }
                }
            }
            Button("Annulla", role: .cancel) { library.cancelDeletion() }
        } message: {
            Text("L'operazione non si può annullare.")
        }
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

            ForEach(decks) { deck in
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

    init(environment: CatalogEnvironment) {
        self.environment = environment
        _browser = State(wrappedValue: BrowserViewModel(
            repository: environment.repository,
            counter: environment.repository,
            artwork: environment.artworkStore,
            banStatusProvider: environment.repository,
            publishedLists: environment.banlistHistory))
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

    var body: some View {
        switch section {
        case .catalog:
            CatalogSection(environment: environment)
        case .collection:
            CollectionView(model: CollectionViewModel(
                reader: environment.collection,
                writer: environment.collection,
                catalogue: environment.repository))
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

    func start() async {
        guard environment == nil, failure == nil else { return }

        // Takes an optional so a finished stage clears the line rather than
        // leaving the last count on screen.
        let report: @Sendable (String?) -> Void = { [weak self] line in
            Task { @MainActor in self?.progress = line }
        }

        do {
            let environment = try CatalogEnvironment.live(
                observeSync: { sync in
                    switch sync.stage {
                    case .checkingVersion: report("Controllo aggiornamenti…")
                    case .downloading: report("Scarico il catalogo…")
                    case .storing:
                        report("Salvo le carte: \(sync.completed) di \(sync.total)")
                    case .finished: report(nil)
                    }
                },
                observePrefetch: { artwork in
                    report("Immagini: \(artwork.stored) di \(artwork.total)")
                })

            // The window appears before synchronisation finishes; a first run
            // downloads about 41 MB of card data and then fills in thumbnails
            // behind the interface.
            self.environment = environment
            await environment.start()
            progress = nil
        } catch {
            failure = String(describing: error)
        }
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
