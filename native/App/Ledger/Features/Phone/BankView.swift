import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

/// The Loans tab of an account: only the loans taken for this account, their terms, early repayment, and a new loan with a chosen term
/// and the whole cost shown first. A company's loans use the company loan screen (`CompanyLoans`, the same engine calls); the personal
/// account's are below. Loans are never an account of their own.
struct BankLoansTab: View {
    @EnvironmentObject var store: GameStore
    var account: BankAccountID
    var loans: [BankLoan]

    @State private var applying = false

    var body: some View {
        if let e = store.engine {
            VStack(alignment: .leading, spacing: 12) {
                if account != .investments { applyCard(e) }
                loansFor(e)
            }
            .fullScreenCover(isPresented: $applying) { BankLoanApplyFlow(account: account) }
        }
    }

    @ViewBuilder private func loansFor(_ e: GameEngine) -> some View {
        switch account {
        case .company(let cid):
            if let co = e.state.company(cid) { CompanyLoans(engine: e, company: co) }
        case .personal:
            BankPersonalLoans(engine: e)
        case .investments:
            Text("Loans are taken for your personal account or a company's, not for investments.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
        }
    }

    private func applyCard(_ e: GameEngine) -> some View {
        let kind: String = account.companyID == nil ? "cons" : "biz"
        let q = e.loanApplicationQuote(kind: kind, amount: 0, termMonths: 36, companyID: account.companyID)
        let cur: Currency = account.companyID.flatMap { e.state.company($0) }.map { e.currency(for: $0) } ?? e.homeCurrency
        let sub: String = q.maximum > 0 ? "The bank would lend up to \(cur.tidyShort(q.maximum)) today" : "The bank would not lend at the moment"
        return Button { Haptics.tap(); applying = true } label: {
            CardRow(glyph: BankGlyph.transfer, title: "Apply for a loan", subtitle: sub, value: Currency.percent(q.yearlyRate, decimals: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bank-apply-loan")
    }
}

/// Your personal loans and borrowing.
struct BankPersonalLoans: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var repaying: Loan?

    var body: some View {
        let e = engine
        let cur = e.homeCurrency
        let s = e.state
        let personal = s.loans.filter { $0.companyID == 0 && $0.balance > 0 }
        let owed = personal.reduce(0) { $0 + $1.balance }
        let monthly = personal.reduce(0) { $0 + $1.monthlyPayment }
        let missed = personal.reduce(0) { $0 + $1.int("miss") }
        VStack(alignment: .leading, spacing: 12) {
            BankCard(title: "You owe") {
                VStack(alignment: .leading, spacing: 8) {
                    KeyFigures(items: [
                        .init(label: "You owe", value: owed > 0 ? store.short(owed) : "Nothing", tint: owed > 0 ? Theme.caution : Theme.ivory, sub: personal.isEmpty ? "" : "\(store.short(monthly)) a month"),
                        .init(label: "Credit", value: Banking.creditWord(s.credit), sub: "bank rate \(Currency.percent(s.economy.policyRate, decimals: 2))"),
                    ], columns: 2)
                    if missed > 0 {
                        Label("\(missed) loan instalment\(missed == 1 ? "" : "s") missed. Pay it before the next week: a missed payment adds a penalty and hurts your credit.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Theme.loss).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            loansCard(e, cur, personal)
        }
        .sheet(item: $repaying) { l in RepayPersonalLoanSheet(loanID: l.id).presentationDetents([.medium, .large]) }
    }

    private func loansCard(_ e: GameEngine, _ cur: Currency, _ loans: [Loan]) -> some View {
        BankCard(title: "Your loans") {
            VStack(alignment: .leading, spacing: 0) {
                if loans.isEmpty { Text("You owe nothing personally.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted) }
                ForEach(Array(loans.enumerated()), id: \.element.id) { n, l in
                    if n > 0 { Hairline() }
                    Button { repaying = l } label: { loanRow(e, cur, l) }.buttonStyle(.plain)
                }
                if !loans.isEmpty {
                    Text("Tap a loan to pay some or all of it back early. Early repayment has no fee and cuts the interest still to come.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6)
                }
            }
        }
    }

    private func loanRow(_ e: GameEngine, _ cur: Currency, _ l: Loan) -> some View {
        let p = e.loanPayoff(loanID: l.id)
        let paid = l.originalAmount > 0 ? max(0, min(1, 1 - l.balance / l.originalAmount)) : 0
        let missed = l.int("miss")
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(l.name).font(.system(size: 14)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text("\(Currency.percent(p?.yearlyRate ?? Banking.rate(of: l, state: e.state), decimals: 2)) · \(cur.tidyShort(l.monthlyPayment)) a month" + (p?.monthsLeft.map { " · \($0) months to go" } ?? ""))
                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                Text("\(Int((paid * 100).rounded()))% repaid" + ((p?.interestLeft ?? 0) > 0 ? " · about \(cur.tidyShort(p!.interestLeft)) interest still to come" : ""))
                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                if missed > 0 { Text("\(missed) instalment\(missed == 1 ? "" : "s") missed").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.loss) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(cur.tidyShort(l.balance)).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.ivory)
                Text("left to pay").font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }
        .padding(.vertical, 9).contentShape(Rectangle())
    }
}

/// Pay back part or all of one loan: presets for one instalment, half and everything, with the balance after.
struct RepayPersonalLoanSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var loanID: Int
    @State private var amount = 0.0

    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = store.engine, let l = e.state.loans.first(where: { $0.id == loanID }) {
                    let cur = l.companyID == 0 ? e.homeCurrency : (e.state.company(l.companyID).map { e.currency(for: $0) } ?? e.homeCurrency)
                    let p = e.loanPayoff(loanID: l.id)
                    let pay = min(amount, l.balance)
                    let available = l.companyID == 0 ? e.state.cash + e.state.savings : (e.state.company(l.companyID)?.cash ?? 0)
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(l.name).capsLabel()
                            Text(cur.tidyDisplay(l.balance)).font(.hero(34))
                            Text("left to pay · \(cur.tidyShort(l.monthlyPayment)) a month" + (p?.monthsLeft.map { " · \($0) months to go" } ?? "")).font(.caption).foregroundStyle(Theme.ivoryFaint)
                        }
                        HStack {
                            Button("One instalment") { amount = min(l.balance, l.monthlyPayment) }.buttonStyle(SmallOutlineButtonStyle())
                            Button("Half") { amount = (l.balance / 2).rounded() }.buttonStyle(SmallOutlineButtonStyle())
                            Button("All") { amount = l.balance }.buttonStyle(SmallOutlineButtonStyle())
                        }
                        AmountField(title: "Pay back", currency: cur, amount: $amount)
                        KeyFigures(items: [
                            .init(label: "You pay now", value: pay > 0 ? cur.tidyShort(pay) : "–"),
                            .init(label: "Left after", value: cur.tidyShort(max(0, l.balance - pay))),
                            .init(label: "Available", value: cur.tidyShort(available), tint: available < pay ? Theme.loss : Theme.ivory, sub: l.companyID == 0 ? "cash and savings" : "company cash"),
                        ])
                        Text("The monthly payment stays the same, so the loan ends sooner; paying it all closes it.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        Button(pay > 0 ? "Pay back \(cur.tidyShort(pay))" : "Choose an amount") {
                            if store.act({ $0.repayLoan(id: loanID, amount: pay) }) == true {
                                Haptics.success()
                                store.show(pay >= l.balance - 0.5 ? "\(l.name) is paid off." : "\(cur.tidyShort(pay)) paid back.", tone: "good")
                                dismiss()
                            } else { Haptics.warning(); store.show("Not enough money to pay that back.", tone: "warn") }
                        }.buttonStyle(GoldButtonStyle()).disabled(pay <= 0)
                    }
                    .padding(Theme.Space.margin)
                } else {
                    Text("This loan is paid off.").foregroundStyle(Theme.ivoryMuted).padding()
                }
            }
            .ledgerBackground()
            .navigationTitle("Pay back").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
