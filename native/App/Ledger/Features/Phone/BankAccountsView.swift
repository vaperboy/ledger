import SwiftUI
import GameCore
import Countries
import Simulation

/// Bank, pick an account (BankAccounts.dc.html): the all-accounts total with what is due in 30 days, then YOU (personal, investments) and
/// YOUR COMPANIES. Loans are not an account: a row only says how many loans the account carries.
struct BankAccountsScreen: View {
    @EnvironmentObject var store: GameStore
    var onPick: (BankAccountID) -> Void

    var body: some View {
        if let e = store.engine {
            let all = e.bankAccounts()
            let you: [BankAccountRow] = all.rows.filter { $0.kind != .company }
            let companies: [BankAccountRow] = all.rows.filter { $0.kind == .company }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    totalCard(all)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOU").capsLabel()
                        ForEach(you) { r in row(r, e) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR COMPANIES").capsLabel()
                        if companies.isEmpty {
                            Text("You have no company yet. Its account appears here once it exists.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                        }
                        ForEach(companies) { r in row(r, e) }
                    }
                    Text("Loans belong to the account they were taken for. Open an account and choose Loans.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).padding(.horizontal, 4)
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func totalCard(_ all: BankAccounts) -> some View {
        let totalTint: Color = all.total < 0 ? Theme.loss : Theme.ivory
        let coverTint: Color = all.isCovered ? Theme.gain : Theme.loss
        let coverText: String = all.isCovered ? "✓ covered" : "Short: not covered"
        return Card(padding: 16, radius: Theme.Radius.hero) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ALL ACCOUNTS").capsLabel()
                    Text(store.short(all.total)).font(.hero(30)).foregroundStyle(totalTint).minimumScaleFactor(0.6).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Due in 30 days").foregroundStyle(Theme.ivoryMuted)
                        Text(store.short(all.dueWithin30Days)).foregroundStyle(Theme.ivory)
                    }.font(.system(size: 12))
                    Text(coverText).font(.system(size: 12)).foregroundStyle(coverTint)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ r: BankAccountRow, _ e: GameEngine) -> some View {
        let co: Company? = r.companyID.flatMap { e.state.company($0) }
        let fmt = BankFmt(store: store, company: co)
        let glyph: String = r.kind == .personal ? Glyph.person : r.kind == .investments ? Glyph.invest : BankGlyph.company
        let note: String = rowNote(r, fmt)
        let value: String = fmt.short(r.balance)
        let tint: Color = r.balance < 0 ? Theme.loss : Theme.ivory
        return Button { Haptics.tap(); onPick(r.id) } label: {
            CardRow(glyph: glyph, title: r.name, subtitle: note, value: value, valueTint: tint, badge: r.hasAlert ? 1 : 0)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bank-account-\(r.id.id)")
    }

    private func rowNote(_ r: BankAccountRow, _ fmt: BankFmt) -> String {
        if r.hasAlert, let n = r.alertNote { return n }
        var parts: [String] = []
        switch r.kind {
        case .personal:
            if let rate = r.savingsRate { parts.append("Savings \(Currency.percent(rate, decimals: 2))") }
            if let s = r.savings, s > 0 { parts.append(fmt.short(s) + " saved") }
        case .investments: parts.append("Shares · crypto · funds")
        case .company: parts.append(r.detail)
        }
        if r.loanCount > 0 { parts.append("\(r.loanCount) loan\(r.loanCount == 1 ? "" : "s")") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
