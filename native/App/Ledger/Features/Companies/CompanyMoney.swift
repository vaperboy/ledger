import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Events
import Simulation

/// The parts of a company's Finances tab. Summary, Statements, Ownership and Settings are the tab row; Payroll and Loans (the hands-on
/// money controls) open from the Summary and stay available beside the Bank app.
enum CompanyMoneyPart: String, CaseIterable, Hashable {
    case summary = "Summary", accounts = "Statements", payroll = "Payroll", loans = "Loans", owners = "Ownership", settings = "Settings"
    /// The tab row: payroll and loans open from the Summary instead.
    static let tabs: [CompanyMoneyPart] = [.summary, .accounts, .owners, .settings]
}

/// A titled card: the small champagne label above a bordered card holding the content (the new-look replacement of a ruled section).
struct CardSection<Content: View, Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).capsLabel()
                Spacer(minLength: 8)
                trailing()
            }
            Card(padding: 14, radius: Theme.Radius.card) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
extension CardSection where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

/// "Open in Bank": all money handling (transfers, loans, deposits, taxes, bills, payroll approval, statements) lives in the Bank app.
/// Opens the Bank app (plain navigation, so no toast). The Bank app has no per-account link yet, so it opens on its account list.
struct OpenInBankButton: View {
    @EnvironmentObject var store: GameStore
    var title = "Open in Bank"
    var body: some View {
        QuietButton(title: title, fullWidth: true) { store.openApp(.bank) }
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
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            SectionTabs(items: CompanyMoneyPart.tabs, title: { $0.rawValue }, selection: $part, sub: true).padding(.horizontal, -Theme.Space.margin)
            switch part {
            case .summary: CompanyMoneySummary(engine: engine, company: company, part: $part)
            case .accounts: CompanyAccounts(engine: engine, company: company)
            case .payroll, .loans: CompanyBankDesk(engine: engine, company: company, part: $part)
            case .owners: CompanyOwnerMoney(engine: engine, company: company)
            case .settings: CompanySettings(engine: engine, company: company)
            }
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
            owedCard(cur, o)
            comingUp(cur, o)
            costs(cur, o)
            margins(cur, o)
            lastWeekReport(cur)
            ownershipCard(cur)
            Button { Haptics.choose(); withAnimation(.snappy(duration: 0.2)) { part = .payroll } } label: {
                CardRow(glyph: Glyph.bank, title: "Payroll, bills and loans", subtitle: "Pay day, what falls due, loans, putting money in or taking it out")
            }.buttonStyle(.plain)
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
                OpenInBankButton()
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
                Text("Taxes, bills and loan instalments are paid in the Bank app.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                OpenInBankButton(title: "Pay taxes and loans in Bank")
            }
        }
    }

    @ViewBuilder private func comingUp(_ cur: Currency, _ o: FinanceOverview) -> some View {
        if !o.upcoming.isEmpty {
            CardSection("Coming up") {
                VStack(spacing: 0) {
                    ForEach(Array(o.upcoming.prefix(4).enumerated()), id: \.element.id) { n, u in
                        FlatRow(label: u.title, value: cur.tidyShort(u.amount), sub: u.detail + " · " + u.dateText, rule: n > 0)
                    }
                    OpenInBankButton(title: "Approve and pay in Bank").padding(.top, 10)
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

    /// Who owns the company and what the owner's share would fetch. The decisions are in the Ownership tab.
    private func ownershipCard(_ cur: Currency) -> some View {
        let owners = engine.owners(companyID: company.id)
        let canSell = CompanySale.canSell(engine.state, companyID: company.id)
        let whole: Double = CompanySale.estimatedValue(engine.state, companyID: company.id, data: engine.data)
        let value: Double = whole * company.ownership / 100
        var parts: [String] = ["You own \(Int(company.ownership.rounded()))%"]
        if !owners.isEmpty { parts.append("\(owners.count) other \(owners.count == 1 ? "owner" : "owners")") }
        if canSell { parts.append("your share is worth about " + cur.tidyShort(value)) }
        let line: String = parts.joined(separator: " · ")
        return Button { Haptics.choose(); withAnimation(.snappy(duration: 0.2)) { part = .owners } } label: {
            CardRow(glyph: Glyph.person, title: "Ownership and sale value", subtitle: line)
        }.buttonStyle(.plain)
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


// MARK: Payroll, loans and moving money

/// Payroll, bills, loans and money between you and the company. The Bank app is where this is done; these controls are the same
/// engine actions, kept reachable from here until the Bank lists this company's account.
struct CompanyBankDesk: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var part: CompanyMoneyPart

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Button { Haptics.choose(); withAnimation(.snappy(duration: 0.2)) { part = .summary } } label: {
                HStack(spacing: 6) {
                    GlyphView(glyph: Glyph.back, size: 12, weight: 2, tint: Theme.gold)
                    Text("Summary").font(.system(size: 13)).foregroundStyle(Theme.gold)
                }
            }.buttonStyle(.plain)
            Card(padding: 14, radius: Theme.Radius.hero) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Handled in the Bank").capsLabel()
                    Text("Payroll, bills, taxes, loans and moving money are done in the Bank app. The same controls for \(company.name) are below.")
                        .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    OpenInBankButton()
                }
            }
            CompanyPayroll(engine: engine, company: company)
            CompanyMoneyMoves(engine: engine, company: company)
            CompanyLoans(engine: engine, company: company)
        }
    }
}

