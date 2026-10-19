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
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Move money")
                    Text("Your account: \(store.money(engine.state.cash))").font(.caption).foregroundStyle(Theme.ivoryMuted)
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
                        Text("Most you can pay out now: \(cur.format(maxDiv)). Dividends are taxed on your return.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
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
                        Text("Profit").font(.bodyText.weight(.semibold)); Spacer()
                        figure(Books.profit(books.week), cur); figure(Books.profit(books.month), cur); figure(Books.profit(books.year), cur)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Borrow for this company")
                    AmountField(title: "Loan amount", currency: cur, amount: $loanAmount)
                    let offer = engine.loanOffer(kind: "biz", amount: loanAmount, companyID: company.id)
                    Text("The bank would lend up to \(cur.format(offer.maximum)) at about \(Currency.percent(engine.state.economy.policyRate + offer.margin, decimals: 1)).")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    Button("Take a 5-year loan") { borrow() }.buttonStyle(QuietButtonStyle())
                    ForEach(engine.state.loans.filter { $0.companyID == company.id }) { l in
                        ValueRow(label: l.name, value: cur.format(l.balance))
                    }
                }
            }
        }
    }

    private func header(_ s: String) -> some View { Text(s).font(.label).foregroundStyle(Theme.ivoryFaint).frame(width: 70, alignment: .trailing) }
    private func figure(_ v: Double, _ cur: Currency) -> some View {
        Text(cur.short(v)).font(.system(.caption, design: .serif).monospacedDigit()).foregroundStyle(Theme.change(v) == Theme.ivoryMuted ? Theme.ivory : Theme.change(v)).frame(width: 70, alignment: .trailing)
    }
    private func row(_ title: String, _ key: String, _ b: Books, _ cur: Currency) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(Theme.ivoryMuted); Spacer()
            ForEach([b.week, b.month, b.year], id: \.self) { dict in
                Text(cur.short(dict[key] ?? 0)).font(.system(.caption, design: .serif).monospacedDigit()).foregroundStyle(Theme.ivory).frame(width: 70, alignment: .trailing)
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
