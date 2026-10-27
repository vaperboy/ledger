import SwiftUI
import GameCore
import Countries
import Simulation

/// Bank, pick an account (BankAccounts.dc.html): the all-accounts total with what is due in 30 days, then YOU (personal, investments) and
/// YOUR COMPANIES. Loans are not an account: a row only says how many loans the account carries.
struct BankAccountsScreen: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    /// The account logged in as: the other rows stay visible but cannot be opened (swapping account goes through Log out).
    var lockedTo: BankAccountID? = nil
    var onPick: (BankAccountID) -> Void
    @State private var move: BankMoveKind?

    var body: some View {
        if let e = store.engine {
            let all = e.bankAccounts()
            let you: [BankAccountRow] = all.rows.filter { $0.kind != .company }
            let companies: [BankAccountRow] = all.rows.filter { $0.kind == .company }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    totalCard(all)
                    BankHomeRing(all: all, engine: e)
                    roundButtons(all)
                    billsLink(all, e)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOU").capsLabel()
                        ForEach(you) { r in row(r, e) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR COMPANIES").capsLabel()
                        if companies.isEmpty {
                            Text("You have no company yet. Its account appears here once it exists.").font(.system(size: 12.5)).foregroundStyle(P.inkFaint)
                        }
                        ForEach(companies) { r in row(r, e) }
                    }
                    Text("Loans belong to the account they were taken for. Open an account and choose Loans.")
                        .font(.system(size: 11.5)).foregroundStyle(P.inkFaint).padding(.horizontal, 4)
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .sheet(item: $move) { kind in BankMoveSheet(account: .personal, kind: kind).presentationDetents([.medium, .large]) }
        }
    }

    private func roundButtons(_ all: BankAccounts) -> some View {
        HStack(spacing: 0) {
            BankRoundButton(glyph: BankGlyph.deposit, title: "Deposit") { move = .deposit }
            BankRoundButton(glyph: BankGlyph.withdraw, title: "Send") { move = .withdraw }
            BankRoundButton(glyph: BankGlyph.transfer, title: "Transfer") { move = .transfer }
        }
        .accessibilityIdentifier("bank-round-actions")
    }

    private func billsLink(_ all: BankAccounts, _ e: GameEngine) -> some View {
        let count: Int = e.financeOverview().upcoming.count
        let sub: String = count == 0 ? "Nothing is due" : "\(count) coming · \(store.short(all.dueWithin30Days)) due in 30 days"
        return NavigationLink {
            BankAllBillsScreen()
        } label: {
            CardRow(glyph: BankGlyph.bill, title: "Bills", subtitle: sub, badge: all.alertCount)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bank-all-bills")
    }

    private func totalCard(_ all: BankAccounts) -> some View {
        let totalTint: Color = all.total < 0 ? P.loss : P.ink
        let coverTint: Color = all.isCovered ? P.gain : P.loss
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
                        Text("Due in 30 days").foregroundStyle(P.inkSoft)
                        Text(store.short(all.dueWithin30Days)).foregroundStyle(P.ink)
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
        let tint: Color = r.balance < 0 ? P.loss : P.ink
        return Button { Haptics.tap(); onPick(r.id) } label: {
            CardRow(glyph: glyph, title: r.name, subtitle: note, value: value, valueTint: tint, badge: r.hasAlert ? 1 : 0, thumb: co.map { ThumbSpec(kind: .trade, key: $0.type, glyph: glyph) })
        }
        .buttonStyle(.plain)
        .disabled(lockedTo != nil && lockedTo != r.id)
        .opacity(lockedTo != nil && lockedTo != r.id ? 0.5 : 1)
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

/// Where the money is: a ring over the accounts that hold some (personal current account, savings, investments, each company), the five
/// biggest named and the rest together. Only drawn when at least two places hold money; one place is not an allocation.
struct BankHomeRing: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var all: BankAccounts
    var engine: GameEngine

    private var palette: [Color] { [P.accent, Theme.roseGold, Theme.slateBlue, P.gain, P.inkSoft, P.inkDim] }

    var body: some View {
        let parts: [PortfolioRingCard.Slice] = slices()
        if parts.count >= 2 {
            PortfolioRingCard(slices: parts, cur: engine.homeCurrency, title: "WHERE YOUR MONEY IS", centerLabel: "Total")
        }
    }

    private func slices() -> [PortfolioRingCard.Slice] {
        var raw: [(String, Double)] = []
        for r in all.rows {
            if r.balance > 0 { raw.append((r.kind == .personal ? "Current account" : r.name, r.balance)) }
            if let s = r.savings, s > 0 { raw.append(("Savings", s)) }
        }
        raw.sort { $0.1 > $1.1 }
        var out: [PortfolioRingCard.Slice] = []
        for (i, p) in raw.prefix(5).enumerated() {
            out.append(PortfolioRingCard.Slice(id: "\(i)-\(p.0)", name: p.0, value: p.1, tint: palette[i % palette.count]))
        }
        let rest: Double = raw.dropFirst(5).reduce(0) { $0 + $1.1 }
        if rest > 0 { out.append(PortfolioRingCard.Slice(id: "other", name: "Other", value: rest, tint: palette[5])) }
        return out
    }
}