/// Money between you and the company (put in, take out) and the owner's salary.
struct CompanyMoneyMoves: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var amount = 0.0
    @State private var salary = 0.0

    var body: some View {
        let cur = engine.currency(for: company)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            CardSection(title: "Move money", trailing: {
                Text("Your account " + store.short(engine.state.cash)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    AmountField(title: "Amount", currency: cur, amount: $amount)
                    HStack {
                        Button("Put in") { putIn(cur) }.buttonStyle(QuietButtonStyle())
                        if company.form != .limited {
                            Button("Take out") { takeOut(cur) }.buttonStyle(QuietButtonStyle())
                        }
                    }
                    if amount > 0 {
                        Text("Company cash after putting in: \(cur.tidyDisplay(company.cash + amount)).")
                            .font(.caption2.monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                    }
                    if company.form == .limited {
                        Text("A limited company pays money out as dividends (Ownership) or salary.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    } else {
                        Text("A sole trader's money is yours: taking it out is not taxed again, the profit already is.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            }
            if company.form == .limited {
                CardSection(title: "Your salary", trailing: {
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
        }
        .onAppear { salary = company.ownerMonthlySalary }
    }

    private func putIn(_ cur: Currency) {
        guard amount > 0 else { Haptics.warning(); store.show("Enter an amount first.", tone: "warn"); return }
        let v = amount
        if store.act({ $0.putMoneyInto(companyID: company.id, amount: v) }) == true { Haptics.success(); store.show("\(cur.tidyDisplay(v)) moved into \(company.name).", tone: "good") }
        else { Haptics.warning(); store.show("You don't have \(cur.tidyDisplay(v)) available.", tone: "warn") }
    }
    private func takeOut(_ cur: Currency) {
        guard amount > 0 else { Haptics.warning(); store.show("Enter an amount first.", tone: "warn"); return }
        let v = amount
        switch store.act({ $0.takeMoneyOut(companyID: company.id, amount: v) }) {
        case .ok?: Haptics.success(); store.show("\(cur.tidyDisplay(v)) moved to your account.", tone: "good")
        case .dividendOnly?: Haptics.warning(); store.show("A limited company can only pay dividends.", tone: "warn")
        case nil: break
        default: Haptics.warning(); store.show("The company doesn't have \(cur.tidyDisplay(v)).", tone: "warn")
        }
    }
    private func setSalary(_ v: Double, _ cur: Currency) {
        let result = store.act { $0.setOwnerSalary(companyID: company.id, monthly: v) }
        let now = store.engine?.state.company(company.id)?.ownerMonthlySalary ?? 0
        salary = now
        store.settle(result, now > 0 ? "Your salary is now \(cur.tidyDisplay(now)) a month." : "You no longer take a salary.", same: "Your salary is already that.")
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
