import SwiftUI
import YGOCore
import YGODesignSystem

/// What a published Forbidden & Limited List makes of the open deck.
///
/// The third thing the panel beside the deck can show, after the card preview
/// and the history. One at a time, each with its own shortcut, and no sheet or
/// alert: the editor already holds a confirmation dialog and a restore alert.
struct DeckLegalityPanel: View {
    let model: DeckEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if model.formatHasNoList {
                noList
            } else if let verdict = model.verdict {
                summary(verdict)
                Divider()
                cards(verdict)
            } else {
                ProgressView().padding(Theme.Spacing.regular)
            }
        }
        .background(Theme.Palette.surface)
        .task { await model.showLegality() }
    }

    private var header: some View {
        HStack {
            Text("Legalità").font(Theme.Typography.sectionTitle)
            Spacer()
            listMenu
            Button { model.hideLegality() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Chiudi la legalità")
        }
        .padding(Theme.Spacing.snug)
    }

    private var listMenu: some View {
        Menu {
            ForEach(BanlistFormat.allCases, id: \.self) { format in
                let lists = model.availableLists.filter { $0.format == format }
                if !lists.isEmpty {
                    Section(format.rawValue.uppercased()) {
                        ForEach(lists, id: \.effectiveDate) { list in
                            Button(list.effectiveDate) {
                                Task { await model.judge(against: list) }
                            }
                        }
                    }
                }
            }
        } label: {
            Label(model.chosenList.map { "\($0.format.rawValue.uppercased()) \($0.effectiveDate)" }
                  ?? "Scegli una lista",
                  systemImage: "hand.raised")
        }
        .accessibilityLabel("Lista contro cui giudicare il mazzo")
    }

    /// A format nothing published covers is told rather than guessed: judging
    /// it against the current TCG list would look authoritative and be wrong.
    private var noList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            Text("Nessuna lista pubblicata copre questo formato.")
                .font(Theme.Typography.body)
            Text("Puoi comunque sceglierne una qui sopra per vedere cosa direbbe.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(Theme.Spacing.regular)
    }

    private func summary(_ verdict: DeckListVerdict) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
            Text(verdict.isWithinList
                 ? "Nessuna carta oltre il consentito."
                 : "\(verdict.overAllowance.count) carte oltre il consentito.")
                .font(Theme.Typography.body)
            Text("\(verdict.forbidden) vietate · \(verdict.limited) limitate · "
                + "\(verdict.semiLimited) semi-limitate"
                + (verdict.unmatched > 0 ? " · \(verdict.unmatched) non abbinabili" : ""))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
            Text("Secondo \(verdict.listName)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .padding(Theme.Spacing.snug)
        .accessibilityElement(children: .combine)
    }

    private func cards(_ verdict: DeckListVerdict) -> some View {
        List(verdict.cards, selection: Binding(
            get: { model.selectedJudgedCard },
            set: { _ in })
        ) { card in
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                    Text(card.name).font(Theme.Typography.body)
                    Text(statusLine(card))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                Spacer()
                if card.isOverAllowance {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
            }
            .tag(card.card)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.announcement)
        }
    }

    private func statusLine(_ card: ListedDeckCard) -> String {
        guard card.isMatched else { return "non abbinabile · \(card.held) in mazzo" }
        let verdict = switch card.status {
        case .forbidden: "vietata"
        case .limited: "limitata"
        case .semiLimited: "semi-limitata"
        case nil: "non elencata"
        }
        return "\(verdict) · \(card.held) in mazzo, \(card.permitted) consentite"
    }
}
