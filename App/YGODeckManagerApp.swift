import SwiftUI
import YGOComposition
import YGOCore
import YGOFeatureBrowser

/// The application entry point. It builds the object graph once and hands the
/// browser the protocols it needs; no policy lives here.
@main
struct YGODeckManagerApp: SwiftUI.App {
    @State private var launch = LaunchState()

    var body: some Scene {
        WindowGroup("YGO Deck Manager") {
            Group {
                if let environment = launch.environment {
                    BrowserView(model: BrowserViewModel(
                        repository: environment.repository,
                        artwork: environment.artworkStore,
                        banStatusProvider: environment.repository))
                } else if let failure = launch.failure {
                    LaunchFailureView(message: failure)
                } else {
                    ProgressView("Apertura del catalogo…")
                }
            }
            .task { await launch.start() }
        }
        .defaultSize(width: 1100, height: 760)
    }
}

@MainActor
@Observable
final class LaunchState {
    private(set) var environment: CatalogEnvironment?
    private(set) var failure: String?

    func start() async {
        guard environment == nil, failure == nil else { return }
        do {
            let environment = try CatalogEnvironment.live()
            // Synchronisation never blocks the window from appearing.
            await environment.start()
            self.environment = environment
        } catch {
            failure = String(describing: error)
        }
    }
}

struct LaunchFailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Impossibile aprire il catalogo")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding(32)
        .frame(maxWidth: 520)
    }
}
