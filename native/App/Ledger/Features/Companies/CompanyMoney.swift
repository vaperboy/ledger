import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

struct CompanyMoney: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var amount = 0.0
    @State private var loanAmount = 0.0

    var body: some View {
        let cur = engine.currency(for: company)
        let books = company.books
        VStack(spacing: Theme.Space.l) {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Company cash").capsLabel()
                    Text(cur.display(company.cash)).font(.hero(34)).foregroundStyle(company.cash < 0 ? Theme.loss : Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                    HStack(spacing: 8) {
                        Chip(text: "Your account " + store.short(engine.state.cash), tint: Theme.ivoryMuted, symbol: "person.fill")
                        if company.vatBalance > 0 { Chip(text: "VAT owed " + cur.short(company.vatBalance), tint: Theme.caution) }
                    }
                }
            }
            let o = engine.financeOverview(companyID: company.id)
            if !o.upcoming.isEmpty || o.taxesOwed > 0 {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        HStack(alignment: .firstTextBaseline) {
                            SectionLabel("Coming up")
                            Spacer()
                            if o.taxesOwed > 0 { Text("Tax and VAT owed " + cur.short(o.taxesOwed)).font(.caption).foregroundStyle(Theme.caution) }
                        }
                        ForEach(o.upcoming.prefix(4)) { u in
                            ListRow(symbol: u.essential ? "lock.fill" : "calendar", tint: Theme.ivoryMuted, title: u.title, subtitle: u.detail, trailing: cur.short(u.amount), trailingSub: u.dateText)
                        }
                        NavigationLink { FinanceView(companyID: company.id) } label: {
                            Text("Taxes, costs and reports").font(.caption.weight(.semibold)).foregroundStyle(Theme.gold)
                        }.buttonStyle(.plain)
                    }
                }
            }
            lastWeekReport(cur)
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Move money")
                    AmountField(title: "Amount", currency: cur, amount: $amount)
                    HStack {
                        Button("Put in") { putIn() }.buttonStyle(QuietButtonStyle())
                        if company.form == .limited {
                            Button("Dividend") { dividend() }.buttonStyle(QuietButtonStyle())
                        } else {
                            Button("Take out") { takeOut() }.buttonStyle(QuietButtonStyle())
                        }
                    }
                    if company.form == .limited {
                        let maxDiv = engine.maximumDividend(companyID: company.id)
                        Text("Most you can pay out now: \(cur.display(maxDiv)). Dividends are taxed on your return.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionLabel("Profit and loss")
                    HStack { Text("").frame(maxWidth: .infinity, alignment: .leading); header("Week"); header("Month"); header("Year") }
                    row("Revenue", "rev", books, cur)
                    row("Cost of sales", "cogs", books, cur)
                    row("Wages", "wages", books, cur)
                    row("Rent", "rent", books, cur)
                    row("Marketing", "mkt", books, cur)
                    row("Interest", "int", books, cur)
                    HStack {
                        SectionLabel("Profit"); Spacer()
                        figure(Books.profit(books.week), cur); figure(Books.profit(books.month), cur); figure(Books.profit(books.year), cur)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Borrow for this company")
                    AmountField(title: "Loan amount", currency: cur, amount: $loanAmount)
                    let offer = engine.loanOffer(kind: "biz", amount: loanAmount, companyID: company.id)
                    Text("The bank would lend up to \(cur.display(offer.maximum)) at about \(Currency.percent(engine.state.economy.policyRate + offer.margin, decimals: 1)).")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    Button("Take a 5-year loan") { borrow() }.buttonStyle(QuietButtonStyle())
                    ForEach(engine.state.loans.filter { $0.companyID == company.id }) { l in
                        ListRow(symbol: "doc.text.fill", tint: Theme.loss, title: l.name, subtitle: "\(cur.display(l.monthlyPayment)) a month", trailing: cur.display(l.balance), trailingSub: "left to pay")
                    }
                }
            }
        }
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
                        Text(cur.short(r.group.pnl.netProfit)).font(.hero(26)).foregroundStyle(r.group.pnl.netProfit < 0 ? Theme.loss : Theme.ivory)
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

    private func header(_ s: String) -> some View { Text(s).font(.label).foregroundStyle(Theme.ivoryFaint).frame(width: 70, alignment: .trailing) }
    private func figure(_ v: Double, _ cur: Currency) -> some View {
        Text(cur.short(v)).font(.system(.caption, design: .default).monospacedDigit()).foregroundStyle(Theme.change(v) == Theme.ivoryMuted ? Theme.ivory : Theme.change(v)).frame(width: 70, alignment: .trailing)
    }
    private func row(_ title: String, _ key: String, _ b: Books, _ cur: Currency) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(Theme.ivoryMuted); Spacer()
            ForEach([b.week, b.month, b.year], id: \.self) { dict in
                Text(cur.short(dict[key] ?? 0)).font(.system(.caption, design: .default).monospacedDigit()).foregroundStyle(Theme.ivory).frame(width: 70, alignment: .trailing)
            }
        }
    }

    private func putIn() {
        guard amount > 0 else { return }
        if store.act({ $0.putMoneyInto(companyID: company.id, amount: amount) }) == true { Haptics.success(); store.show("Moved in.", tone: "good") }
        else { Haptics.warning(); store.show("You don't have that much available.", tone: "warn") }
    }
    private func takeOut() {
        guard amount > 0 else { return }
        switch store.act({ $0.takeMoneyOut(companyID: company.id, amount: amount) }) {
        case .ok?: Haptics.success(); store.show("Moved to your account.", tone: "good")
        case .dividendOnly?: store.show("A limited company can only pay dividends.", tone: "warn")
        default: Haptics.warning(); store.show("The company doesn't have that much.", tone: "warn")
        }
    }
    private func dividend() {
        guard amount > 0 else { return }
        switch store.act({ $0.payDividend(companyID: company.id, amount: amount) }) {
        case .ok?: Haptics.success(); store.show("Dividend paid.", tone: "good")
        case .noRetainedProfit?: store.show("There are no retained profits to pay out.", tone: "warn")
        case .notEnoughCash?: store.show("Not enough cash in the company.", tone: "warn")
        default: store.show("Not possible.", tone: "warn")
        }
    }
    private func borrow() {
        guard loanAmount > 0 else { return }
        switch store.act({ $0.takeLoan(kind: "biz", amount: loanAmount, termMonths: 60, companyID: company.id) }) {
        case .ok?: Haptics.success(); store.show("Loan granted.", tone: "good")
        case .tooSmall?: store.show("The bank won't lend that little.", tone: "warn")
        default: Haptics.warning(); store.show("The bank declined.", tone: "bad")
        }
    }
}
