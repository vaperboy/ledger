import SwiftUI
import GameCore
import Countries
import Simulation

/// The first page of the Bank app: everything the bank holds as one figure, then whose account to open (the player, the investments
/// account, each company) with its balance. Back from an account leads to the full overview, where every account can be opened.
struct BankPickerScreen: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var onPick: (BankAccountID) -> Void

    var body: some View {
        if let e = store.engine {
            let all: BankAccounts = e.bankAccounts()
            let you: [BankAccountRow] = all.rows.filter { $0.kind != .company }
            let companies: [BankAccountRow] = all.rows.filter { $0.kind == .company }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                    BankTotalHero(all: all)
                    group("You", you, e)
                    group("Your companies", companies, e)
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.l).padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).noSidewaysDrag().scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("bank-picker")
        }
    }

    @ViewBuilder private func group(_ title: String, _ rows: [BankAccountRow], _ e: GameEngine) -> some View {
        if !rows.isEmpty {
            MoneyGroup(title) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { (n: Int, r: BankAccountRow) in
                    if n > 0 { MoneyRule(inset: 52) }
                    BankAccountLine(row: r, engine: e, identifier: "bank-pick-\(r.id.id)") { onPick(r.id) }
                }
            }
        }
    }
}

/// The opening figure of the Bank: every balance added up, and whether what falls due in 30 days is covered.
struct BankTotalHero: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var all: BankAccounts

    var body: some View {
        let due: String = store.short(all.dueWithin30Days)
        let context: String = all.dueWithin30Days < 0.5 ? "Nothing falls due in the next 30 days"
            : (all.isCovered ? "\(due) due in 30 days \u{00B7} covered" : "\(due) due in 30 days \u{00B7} not covered")
        MoneyHero(label: "Total with the bank", value: store.money(all.total), tint: all.total < 0 ? P.loss : nil,
                  context: context, contextTint: all.isCovered ? P.inkSoft : P.loss, live: all.total)
    }
}

/// One account in a list: its mark (the company's picture, or a glyph), name, one line of detail and its balance; red when a payroll waits.
struct BankAccountLine: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var row: BankAccountRow
    var engine: GameEngine
    var identifier: String = ""
    var action: () -> Void

    var body: some View {
        let r: BankAccountRow = row
        let co: Company? = r.companyID.flatMap { engine.state.company($0) }
        let fmt = BankFmt(store: store, company: co)
        let glyph: String = r.kind == .personal ? Glyph.person : r.kind == .investments ? Glyph.invest : BankGlyph.company
        let lead: LedgerRow.Leading = co.map { LedgerRow.Leading.thumb(ThumbSpec(kind: .trade, key: $0.type, glyph: glyph)) } ?? .glyph(glyph)
        LedgerRow(leading: lead, leadingTint: P.accent, title: r.name, subtitle: note(r, fmt),
                  value: fmt.short(r.balance), valueTint: r.balance < 0 ? P.loss : nil, badge: r.hasAlert ? 1 : 0, lineLimit: 1,
                  identifier: identifier, action: action)
            .frame(minHeight: 60)
            .newGroupMarker(.bank, r.hasAlert ? [] : store.messageItemIDs(.bank, companyID: r.companyID ?? 0), alignment: .topLeading)
    }

    private func note(_ r: BankAccountRow, _ fmt: BankFmt) -> String {
        if r.hasAlert, let n = r.alertNote { return n }
        var parts: [String] = []
        switch r.kind {
        case .personal:
            if let s = r.savings, s > 0 { parts.append(fmt.short(s) + " saved") } else { parts.append("Current account") }
        case .investments: parts.append("Shares, crypto and funds")
        case .company: parts.append(r.detail)
        }
        if r.loanCount > 0 { parts.append("\(r.loanCount) loan\(r.loanCount == 1 ? "" : "s")") }
        return parts.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }
}
