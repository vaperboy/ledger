import SwiftUI
import GameCore
import Countries
import Finance
import Investments
import Simulation

struct BankView: View {
    @EnvironmentObject var store: GameStore
    @State private var amount = 0.0
    @State private var borrow = 0.0
    @State private var repayAmount = 0.0

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            let s = e.state
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            SectionLabel("Accounts")
                            ValueRow(label: "Current account", value: cur.format(s.cash), tint: s.cash < 0 ? Theme.loss : Theme.ivory)
                            ValueRow(label: "Savings", value: cur.format(s.savings))
                            ValueRow(label: "Credit standing", value: Banking.creditWord(s.credit))
                            ValueRow(label: "Central bank rate", value: Currency.percent(s.economy.policyRate, decimals: 2))
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
                            ForEach(e.deposits) { d in ValueRow(label: "Fixed deposit · \(d.weeksLeft) wk left", value: cur.format(d.balance)) }
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
                                VStack(alignment: .leading, spacing: 4) {
                                    ValueRow(label: l.name, value: cur.format(l.balance))
                                    ValueRow(label: "Monthly payment", value: cur.format(l.monthlyPayment))
                                    Text("Interest \(Currency.percent(Banking.rate(of: l, state: s), decimals: 2))").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                                }
                                Divider().overlay(Theme.hairline)
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
                            Text("The bank would lend up to \(cur.format(offer.maximum)) at about \(Currency.percent(s.economy.policyRate + offer.margin, decimals: 1)) (\(offer.creditBand)).")
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
                .padding(Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .ledgerBackground()
            .navigationTitle("Bank")
        }
    }

    private func move(_ a: Double) {
        guard a != 0 else { return }
        if store.act({ $0.moveToSavings(a) }) == true { Haptics.success() } else { Haptics.warning(); store.show("Not enough there.", tone: "warn") }
    }
}
