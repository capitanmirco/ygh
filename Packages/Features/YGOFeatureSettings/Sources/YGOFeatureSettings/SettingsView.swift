import SwiftUI
import YGOCore
import YGODesignSystem

/// The settings window: what is stored, what can be reclaimed, and what the
/// application should remember.
///
/// Split into three small views on purpose. A single `body` holding the whole
/// window builds one generic type deep enough that the compiler stops linking
/// it — a trap this project has already fallen into once.
public struct SettingsView: View {
    @Bindable private var model: SettingsViewModel

    public init(model: SettingsViewModel) {
        _model = Bindable(wrappedValue: model)
    }

    public var body: some View {
        TabView {
            CatalogPane(model: model)
                .tabItem { Label("Catalogo", systemImage: "square.grid.2x2") }
            StoragePane(model: model)
                .tabItem { Label("Spazio", systemImage: "internaldrive") }
            ChoicesPane(model: model)
                .tabItem { Label("Preferenze", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 380)
        .task { await model.load() }
        // One alert bound to one armed request. Two presentations stacked on
        // one view means SwiftUI shows the first and drops the rest, which is
        // how a deck could be renamed and not deleted.
        .alert(
            alertTitle,
            isPresented: Binding(
                get: { model.pending != nil },
                set: { if !$0 { model.cancel() } })
        ) {
            // Captured while the alert is built, not read inside the action:
            // tapping a button dismisses the alert first, and the dismissal
            // runs this binding's setter, so `pending` is already nil by the
            // time the action runs.
            let pending = model.pending
            Button("Annulla", role: .cancel) { model.cancel() }
            Button("Elimina", role: .destructive) {
                guard let pending else { return }
                Task { await model.confirm(pending) }
            }
        } message: {
            Text(alertMessage)
        }
    }

    private var alertTitle: String {
        switch model.pending {
        case .purgeArtwork: "Svuotare la cache delle immagini?"
        case .deleteBackup: "Eliminare il backup precedente alla migrazione?"
        case nil: ""
        }
    }

    private var alertMessage: String {
        switch model.pending {
        case .purgeArtwork:
            "Le immagini vengono riscaricate quando servono. Mazzi e collezione non sono toccati."
        case .deleteBackup:
            "È la copia del database precedente all'ultimo aggiornamento dello schema. "
                + "Eliminandola rinunci a un ripristino manuale allo schema precedente. "
                + "Mazzi e collezione non sono toccati."
        case nil: ""
        }
    }
}

/// What the stored catalog is, and asking for a newer one.
private struct CatalogPane: View {
    let model: SettingsViewModel

    var body: some View {
        Form {
            if model.catalogValues.isEmpty {
                Text("Catalogo non ancora scaricato.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.catalogValues) { value in
                    ReportedRow(value: value)
                }
            }

            Section {
                HStack(spacing: Theme.Spacing.snug) {
                    Button("Controlla aggiornamenti") {
                        Task { await model.checkForUpdates() }
                    }
                    .disabled(model.activity.isRunning)

                    if let line = model.activity.line {
                        ProgressView().controlSize(.small)
                        Text(line).foregroundStyle(.secondary)
                    }
                }

                if let report = model.report {
                    Text(report.sentence)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// What the application occupies, and the two things that can be reclaimed.
private struct StoragePane: View {
    let model: SettingsViewModel

    var body: some View {
        Form {
            if model.storageValues.isEmpty {
                // Measured after the window is on screen: walking fourteen
                // thousand files takes long enough to be seen.
                HStack(spacing: Theme.Spacing.snug) {
                    ProgressView().controlSize(.small)
                    Text("Calcolo dello spazio…").foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.storageValues) { value in
                    ReportedRow(value: value)
                }
            }

            Section {
                Button("Svuota la cache delle immagini") {
                    model.ask(.purgeArtwork)
                }
                .disabled(model.footprint.map { $0.artworkFiles == 0 } ?? true)

                Button("Elimina il backup precedente alla migrazione") {
                    model.ask(.deleteBackup)
                }
                .disabled(model.footprint?.backupBytes == nil)
            } footer: {
                Text("Le immagini si riscaricano quando servono. "
                    + "Mazzi e collezione non vengono mai toccati.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// What the application remembers between launches.
private struct ChoicesPane: View {
    let model: SettingsViewModel

    var body: some View {
        Form {
            Picker(
                "All'avvio apri",
                selection: Binding(
                    get: { model.preferences.startingSection },
                    set: { model.setStartingSection($0) })
            ) {
                ForEach(AppSection.allCases, id: \.self) { section in
                    Text(section.title).tag(section)
                }
            }

            Picker(
                "Lingua delle carte",
                selection: Binding(
                    get: { model.preferences.cardLanguage },
                    set: { model.setCardLanguage($0) })
            ) {
                Text("Italiano").tag(CardLanguage.italian)
                Text("Inglese").tag(CardLanguage.english)
            }
        }
        .formStyle(.grouped)
    }
}

/// One measured figure, read as a pair so it never reaches a screen reader as
/// a bare number.
private struct ReportedRow: View {
    let value: ReportedValue

    var body: some View {
        LabeledContent(value.label) {
            Text(value.value).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.accessibilityLabel)
    }
}
