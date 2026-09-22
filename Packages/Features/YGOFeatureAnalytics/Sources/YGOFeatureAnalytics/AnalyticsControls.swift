import SwiftUI
import YGOCore
import YGODesignSystem

/// What the figures are about: which deck, read in which format, measured
/// against which list.
///
/// Three menus and a picker. Nothing here presents anything: the statistics
/// screen holds no alert and no sheet, and this adds none.
struct AnalyticsControls: View {
    let model: AnalyticsViewModel

    var body: some View {
        HStack(spacing: Theme.Spacing.regular) {
            deckMenu
            formatPicker
            if model.canMeasure { listMenu }
        }
    }

    @ViewBuilder
    private var deckMenu: some View {
        if model.canChooseDeck {
            Menu {
                ForEach(model.decks) { deck in
                    Button("\(deck.name) · \(deck.format.rawValue)") {
                        Task { await model.choose(deckID: deck.id) }
                    }
                }
            } label: {
                Label(model.deck?.name ?? "Scegli un mazzo", systemImage: "rectangle.stack")
            }
            .disabled(model.decks.isEmpty)
            .accessibilityLabel("Mazzo descritto dalle statistiche")
        }
    }

    /// Reading a deck elsewhere is a question, not an edit: the deck's own
    /// format stays whatever it is, and the screen says when the figures are
    /// not about it.
    private var formatPicker: some View {
        HStack(spacing: Theme.Spacing.tight) {
            Picker("Leggi come", selection: Binding(
                get: { model.readingFormat ?? .tcg },
                set: { model.assume(format: $0 == model.deck?.format ? nil : $0) })
            ) {
                ForEach(CardFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .frame(maxWidth: 170)
            .disabled(model.deck == nil)
            .accessibilityLabel("Formato assunto dalle cifre")

            if model.isReadingAnotherFormat, let own = model.deck?.format {
                Text("il mazzo è \(own.rawValue)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
        }
    }

    private var listMenu: some View {
        HStack(spacing: Theme.Spacing.tight) {
            Menu {
                ForEach(BanlistFormat.allCases, id: \.self) { format in
                    let lists = model.availableLists.filter { $0.format == format }
                    if !lists.isEmpty {
                        Section(format.rawValue.uppercased()) {
                            ForEach(lists, id: \.effectiveDate) { list in
                                Button(list.effectiveDate) {
                                    Task { await model.measure(against: list) }
                                }
                            }
                        }
                    }
                }
            } label: {
                Label(model.chosenList.map { "\($0.format.rawValue.uppercased()) \($0.effectiveDate)" }
                      ?? "Nessuna lista",
                      systemImage: "hand.raised")
            }
            .accessibilityLabel("Lista contro cui misurare il mazzo")

            verdictLine
        }
    }

    @ViewBuilder
    private var verdictLine: some View {
        if model.formatHasNoList {
            Text("nessuna lista copre questo formato")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
        } else if let verdict = model.verdict {
            Text(verdict.isWithinList
                 ? "nessuna carta oltre il consentito"
                 : "\(verdict.overAllowance.count) oltre il consentito")
                .font(Theme.Typography.caption)
                .foregroundStyle(verdict.isWithinList
                                 ? Theme.Palette.secondaryText : .orange)
                .accessibilityLabel(verdict.isWithinList
                    ? "Nessuna carta oltre il consentito secondo \(verdict.listName)"
                    : "\(verdict.overAllowance.count) carte oltre il consentito secondo \(verdict.listName)")
        }
    }
}
