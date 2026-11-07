import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

/// One account (BankAccount.dc.html): the payroll alert, the tabs, the balance with the available / overdraft / rate strip, the action
/// tiles and the tab's content. Every money action is the engine's existing one; each reports its result in a toast. The investments
/// account has no tabs: its holdings sit under the balance, one level less to reach a name.
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
        case .investments: return [.account]
        case .company: return [.account, .bills, .loans, .statements]
        }
    }

    var body: some View {
        if let e = store.engine, let d = e.bankAccount(id) {
            let fmt = BankFmt.make(store, id)
            let pagerSelection: Binding<BankTab> = Binding(get: { tabs.contains(tab) ? tab : BankTab.account }, set: { tab = $0 })
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    if let a = d.alert { alertBanner(a, fmt) }
                    if tabs.count > 1 { tabRow(d, pagerSelection) }
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xs)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                // Pages sit on the page itself: every group inside draws flat (no boxes).
                if tabs.count > 1 {
                    SegmentPager(items: tabs, selection: pagerSelection) { (t: BankTab) in
                        ScrollScreen(spacing: Theme.Space.xl, top: Theme.Space.l, maxWidth: 560) { pageContent(e, d, fmt, t) }
                            .environment(\.insideCard, true)
                    }
                } else {
                    ScrollScreen(spacing: Theme.Space.xl, top: Theme.Space.l, maxWidth: 560) { pageContent(e, d, fmt, .account) }
                        .environment(\.insideCard, true)
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
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                balanceCard(d, fmt)
                tiles(d)
            }
        }
        content(e, d, fmt, t)
    }

    // MARK: Alert

    /// Payroll that needs the player: run in Accounting, which owns payroll; the Bank only says it and links there.
    private func alertBanner(_ a: PayrollAlert, _ fmt: BankFmt) -> some View {
        let text: String = a.isLate ? "Payroll \(fmt.short(a.amount)) is late. \(a.reason)"
                                    : "Payroll \(fmt.short(a.amount)) on \(a.dateText) needs you. \(a.reason)"
        return HStack(alignment: .center, spacing: Theme.Space.m) {
            LedgerGlyph(glyph: Glyph.warning, size: Theme.Icon.medium, tint: a.isLate ? P.loss : P.warn)
            Text(text.tidyText).textStyle(.caption, tint: P.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.xs)
            Button("Run payroll") { store.openAccounting(companyID: a.companyID, payroll: true) }
                .buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
                .accessibilityIdentifier("bank-alert-payroll")
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill((a.isLate ? P.loss : P.warn).opacity(0.10)))
        .accessibilityElement(children: .contain)
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

    /// The system section bar: Bills carries the payroll alert as a red count, Loans a dot for unread bank letters.
    private func tabRow(_ d: BankAccountDetail, _ selection: Binding<BankTab>) -> some View {
        let alert: Bool = d.alert != nil
        let loanIDs: [String] = tabs.contains(.loans) ? store.loanMessageIDs(companyID: bankCompanyID) : []
        let loansDot: Bool = loanIDs.contains { (mid: String) -> Bool in store.isNew(.bank, mid) }
        return SectionTabs(items: tabs, primary: Array(tabs.prefix(4)), title: { (t: BankTab) -> String in t.rawValue }, selection: selection,
                           badge: { (t: BankTab) -> Int in t == .bills && alert ? 1 : 0 },
                           dots: { (t: BankTab) -> Bool in t == .loans && loansDot })
            .padding(.horizontal, -Theme.Space.page)
    }

    // MARK: Balance

    /// The balance leads, the month's change under it in gain or loss, then one quiet line of what can be spent. No box.
    private func balanceCard(_ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        let label: String = id == .personal ? "Current account" : id == .investments ? "Value of what you hold" : "Company account"
        let m: Double = d.monthChange ?? 0
        let change: String = abs(m) >= 0.5 ? (m > 0 ? "+" : "\u{2212}") + fmt.short(abs(m)) + " this month" : "No change this month"
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            MoneyHero(label: label, value: fmt.full(d.balance), tint: d.balance < 0 ? P.loss : nil,
                      context: change, contextTint: abs(m) >= 0.5 ? P.change(m) : P.inkFaint, live: d.balance)
            if !spendLine(d, fmt).isEmpty {
                Text(spendLine(d, fmt).tidyText).textStyle(.caption, tint: P.inkFaint, numeric: true).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "£12k available · overdraft £5k at 9.50% · £3k saved at 4.00%": what can be spent, in one line.
    private func spendLine(_ d: BankAccountDetail, _ fmt: BankFmt) -> String {
        guard id != .investments else { return "" }
        var parts: [String] = [fmt.short(d.available) + " available"]
        let rate: String = d.overdraftRate.map { " at " + Currency.percent($0, decimals: 2) } ?? ""
        if d.overdraftUsed > 0 { parts.append("overdraft " + fmt.short(d.overdraftUsed) + " used" + rate) }
        else if d.overdraftLimit > 0 { parts.append("overdraft " + fmt.short(d.overdraftLimit) + rate) }
        if let s = d.savings, s > 0.5 { parts.append(fmt.short(s) + " saved" + (d.savingsRate.map { " at " + Currency.percent($0, decimals: 2) } ?? "")) }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: Actions

    /// Transfer is the one filled action; Deposit and Withdraw sit under it as text. Bills have their own tab.
    @ViewBuilder private func tiles(_ d: BankAccountDetail) -> some View {
        if id == .investments {
            Button { Haptics.tap(); move = .transfer } label: { Text("Cash to invest") }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
        } else {
            VStack(spacing: Theme.Space.xs) {
                Button { Haptics.tap(); move = .transfer } label: { Text("Transfer") }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                HStack(spacing: Theme.Space.l) {
                    MoneyTextAction(title: "Deposit") { move = .deposit }
                    MoneyTextAction(title: "Withdraw") { move = .withdraw }
                    if !d.upcoming.isEmpty { MoneyTextAction(title: "Pay a bill") { tab = .bills } }
                }
            }
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
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if id == .investments {
                InvestContent()
            }
            if let cid = id.companyID, let reserves = e.companyReserves(companyID: cid) {
                BankReservesCard(reserves: reserves, fmt: fmt)
            }
            if id != .investments {
                comingUp(d, fmt)
            }
            recent(d, fmt)
            if let cid = id.companyID, let co = e.state.company(cid), co.form == .limited {
                BankOwnerSalary(company: co)
            }
            if id == .personal {
                NavigationLink { ActivityView().environment(\.outsidePalette, OutsidePalette.game) } label: {
                    LedgerRow(leading: .glyph(Glyph.list), title: "Every movement", subtitle: "Week by week, since you started", chevron: true)
                }
                .buttonStyle(AcctPressStyle())
            }
        }
    }

    /// The next three payments; the Bills tab holds the rest and the Pay now buttons.
    private func comingUp(_ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        MoneyGroup(title: "Coming up", trailing: {
            Button("All bills") { tab = .bills }.buttonStyle(TertiaryButtonStyle(size: .compact))
        }) {
            if d.upcoming.isEmpty { EmptyState(glyph: BankGlyph.bill, title: "Nothing is due.", centered: false).padding(.vertical, Theme.Space.s) }
            ForEach(Array(d.upcoming.prefix(3).enumerated()), id: \.element.id) { (n: Int, u: Obligation) in
                if n > 0 { MoneyRule(inset: 32) }
                BankObligationRow(obligation: u, fmt: fmt)
            }
        }
    }

    private func recent(_ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        MoneyGroup(title: "Recent", trailing: {
            Button("View all") { viewAll = true }.buttonStyle(TertiaryButtonStyle(size: .compact))
        }) {
            if d.recent.isEmpty { EmptyState(glyph: BankGlyph.transfer, title: "Nothing has gone through yet.", centered: false).padding(.vertical, Theme.Space.s) }
            ForEach(Array(d.recent.prefix(5).enumerated()), id: \.element.id) { (n: Int, t: BankTransaction) in
                if n > 0 { MoneyRule(inset: 0) }
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
                  value: fmt.short(obligation.amount), lineLimit: 1)
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
                  valueTint: transaction.amount > 0 ? P.gain : nil, lineLimit: 1)
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

/// The owner's salary from a limited company (moved here from the company's money desk).
struct BankOwnerSalary: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var company: Company
    @State private var salary = 0.0

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
                    Text("Paid with payroll while the company is open, with employer contributions on top; income tax is withheld. A salary is a cost to the company, a dividend is not.")
                        .textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
            }
            .onAppear { salary = now }
        }
    }

    private func set(_ v: Double, _ cur: Currency) {
        let result = store.act { $0.setOwnerSalary(companyID: company.id, monthly: v) }
        let now: Double = store.engine?.state.company(company.id)?.ownerMonthlySalary ?? 0
        salary = now
        store.settle(result, now > 0 ? "Your salary is now \(cur.tidyDisplay(now)) a month." : "You no longer take a salary.", same: "Your salary is already that.")
    }
}
