import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The parts of a company's Finances section. Summary answers "is the money all right"; the others are where it is handled.
enum CompanyMoneyPart: String, CaseIterable, Hashable {
    case summary = "Summary", accounts = "Accounts", payroll = "Payroll and bills", loans = "Loans", owners = "You and owners", settings = "Settings"
}

/// One company's money: the shared financial summary, then accounts, loans, owner money and the company's legal settings.
struct CompanyMoney: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var part: CompanyMoneyPart

    var body: some View {
        let loans = engine.state.loans.filter { $0.companyID == company.id }.count
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            SectionTabs(items: CompanyMoneyPart.allCases, title: { $0.rawValue }, selection: $part,
                        badge: { $0 == .loans ? loans : 0 }).padding(.horizontal, -Theme.Space.margin)
            switch part {
            case .summary: CompanyMoneySummary(engine: engine, company: company, part: $part)
            case .accounts: CompanyAccounts(engine: engine, company: company)
            case .payroll: CompanyPayroll(engine: engine, company: company)
            case .loans: CompanyLoans(engine: engine, company: company)
            case .owners: CompanyOwnerMoney(engine: engine, company: company)
            case .settings: CompanySettings(engine: engine, company: company)
            }
        }
    }
}

// MARK: Summary

/// The financial summary every trade shares: cash, what is behind, what falls due, the last report, and where to go next.
struct CompanyMoneySummary: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var part: CompanyMoneyPart

    var body: some View {
        let cur = engine.currency(for: company)
        let h = engine.companyHealth(company)
        let o = engine.financeOverview(companyID: company.id)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Company cash").capsLabel()
                Text(cur.display(company.cash)).font(.hero(34)).foregroundStyle(company.cash < 0 ? Theme.loss : Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                Text(h.runwayWeeks != nil ? "At the current rate of loss the cash lasts \(RunwayText.of(h))." : String(format: "About %.0f weeks of costs in the bank.", h.weeksOfCash))
                    .font(.system(size: 12)).foregroundStyle(h.runwayWeeks.map { $0 < 8 ? Theme.loss : Theme.caution } ?? Theme.ivoryFaint)
                KeyFigures(items: [
                    .init(label: "Profit this month", value: cur.tidyShort(o.monthProfit), tint: o.monthProfit < 0 ? Theme.loss : Theme.ivory),
                    .init(label: "Profit this year", value: cur.tidyShort(o.yearProfit), tint: o.yearProfit < 0 ? Theme.loss : Theme.ivory),
                    .init(label: "Due in 30 days", value: cur.tidyShort(o.dueWithin30Days), tint: o.dueWithin30Days > max(0, company.cash) ? Theme.loss : Theme.ivory),
                    .init(label: "Debt", value: cur.tidyShort(h.debt), tint: h.debt > 0 ? Theme.loss : Theme.ivory),
                    .init(label: "Tax and VAT owed", value: cur.tidyShort(o.taxesOwed), tint: o.taxesOwed > 0 ? Theme.caution : Theme.ivory),
                    .init(label: "Your account", value: store.short(engine.state.cash)),
                ]).padding(.top, 8)
            }
            CompanyPaymentStress(engine: engine, company: company)
            if !o.upcoming.isEmpty {
                LedgerSection(title: "Coming up", trailing: {
                    // Stays inside this company's Finances section: no second "Group money" screen in the Company tab.
                    Button { withAnimation(.snappy(duration: 0.2)) { part = .payroll }; Haptics.choose() } label: {
                        Text("Payroll and bills  →").font(.system(size: 12)).foregroundStyle(Theme.gold)
                    }.buttonStyle(.plain)
                }) {
                    VStack(spacing: 0) {
                        ForEach(o.upcoming.prefix(4)) { u in
                            ListRow(symbol: u.essential ? "lock.fill" : "calendar", tint: Theme.ivoryMuted, title: u.title, subtitle: u.detail, trailing: cur.tidyShort(u.amount), trailingSub: u.dateText)
                        }
                    }
                }
            }
            lastWeekReport(cur)
            LedgerSection("Handle the money") {
                VStack(spacing: 0) {
                    jump("Accounts", "Profit and loss, balance sheet, cash flow, tax, transactions", .accounts)
                    jump("Payroll and bills", "Pay day, what falls due, rent and supplier bills", .payroll)
                    jump("Loans", engine.state.loans.contains { $0.companyID == company.id } ? "Borrow more, repay early" : "Borrow for this company", .loans)
                    jump("You and owners", "Put money in, take it out, salary, shares, selling", .owners)
                    jump("Settings", "Legal form, name, closing for a while, winding up", .settings)
                }
            }
        }
    }

    private func jump(_ title: String, _ sub: String, _ to: CompanyMoneyPart) -> some View {
        Button { withAnimation(.snappy(duration: 0.2)) { part = to }; Haptics.choose() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    Text(sub).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }.padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    /// The company's last closed week in a few lines, with a link to all its weekly, monthly and yearly reports.
    @ViewBuilder private func lastWeekReport(_ cur: Currency) -> some View {
        let last = engine.latestReport(.week)?.filtered(to: company.id)
        LedgerSection(title: "Reports", trailing: {
            NavigationLink { ReportsScreen(companyID: company.id) } label: {
                Text("Week, month, year  →").font(.system(size: 12)).foregroundStyle(Theme.gold)
            }.buttonStyle(.plain)
        }) {
            if let r = last {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(cur.tidyShort(r.group.pnl.netProfit)).font(.hero(26)).foregroundStyle(r.group.pnl.netProfit < 0 ? Theme.loss : Theme.ivory)
                        Text("profit · " + r.title).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                    }
                    if let s = ReportSummary.sentences(r, currency: cur).first {
                        Text(s).font(.system(size: 14)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("The first report arrives when this company has been through a full week.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }
}

/// What unpaid loans, bills and VAT have set in motion: restricted credit, a called loan, suppliers who want cash, overdue VAT.
struct CompanyPaymentStress: View {
    var engine: GameEngine
    var company: Company

    var body: some View {
        let cur = engine.currency(for: company)
        let loans = engine.state.loans.filter { $0.companyID == company.id }
        let missed = loans.reduce(0) { $0 + $1.int("miss") }
        let called = company.int("loanCall")
        let weeksLeft = called - engine.state.week
        let sup = company.int("supCut")
        let vatOver = company.num("vatOver")
        let billsOwed = (company.payables["rent"] ?? 0) + (company.payables["other"] ?? 0)
        if missed > 0 || company.flag("loanFrozen") || called != 0 || sup > 0 || vatOver > 1 {
            LedgerSection("Behind on payments") {
                VStack(alignment: .leading, spacing: 6) {
                    if called != 0 { line("The bank has called the loan: pay the next instalment within \(max(0, weeksLeft).weeksText) or the company is wound up.", Theme.loss) }
                    else if missed > 0 { line("\(missed) loan instalment\(missed == 1 ? "" : "s") missed. Unpaid interest and a penalty were added to the loan.", Theme.loss) }
                    if company.flag("loanFrozen") { line("Credit restricted: no new loans until the instalments are back on track.", Theme.caution) }
                    if vatOver > 1 { line("VAT overdue \(cur.tidyShort(vatOver)), with interest running and a penalty added.", Theme.loss) }
                    if sup >= 2 { line("Suppliers have stopped delivering stock until the overdue bills are paid.", Theme.loss) }
                    else if sup == 1 { line("Suppliers only deliver stock against cash in the account.", Theme.caution) }
                    if billsOwed > 0 { line("Rent and supplier bills waiting for month end: \(cur.tidyShort(billsOwed)).", Theme.ivoryMuted) }
                }
            }
        }
    }
    private func line(_ text: String, _ tint: Color) -> some View {
        Text(text).font(.caption).foregroundStyle(tint).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: You and owners

/// Money between you and the company (put in, take out, dividend, salary), then the owners and shares, and selling.
struct CompanyOwnerMoney: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var amount = 0.0
    @State private var salary = 0.0
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            LedgerSection(title: "Move money", trailing: {
                Text("Your account " + store.short(engine.state.cash)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    AmountField(title: "Amount", currency: cur, amount: $amount)
                    HStack {
                        Button("Put in") { putIn() }.buttonStyle(QuietButtonStyle())
                        if company.form == .limited {
                            Button("Pay a dividend") { confirmDividend(cur) }.buttonStyle(QuietButtonStyle())
                        } else {
                            Button("Take out") { takeOut() }.buttonStyle(QuietButtonStyle())
                        }
                    }
                    if company.form == .limited {
                        Text("Most you can pay out now: \(cur.display(engine.maximumDividend(companyID: company.id))). Dividends come from retained profit and are taxed on your return.")
                            .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("A sole trader's money is yours: taking it out is not taxed again, the profit already is.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            }
            if company.form == .limited {
                LedgerSection(title: "Your salary", trailing: {
                    Text(company.ownerMonthlySalary > 0 ? cur.tidyShort(company.ownerMonthlySalary) + " a month" : "None").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        AmountField(title: "Monthly salary", currency: cur, amount: $salary)
                        HStack {
                            Button("Set salary") { setSalary(salary, cur) }.buttonStyle(QuietButtonStyle())
                            if company.ownerMonthlySalary > 0 { Button("Stop salary") { setSalary(0, cur) }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted)) }
                        }
                        Text("Paid with payroll while the company is open, with employer contributions on top; income tax is withheld. A salary is a cost to the company, a dividend is not.")
                            .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            CompanyOwnershipSection(engine: engine, company: company)
            CompanySaleSection(engine: engine, company: company)
        }
        .confirmAction($pending)
        .onAppear { salary = company.ownerMonthlySalary }
    }

    private func putIn() {
        guard amount > 0 else { store.show("Enter an amount first.", tone: "warn"); return }
        if store.act({ $0.putMoneyInto(companyID: company.id, amount: amount) }) == true { Haptics.success(); store.show("Moved into \(company.name).", tone: "good") }
        else { Haptics.warning(); store.show("You don't have that much available.", tone: "warn") }
    }
    private func takeOut() {
        guard amount > 0 else { store.show("Enter an amount first.", tone: "warn"); return }
        switch store.act({ $0.takeMoneyOut(companyID: company.id, amount: amount) }) {
        case .ok?: Haptics.success(); store.show("Moved to your account.", tone: "good")
        case .dividendOnly?: store.show("A limited company can only pay dividends.", tone: "warn")
        default: Haptics.warning(); store.show("The company doesn't have that much.", tone: "warn")
        }
    }
    private func confirmDividend(_ cur: Currency) {
        guard amount > 0 else { store.show("Enter an amount first.", tone: "warn"); return }
        let amt = amount
        pending = PendingAction(title: "Pay \(cur.display(amt)) as a dividend?", message: "The cash leaves the company for good. Dividend tax is due on your personal return; co-owners get their share.", button: "Pay dividend") {
            switch store.act({ $0.payDividend(companyID: company.id, amount: amt) }) {
            case .ok?: Haptics.success(); store.show("Dividend paid.", tone: "good")
            case .noRetainedProfit?: store.show("There are no retained profits to pay out.", tone: "warn")
            case .notEnoughCash?: store.show("Not enough cash in the company.", tone: "warn")
            default: store.show("Not possible.", tone: "warn")
            }
        }
    }
    private func setSalary(_ v: Double, _ cur: Currency) {
        store.act { $0.setOwnerSalary(companyID: company.id, monthly: v) }
        let now = store.engine?.state.company(company.id)?.ownerMonthlySalary ?? 0
        salary = now
        store.show(now > 0 ? "Your salary is now \(cur.display(now)) a month." : "You no longer take a salary.", tone: "n")
    }
}
