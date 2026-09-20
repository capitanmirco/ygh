import SwiftUI
import YGOComposition
import YGOCore
import YGODesignSystem
import UniformTypeIdentifiers
import YGOFeatureBrowser
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
    @State private var importReport: String?

    var body: some View {
        NavigationSplitView {
            Sidebar(section: $section, decks: decks, selectedDeck: $selectedDeck,
                    importing: $importing, progress: progress)
        } detail: {
            Detail(section: section, environment: environment, selectedDeck: selectedDeck)
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

    private func reloadDecks() async {
        decks = (try? await environment.deckRepository.allDecks()) ?? []
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

private struct Sidebar: View {
    @Binding var section: RootView.Section
    let decks: [Deck]
    @Binding var selectedDeck: Int64?
    @Binding var importing: Bool
    let progress: String?

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
    }

    @ViewBuilder
    private var deckSection: some View {
        SwiftUI.Section("I tuoi mazzi") {
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
            }
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

private struct Detail: View {
    let section: RootView.Section
    let environment: CatalogEnvironment
    let selectedDeck: Int64?

    var body: some View {
        switch section {
        case .catalog:
            BrowserView(model: BrowserViewModel(
                repository: environment.repository,
                artwork: environment.artworkStore,
                banStatusProvider: environment.repository))
        case .collection:
            CollectionView(model: CollectionViewModel(reader: environment.collection))
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
            DeckEditorView(model: DeckEditorViewModel(
                repository: environment.deckRepository,
                validator: environment.deckValidator))
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
            let entries = (try? await environment.collection.entries()) ?? []

            // Rarity and location come from the printing and the binder, which
            // is why the valuation can be broken down by either.
            var items: [ValuationItem] = []
            var names: [CardIdentifier: String] = [:]
            let locations = (try? await environment.collection.locations()) ?? []
            let locationNames = Dictionary(
                uniqueKeysWithValues: locations.map { ($0.id, $0.name) })

            for entry in entries {
                items.append(ValuationItem(
                    card: entry.card,
                    quantity: entry.quantity,
                    rarity: nil,
                    location: entry.locationID.flatMap { locationNames[$0] }))
                if names[entry.card] == nil {
                    names[entry.card] = (try? await environment.repository
                        .card(with: entry.card))??.englishName ?? "Carta \(entry.card.rawValue)"
                }
            }

            let totals = try? await environment.collection.totals()
            await model.load(
                items: items, names: names,
                recordedSpend: totals.map { Money(amount: $0.recordedSpend, currency: .eur) })
            self.model = model
        }
    }
}
