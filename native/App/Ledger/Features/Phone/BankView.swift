import SwiftUI
import GameCore
import Countries
import Finance
import Investments
import Simulation

/// Accounts, savings, loans and borrowing: a section of the Money tab.
struct BankContent: View {
    @EnvironmentObject var store: GameStore
    @State private var amount = 0.0
    @State private var borrow = 0.0
    @State private var repayAmount = 0.0

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            let s = e.state
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cash and savings").capsLabel()
                    Text(cur.display(s.cash + s.savings)).font(.hero(36)).foregroundStyle(s.cash + s.savings < 0 ? Theme.loss : Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                    KeyFigures(items: [
                        .init(label: "Current account", value: store.short(s.cash), tint: s.cash < 0 ? Theme.loss : Theme.ivory),
                        .init(label: "Credit", value: Banking.creditWord(s.credit)),
                        .init(label: "Bank rate", value: Currency.percent(s.economy.policyRate, decimals: 2)),
                    ]).padding(.top, 8)
                }
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionLabel("Accounts")
                        ListRow(symbol: "creditcard.fill", tint: Theme.ivoryMuted, title: "Current account", subtitle: "Everyday money", trailing: cur.display(s.cash), trailingTint: s.cash < 0 ? Theme.loss : Theme.ivory)
                        ListRow(symbol: "building.columns.fill", tint: Theme.ivoryMuted, title: "Savings", subtitle: "Earns interest, can be moved any day", trailing: cur.display(s.savings))
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionLabel("Savings")
                        AmountField(title: "Amount", currency: cur, amount: $amount)
                        HStack {
                            Button("Save") { move(amount) }.buttonStyle(QuietButtonStyle())
                            Button("Withdraw") { move(-amount) }.buttonStyle(QuietButtonStyle())
                        }
                        ForEach(e.deposits) { d in ListRow(symbol: "lock.fill", tint: Theme.gold, title: "Fixed deposit", subtitle: "\(d.weeksLeft) weeks left", trailing: cur.display(d.balance)) }
                        HStack {
                            ForEach([13, 26, 52], id: \.self) { w in
                                Button("Lock \(w) wk") {
                                    if store.act({ $0.openDeposit(amount: amount, weeks: w) }) == true { Haptics.success() } else { Haptics.warning(); store.show("Not enough cash.", tone: "warn") }
                                }.buttonStyle(QuietButtonStyle())
                            }
                        }
                        Text("A longer lock pays a little more. The money is out of reach until it matures.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionLabel("Loans")
                        let loans = s.loans.filter { $0.companyID == 0 }
                        if loans.isEmpty { Text("You owe nothing personally.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
                        ForEach(loans) { l in
                            ListRow(symbol: "doc.text.fill", tint: Theme.loss, title: l.name,
                                    subtitle: "Interest \(Currency.percent(Banking.rate(of: l, state: s), decimals: 2)) · \(cur.display(l.monthlyPayment)) a month",
                                    trailing: cur.display(l.balance), trailingSub: "left to pay")
                        }
                        if !loans.isEmpty {
                            AmountField(title: "Pay back", currency: cur, amount: $repayAmount)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(loans) { l in
                                        Button("Repay \(l.name)") {
                                            if store.act({ $0.repayLoan(id: l.id, amount: repayAmount) }) == true { Haptics.success(); store.show("Paid.", tone: "good") }
                                            else { Haptics.warning(); store.show("Not possible.", tone: "warn") }
                                        }.buttonStyle(QuietButtonStyle())
                                    }
                                }
                            }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionLabel("Borrow")
                        AmountField(title: "Amount", currency: cur, amount: $borrow)
                        let offer = e.loanOffer(kind: "cons", amount: borrow, companyID: nil)
                        Text("The bank would lend up to \(cur.display(offer.maximum)) at about \(Currency.percent(s.economy.policyRate + offer.margin, decimals: 1)) (\(offer.creditBand)).")
                            .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        Button("Take a 5-year personal loan") {
                            switch store.act({ $0.takeLoan(kind: "cons", amount: borrow, termMonths: 60, companyID: nil) }) {
                            case .ok?: Haptics.success(); store.show("Loan granted.", tone: "good")
                            case .tooSmall?: store.show("Too small for the bank.", tone: "warn")
                            default: Haptics.warning(); store.show("The bank declined.", tone: "bad")
                            }
                        }.buttonStyle(QuietButtonStyle())
                    }
                }
            }
        }
    }

    private func move(_ a: Double) {
        guard a != 0 else { return }
        if store.act({ $0.moveToSavings(a) }) == true { Haptics.success() } else { Haptics.warning(); store.show("Not enough there.", tone: "warn") }
    }
}
