import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

struct BankAccountScreen: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var id: BankAccountID
    @Binding var tab: BankTab
    @State private var viewAll = false

    private var tabs: [BankTab] {
        switch id {
        case .personal: return [.account, .bills, .loans, .deposits, .statements]
        case .investments: return [.account, .bills, .loans, .statements]
        }
    }

    var body: some View {
        if let e = store.engine, let d = e.bankAccount(id) {
            let fmt = BankFmt(store: store, company: nil)
            let pagerSelection: Binding<BankTab> = Binding(get: { tabs.contains(tab) ? tab : BankTab.account }, set: { tab = $0 })
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    if tabs.count > 1 { tabRow(d, pagerSelection) }
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xs)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                if tabs.count > 1 {
                    SegmentPager(items: tabs, selection: pagerSelection) { (t: BankTab) in
                        ScrollScreen(spacing: Theme.Space.l, top: Theme.Space.xs, maxWidth: 560) { pageContent(e, d, fmt, t) }
                    }
                } else {
                    ScrollScreen(spacing: Theme.Space.l, top: Theme.Space.xs, maxWidth: 560) { pageContent(e, d, fmt, .account) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { clearLoanDot() }
            .onChange(of: tab) { _, _ in clearLoanDot() }
            .centerSheet(isPresented: $viewAll, title: "Every movement") { BankAllMovementsSheet(account: id) }
        } else {
            EmptyState(title: "This account is closed.").padding(Theme.Space.xl)
        }
    }

    @ViewBuilder private func pageContent(_ e: GameEngine, _ d: BankAccountDetail, _ fmt: BankFmt, _ t: BankTab) -> some View {
        if t == .account {
            balanceCard(d, fmt)
            tiles(d)
        }
        content(e, d, fmt, t)
    }

    private func clearLoanDot() {
        guard tab == .loans else { return }
        for mid in store.loanMessageIDs() { store.markItemSeen(.bank, mid) }
    }

    private func tabRow(_ d: BankAccountDetail, _ selection: Binding<BankTab>) -> some View {
        let loanIDs: [String] = tabs.contains(.loans) ? store.loanMessageIDs() : []
        let loansDot: Bool = loanIDs.contains { (mid: String) -> Bool in store.isNew(.bank, mid) }
        return SectionTabs(items: tabs, primary: Array(tabs.prefix(4)), title: { (t: BankTab) -> String in t.rawValue }, selection: selection,
                           dots: { (t: BankTab) -> Bool in t == .loans && loansDot })
            .padding(.horizontal, -Theme.Space.page)
    }

    private func balanceCard(_ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        let label: String = id == .personal ? "Your account" : "Investments"
        let tint: Color = d.balance < 0 ? P.loss : P.ink
        let overdraft: String = d.overdraftUsed > 0 ? fmt.short(d.overdraftUsed) + " used" : fmt.short(d.overdraftLimit)
        let rate: String = d.overdraftRate.map { Currency.percent($0, decimals: 2) } ?? "–"
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                Figure(label: label, value: fmt.full(d.balance), tint: tint, size: .display, live: d.balance)
                Spacer(minLength: Theme.Space.s)
                if let m = d.monthChange, abs(m) >= 0.5 {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text((m > 0 ? "▲ " : "▼ ") + fmt.short(abs(m))).textStyle(.caption, tint: P.change(m), numeric: true)
                        Text("this month").textStyle(.caption, tint: P.inkFaint)
                    }
                }
            }
            FigureRow(items: [
                KeyFigures.Item(label: "Available", value: fmt.short(d.available), tint: d.available <= 0 ? P.loss : P.ink),
                KeyFigures.Item(label: "Overdraft", value: overdraft, tint: d.overdraftUsed > 0 ? P.warn : P.ink),
                KeyFigures.Item(label: "Overdraft rate", value: rate),
            ])
        }
    }

    private func tiles(_ d: BankAccountDetail) -> some View {
        HStack(spacing: Theme.Space.s) {
            ActionTile(glyph: BankGlyph.bill, title: "Pay bill") { tab = .bills }
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ d: BankAccountDetail, _ fmt: BankFmt, _ t: BankTab) -> some View {
        switch t {
        case .account: accountTab(e, d, fmt)
        case .loans: BankLoansTab(account: id, loans: d.loans)
        case .deposits: BankFixedDeposits()
        case .bills: BankBillsTab(account: id, detail: d)
        case .statements: BankStatementsTab(account: id, detail: d)
        }
    }

    private func accountTab(_ e: GameEngine, _ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if id == .personal { TaxEstimateCard(engine: e) }
            comingUp(d, fmt)
            recent(d, fmt)
            if id == .personal {
                NavigationLink { ActivityView().environment(\.outsidePalette, OutsidePalette.game) } label: {
                    LedgerRow(title: "Why did my money move?", chevron: true)
                }
                .buttonStyle(AcctPressStyle())
            }
        }
    }

    private func comingUp(_ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        CardSection(title: "Coming up", trailing: {
            Button("All bills") { tab = .bills }.buttonStyle(TertiaryButtonStyle(size: .compact))
        }) {
            if d.upcoming.isEmpty { EmptyState(glyph: BankGlyph.bill, title: "Nothing is due.", centered: false) }
            ForEach(Array(d.upcoming.prefix(3).enumerated()), id: \.element.id) { (n: Int, u: Obligation) in
                if n > 0 { Hairline() }
                BankObligationRow(obligation: u, fmt: fmt)
            }
        }
    }

    private func recent(_ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        CardSection(title: "Recent", trailing: {
            Button("View all") { viewAll = true }.buttonStyle(TertiaryButtonStyle(size: .compact))
        }) {
            if d.recent.isEmpty { EmptyState(glyph: BankGlyph.transfer, title: "Nothing has gone through yet.", centered: false) }
            ForEach(Array(d.recent.prefix(5).enumerated()), id: \.element.id) { (n: Int, t: BankTransaction) in
                if n > 0 { Hairline() }
                BankTransactionRow(transaction: t, fmt: fmt)
            }
        }
    }
}

struct BankObligationRow: View {
    @Environment(\.outsidePalette) private var P
    var obligation: Obligation
    var fmt: BankFmt
    var body: some View {
        let glyph: String = obligation.kind == .loan ? BankGlyph.transfer : BankGlyph.bill
        LedgerRow(leading: .glyph(glyph), leadingTint: P.inkSoft, title: obligation.title, subtitle: obligation.dateText,
                  value: fmt.short(obligation.amount), density: .compact)
    }
}

struct BankTransactionRow: View {
    @Environment(\.outsidePalette) private var P
    var transaction: BankTransaction
    var fmt: BankFmt
    var body: some View {
        let sign: String = transaction.amount >= 0 ? "+" : "−"
        LedgerRow(title: transaction.label, subtitle: transaction.dateText, value: sign + fmt.short(abs(transaction.amount)),
                  valueTint: P.change(transaction.amount), density: .compact)
    }
}

struct BankAllMovementsSheet: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var account: BankAccountID
    var body: some View {
        Group {
            Group {
                if let e = store.engine {
                    let fmt = BankFmt(store: store, company: nil)
                    let list: [BankTransaction] = e.bankTransactions(account, limit: 200)
                    VStack(spacing: 0) {
                        if list.isEmpty { EmptyState(glyph: BankGlyph.transfer, title: "Nothing has gone through yet.") }
                        ForEach(Array(list.enumerated()), id: \.element.id) { n, t in
                            if n > 0 { Hairline() }
                            BankTransactionRow(transaction: t, fmt: fmt)
                        }
                    }
                }
            }
        }
    }
}
