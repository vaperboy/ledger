import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

/// One account (BankAccount.dc.html): the tabs, the balance with the available / overdraft / rate strip, the action
/// tiles and the tab's content. Every money action is the engine's existing one; each reports its result in a popup. Investing is in the
/// Market app, so the Bank opens cash accounts only.
struct BankAccountScreen: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var id: BankAccountID
    @Binding var tab: BankTab
    @State private var move: BankMoveKind?
    @State private var viewAll = false

    /// Bills come second: they are what most visits are for. The section bar folds the last ones into More when they do not fit.
    private var tabs: [BankTab] {
        switch id {
        case .personal: return [.account, .bills, .loans, .deposits, .statements]
        case .company, .investments: return [.account, .bills, .loans, .statements]
        }
    }

    var body: some View {
        if let e = store.engine, let d = e.bankAccount(id) {
            let fmt = BankFmt.make(store, id)
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
            .centerSheet(item: $move) { kind in BankMoveSheet(account: id, kind: kind) }
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

    // MARK: Tabs

    /// The company behind this account (0 for the player's own accounts), to find its Bank messages.
    private var bankCompanyID: Int {
        if case .company(let n) = id { return n }
        return 0
    }

    /// Opening the Loans tab reads its messages: their dot goes.
    private func clearLoanDot() {
        guard tab == .loans else { return }
        for mid in store.loanMessageIDs(companyID: bankCompanyID) { store.markItemSeen(.bank, mid) }
    }

    /// The system section bar: Loans carries a dot for unread bank letters.
    private func tabRow(_ d: BankAccountDetail, _ selection: Binding<BankTab>) -> some View {
        let loanIDs: [String] = tabs.contains(.loans) ? store.loanMessageIDs(companyID: bankCompanyID) : []
        let loansDot: Bool = loanIDs.contains { (mid: String) -> Bool in store.isNew(.bank, mid) }
        return SectionTabs(items: tabs, primary: Array(tabs.prefix(4)), title: { (t: BankTab) -> String in t.rawValue }, selection: selection,
                           dots: { (t: BankTab) -> Bool in t == .loans && loansDot })
            .padding(.horizontal, -Theme.Space.page)
    }

    // MARK: Balance

    /// The balance leads; change this month beside it, then one strip of what can be spent. No box: the page is the surface.
    private func balanceCard(_ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        let label: String = id == .personal ? "Your account" : "Company account"
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

    // MARK: Tiles

    /// Pay bill opens the Bills tab: one place for bills instead of a second list in a sheet.
    private func tiles(_ d: BankAccountDetail) -> some View {
        HStack(spacing: Theme.Space.s) {
            if id == .personal {
                ActionTile(glyph: BankGlyph.transfer, title: "Transfer") { move = .transfer }
            } else {
                ActionTile(glyph: BankGlyph.deposit, title: "Deposit") { move = .deposit }
            }
            ActionTile(glyph: BankGlyph.bill, title: "Pay bill") { tab = .bills }
        }
    }

    // MARK: Content

    @ViewBuilder private func content(_ e: GameEngine, _ d: BankAccountDetail, _ fmt: BankFmt, _ t: BankTab) -> some View {
        switch t {
        case .account: accountTab(e, d, fmt)
        case .loans: BankLoansTab(account: id, loans: d.loans)
        case .deposits: BankDepositsTab(account: id, detail: d)
        case .bills: BankBillsTab(account: id, detail: d)
        case .statements: BankStatementsTab(account: id, detail: d)
        }
    }

    private func accountTab(_ e: GameEngine, _ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if let cid = id.companyID, let reserves = e.companyReserves(companyID: cid) {
                BankReservesCard(reserves: reserves, fmt: fmt)
            }
            if id == .personal { TaxEstimateCard(engine: e) }
            comingUp(d, fmt)
            recent(d, fmt)
            if let cid = id.companyID, let co = e.state.company(cid) {
                BankOwnerSalary(company: co)
            }
            if id == .personal {
                NavigationLink { ActivityView().environment(\.outsidePalette, OutsidePalette.game) } label: {
                    LedgerRow(title: "Why did my money move?", chevron: true)
                }
                .buttonStyle(AcctPressStyle())
            }
        }
    }

    /// The next three payments; the Bills tab holds the rest and the Pay now buttons.
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

/// One coming payment: icon, title, date, amount.
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

/// One movement: label, date, signed amount.
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

/// "View all": the longer list of movements.
struct BankAllMovementsSheet: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var account: BankAccountID
    var body: some View {
        Group {
            Group {
                if let e = store.engine {
                    let fmt = BankFmt.make(store, account)
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

/// The owner's salary from a company (moved here from the company's money desk).
struct BankOwnerSalary: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var company: Company
    @State private var salary = 0.0
    @State private var compare = false

    var body: some View {
        if let e = store.engine {
            let cur = e.currency(for: company)
            let now: Double = e.state.company(company.id)?.ownerMonthlySalary ?? 0
            BankCard(title: "Your salary", trailing: now > 0 ? cur.tidyShort(now) + " a month" : "None") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    AmountField(title: "Monthly salary", currency: cur, amount: $salary)
                    HStack(spacing: Theme.Space.s) {
                        Button("Set salary") { set(salary, cur) }.buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
                        if now > 0 { Button("Stop salary") { set(0, cur) }.buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.loss)) }
                    }
                    Button("Compare salary, dividend or keeping it in") { compare = true }.buttonStyle(TertiaryButtonStyle(size: .compact))
                    Text("Paid with payroll on the 15th while the company is open, with employer contributions on top; income tax is withheld. A salary is a cost to the company, a dividend is not.")
                        .textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
            }
            .onAppear { salary = now }
            .centerSheet(isPresented: $compare, title: "Pay yourself") { PayYourselfSheet(companyID: company.id).environmentObject(store) }
        }
    }

    private func set(_ v: Double, _ cur: Currency) {
        let result = store.act { $0.setOwnerSalary(companyID: company.id, monthly: v) }
        let now: Double = store.engine?.state.company(company.id)?.ownerMonthlySalary ?? 0
        salary = now
        store.settle(result, now > 0 ? "Your salary is now \(cur.tidyDisplay(now)) a month." : "You no longer take a salary.", same: "Your salary is already that.")
    }
}
