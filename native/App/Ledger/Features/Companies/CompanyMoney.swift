import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Events
import Simulation

/// The parts of a company's Finances tab: Summary, Statements, Ownership and Settings. Every payment, loan and money move is in the Bank
/// app, on this company's account ("Open in Bank").
enum CompanyMoneyPart: String, CaseIterable, Hashable {
    case summary = "Summary", accounts = "Statements", owners = "Ownership", settings = "Settings"
    /// The tab row.
    static let tabs: [CompanyMoneyPart] = [.summary, .accounts, .owners, .settings]
}

/// "Open in Bank": all money handling (transfers, loans, deposits, taxes, bills, payroll approval, statements) lives in the Bank app.
/// Opens the Bank app on THIS company's account (plain navigation, so no toast); `tab` picks the Bills tab for the pay buttons.
struct OpenInBankButton: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var title = "Open in Bank"
    var tab: BankTab = .account
    var body: some View {
        QuietButton(title: title, fullWidth: true) { store.openBank(.company(companyID), tab: tab) }
            .accessibilityHint("Opens the Bank app")
    }
}

/// One company's Finances tab: a read-only, scannable view of the money, with the company decisions (dividends, shares, selling,
/// settings) kept here and every payment handled in the Bank app.
struct CompanyMoney: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var part: CompanyMoneyPart

    var body: some View {
        CompanyMoneySummary(engine: engine, company: company, part: $part)
            .navigationDestination(isPresented: Binding(get: { part != .summary }, set: { if !$0 { part = .summary } })) {
                MoneyPageDestination(part: part, companyID: company.id)
            }
    }
}

/// The full-screen page a row of the Finances table opens: Statements, Ownership or the company's own settings.
struct MoneyPageDestination: View {
    @EnvironmentObject var store: GameStore
    var part: CompanyMoneyPart
    var companyID: Int

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            SettingsPage(title: part.rawValue, subtitle: co.name) { content(e, co) }
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        switch part {
        case .summary: EmptyView()
        case .accounts: CompanyAccounts(engine: e, company: co)
        case .owners: CompanyOwnerMoney(engine: e, company: co)
        case .settings: CompanySettings(engine: e, company: co)
        }
    }
}

// MARK: Summary

/// Read-only: cash, profit, what falls due, tax and VAT owed, costs, margins, ownership and sale value.
struct CompanyMoneySummary: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var part: CompanyMoneyPart

    private static let palette: [Color] = [Theme.slateBlue, Theme.caution, Theme.gain, Theme.gold, Theme.loss, Color(red: 0.36, green: 0.70, blue: 0.74), Color(red: 0.62, green: 0.50, blue: 0.80), Theme.goldDeep, Theme.ivoryFaint, Theme.ivoryMuted]

    var body: some View {
        let cur = engine.currency(for: company)
        let o = engine.financeOverview(companyID: company.id)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            CompanyPaymentStress(engine: engine, company: company)
            cashCard(cur, o)
            settingsTable(cur, o)
            owedCard(cur, o)
            comingUp(cur, o)
            costs(cur, o)
            margins(cur, o)
            lastWeekReport(cur)
        }
    }

    // MARK: Cards

    private func cashCard(_ cur: Currency, _ o: FinanceOverview) -> some View {
        let h = engine.companyHealth(company)
        let runwayText: String = h.runwayWeeks != nil ? "At the current rate of loss the cash lasts \(RunwayText.of(h))." : String(format: "About %.0f weeks of costs in the bank.", h.weeksOfCash)
        let runwayTint: Color = h.runwayWeeks.map { $0 < 8 ? Theme.loss : Theme.caution } ?? Theme.ivoryFaint
        let cashTint: Color = company.cash < 0 ? Theme.loss : Theme.ivory
        let monthTint: Color = o.monthProfit < 0 ? Theme.loss : Theme.ivory
        let yearTint: Color = o.yearProfit < 0 ? Theme.loss : Theme.ivory
        let dueTint: Color = o.dueWithin30Days > max(0, company.cash) ? Theme.loss : Theme.ivory
        let cells: [StatStrip.Cell] = [
            .init(label: "Profit this month", value: cur.tidyShort(o.monthProfit), tint: monthTint),
            .init(label: "Profit this year", value: cur.tidyShort(o.yearProfit), tint: yearTint),
            .init(label: "Due in 30 days", value: cur.tidyShort(o.dueWithin30Days), tint: dueTint),
        ]
        return Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Company cash").capsLabel()
                Text(cur.tidyDisplay(company.cash)).font(.hero(34)).foregroundStyle(cashTint).minimumScaleFactor(0.6).lineLimit(1)
                Text(runwayText).font(.system(size: 12)).foregroundStyle(runwayTint).fixedSize(horizontal: false, vertical: true)
                StatStrip(cells: cells)
            }
        }
    }

    private func owedCard(_ cur: Currency, _ o: FinanceOverview) -> some View {
        let h = engine.companyHealth(company)
        let debtTint: Color = h.debt > 0 ? Theme.loss : Theme.ivory
        let taxTint: Color = o.taxesOwed > 0 ? Theme.caution : Theme.ivory
        let cells: [StatStrip.Cell] = [
            .init(label: "Tax and VAT owed", value: cur.tidyShort(o.taxesOwed), tint: taxTint),
            .init(label: "Debt", value: cur.tidyShort(h.debt), tint: debtTint),
            .init(label: "Your account", value: store.short(engine.state.cash)),
        ]
        return CardSection("Owed") {
            VStack(alignment: .leading, spacing: 10) {
                StatStrip(cells: cells, ruled: false)
                loansRow(cur, h.debt)
            }
        }
    }

    /// Compact loans row: what the company owes on loans, (loans are applied for and repaid in the Bank app on the Phone).
    private func loansRow(_ cur: Currency, _ debt: Double) -> some View {
        let loans = engine.state.loans.filter { $0.companyID == company.id && $0.balance > 0 }
        let monthly = loans.reduce(0) { $0 + $1.monthlyPayment }
        let sub: String = loans.isEmpty ? "No loans" : "\(loans.count) \(loans.count == 1 ? "loan" : "loans") · \(cur.tidyShort(monthly)) a month"
        return VStack(alignment: .leading, spacing: 8) {
            FlatRow(label: "Loans", value: cur.tidyShort(debt), sub: sub, rule: true)
        }
    }

    @ViewBuilder private func comingUp(_ cur: Currency, _ o: FinanceOverview) -> some View {
        if !o.upcoming.isEmpty {
            CardSection("Coming up") {
                VStack(spacing: 0) {
                    ForEach(Array(o.upcoming.prefix(4).enumerated()), id: \.element.id) { n, u in
                        FlatRow(label: u.title, value: cur.tidyShort(u.amount), sub: u.detail + " · " + u.dateText, rule: n > 0)
                    }
                }
            }
        }
    }

    @ViewBuilder private func costs(_ cur: Currency, _ o: FinanceOverview) -> some View {
        let lines: [FinanceLine] = o.costsThisMonth
        CardSection(title: "Where the money goes", trailing: {
            Text("This month " + cur.tidyShort(o.costTotalThisMonth)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
        }) {
            if lines.isEmpty {
                Text("No costs booked yet this month.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
            } else {
                VStack(spacing: Theme.Space.m) {
                    HStack(spacing: Theme.Space.l) {
                        Chart(lines) { l in
                            SectorMark(angle: .value("Amount", l.amount), innerRadius: .ratio(0.64), angularInset: 1.5)
                                .foregroundStyle(by: .value("Cost", l.label))
                                .cornerRadius(3)
                        }
                        .chartLegend(.hidden)
                        .chartForegroundStyleScale(range: Self.palette)
                        .frame(width: 112, height: 112)
                        .accessibilityHidden(true)
                        VStack(spacing: 7) {
                            ForEach(Array(lines.prefix(5).enumerated()), id: \.offset) { i, l in
                                HStack(spacing: 6) {
                                    Circle().fill(Self.palette[i % Self.palette.count]).frame(width: 7, height: 7)
                                    Text(l.label).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("\(Int((l.share * 100).rounded()))%").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
                                }
                            }
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { n, l in
                            FlatRow(label: l.label, value: cur.tidyShort(l.amount), rule: n > 0)
                        }
                    }
                }
            }
        }
    }

    private func margins(_ cur: Currency, _ o: FinanceOverview) -> some View {
        let monthMargin: Double = o.monthRevenue > 0 ? o.monthProfit / o.monthRevenue : 0
        let yearMargin: Double = o.yearRevenue > 0 ? o.yearProfit / o.yearRevenue : 0
        let monthTint: Color = o.monthRevenue > 0 && monthMargin < 0 ? Theme.loss : Theme.ivory
        let yearTint: Color = o.yearRevenue > 0 && yearMargin < 0 ? Theme.loss : Theme.ivory
        let monthText: String = o.monthRevenue > 0 ? Currency.percent(monthMargin, decimals: 0) : "–"
        let yearText: String = o.yearRevenue > 0 ? Currency.percent(yearMargin, decimals: 0) : "–"
        let cells: [StatStrip.Cell] = [
            .init(label: "Sales this month", value: cur.tidyShort(o.monthRevenue)),
            .init(label: "Margin this month", value: monthText, tint: monthTint),
            .init(label: "Margin this year", value: yearText, tint: yearTint),
        ]
        return CardSection("Margins") { StatStrip(cells: cells, ruled: false) }
    }

    /// The company's last closed week in a few lines, with a link to all its weekly, monthly and yearly reports.
    @ViewBuilder private func lastWeekReport(_ cur: Currency) -> some View {
        let last = engine.latestReport(.week)?.filtered(to: company.id)
        CardSection(title: "Reports", trailing: {
            NavigationLink { ReportsScreen(companyID: company.id) } label: {
                Text("Week, month, year  →").font(.system(size: 12)).foregroundStyle(Theme.gold)
            }.buttonStyle(.plain)
        }) {
            if let r = last {
                let net: Double = r.group.pnl.netProfit
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(cur.tidyShort(net)).font(.hero(26)).foregroundStyle(net < 0 ? Theme.loss : Theme.ivory)
                        Text("profit · " + r.title).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                    }
                    if let s = ReportSummary.sentences(r, currency: cur).first {
                        Text(s).font(.system(size: 14)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("The first report arrives when this company has been through a full week.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
            }
        }
    }

    // MARK: Table of settings

    /// One row per area of the company's money; each opens a full page (the decisions there are big: dividends, selling, closing).
    private func settingsTable(_ cur: Currency, _ o: FinanceOverview) -> some View {
        let canSell = CompanySale.canSell(engine.state, companyID: company.id)
        let whole: Double = CompanySale.estimatedValue(engine.state, companyID: company.id, data: engine.data)
        let share: String = "You own \(Int(company.ownership.rounded()))%" + (canSell ? ", worth about " + cur.tidyShort(whole * company.ownership / 100) : "")
        let form: String = company.form == .limited ? "Limited company" : "Sole trader"
        let closed: Bool = company.status == .closed
        return SettingsTable(heading: "Money matters") {
            SettingsTableRow(title: "Statements", note: "Profit and loss, balance sheet, cash flow, tax", value: "Month " + cur.tidyShort(o.monthProfit), valueTint: o.monthProfit < 0 ? Theme.loss : Theme.ivory) { part = .accounts }
            SettingsTableRow(title: "Ownership", note: "Dividends, owners, shares, selling", value: share) { part = .owners }
            SettingsTableRow(title: "Legal form and trading", note: "Sole trader or limited, rename, close for a while or wind up", value: closed ? "Closed for now" : form, valueTint: closed ? Theme.caution : Theme.ivory) { part = .settings }
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
            CardSection("Behind on payments") {
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
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: tint == Theme.ivoryMuted ? "info.circle" : "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(tint).padding(.top, 2)
            Text(text).font(.system(size: 13.5, weight: tint == Theme.ivoryMuted ? .regular : .medium)).foregroundStyle(tint == Theme.ivoryMuted ? Theme.ivoryMuted : Theme.ivory).fixedSize(horizontal: false, vertical: true)
        }
    }
}


// MARK: Ownership (company decisions)

/// Company decisions: dividend, owners and shares, going public, buy-back, selling. Payments are in the Bank app.
struct CompanyOwnerMoney: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var amount = 0.0
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if company.form == .limited {
                CardSection(title: "Pay a dividend", trailing: {
                    Text("Company cash " + cur.tidyShort(company.cash)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }) {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        AmountField(title: "Amount", currency: cur, amount: $amount)
                        Button("Pay a dividend…") { confirmDividend(cur) }.buttonStyle(QuietButtonStyle())
                        Text("Most you can pay out now: \(cur.tidyDisplay(engine.maximumDividend(companyID: company.id))). Dividends come from retained profit and are taxed on your return.")
                            .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            CompanyOwnershipSection(engine: engine, company: company)
            CompanySaleSection(engine: engine, company: company)
        }
        .confirmAction($pending)
    }

    private func confirmDividend(_ cur: Currency) {
        guard amount > 0 else { Haptics.warning(); store.show("Enter an amount first.", tone: "warn"); return }
        let amt = amount
        let after: Double = max(0, company.cash - amt)
        let most: Double = engine.maximumDividend(companyID: company.id)
        let message: String = "The cash leaves the company for good: \(cur.tidyDisplay(after)) stays in it. Dividend tax is due on your personal return; co-owners get their share. Most you can pay now: \(cur.tidyDisplay(most))."
        pending = PendingAction(title: "Pay \(cur.tidyDisplay(amt)) as a dividend?", message: message, button: "Pay dividend", destructive: true) {
            switch store.act({ $0.payDividend(companyID: company.id, amount: amt) }) {
            case .ok?: Haptics.success(); amount = 0; store.show("Dividend of \(cur.tidyDisplay(amt)) paid.", tone: "good")
            case .noRetainedProfit?: Haptics.warning(); store.show("There are no retained profits to pay out.", tone: "warn")
            case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in the company.", tone: "warn")
            case nil: break
            default: Haptics.warning(); store.show("A dividend of that size is not possible now.", tone: "warn")
            }
        }
    }
}
