import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

/// The Loans tab of an account: only the loans taken for this account, their terms, early repayment, and a new loan with a chosen term
/// and the whole cost shown first. A company's loans use the company loan screen (`CompanyLoans`, the same engine calls); the personal
/// account's are below. Loans are never an account of their own.
struct BankLoansTab: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var account: BankAccountID
    var loans: [BankLoan]

    @State private var applying = false

    var body: some View {
        if let e = store.engine {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                switch account {
                case .company(let cid):
                    applyButton
                    if let co = e.state.company(cid) { CompanyLoans(engine: e, company: co) }
                case .personal:
                    BankPersonalLoans(engine: e, onApply: { applying = true })
                case .investments:
                    EmptyState(glyph: BankGlyph.transfer, title: "No loans here", message: "Loans are taken for your personal account or a company's, not for investments.")
                }
            }
            .centerSheet(isPresented: $applying, size: .tall) { BankLoanApplyFlow(account: account) }
        }
    }

    /// The one action of the tab: ask the bank for a loan (its offer comes first, then the amount).
    private var applyButton: some View {
        BankApplyLoanButton { applying = true }
    }
}

/// "Apply for a loan": the tab's filled action, with the one line that says what follows.
struct BankApplyLoanButton: View {
    @Environment(\.outsidePalette) private var P
    var action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Button { Haptics.tap(); action() } label: { Text("Apply for a loan") }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("bank-apply-loan")
            Text("See the bank's offer first, then choose how much.").textStyle(.caption, tint: P.inkFaint)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

/// Your personal loans: what you owe as the figure that leads, the credit line under it, Apply, then each loan (it opens its details).
struct BankPersonalLoans: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var onApply: (() -> Void)? = nil
    @State private var repaying: Loan?

    var body: some View {
        let e = engine
        let cur = e.homeCurrency
        let s = e.state
        let personal = s.loans.filter { $0.companyID == 0 && $0.balance > 0 }
        let owed = personal.reduce(0) { $0 + $1.balance }
        let monthly = personal.reduce(0) { $0 + $1.monthlyPayment }
        let missed = personal.reduce(0) { $0 + $1.int("miss") }
        let credit: String = "Credit " + Banking.creditWord(s.credit).lowercased() + " \u{00B7} bank rate " + Currency.percent(s.economy.policyRate, decimals: 2)
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                MoneyHero(label: "You owe", value: owed > 0 ? store.money(owed) : "Nothing", tint: owed > 0 ? P.ink : P.inkSoft,
                          context: (owed > 0 ? "\(store.short(monthly)) a month \u{00B7} " : "") + credit)
                if missed > 0 {
                    HStack(alignment: .top, spacing: Theme.Space.m) {
                        LedgerGlyph(glyph: Glyph.warning, size: Theme.Icon.medium, tint: P.loss)
                        Text("\(missed) instalment\(missed == 1 ? "" : "s") missed. Pay before next week: a missed payment adds a penalty and hurts your credit.")
                            .textStyle(.caption, tint: P.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.loss.opacity(0.10)))
                }
                if let onApply { BankApplyLoanButton(action: onApply) }
            }
            loansCard(e, cur, personal)
        }
        .centerSheet(item: $repaying, title: "Loan details") { l in LoanDetailSheet(loanID: l.id) }
    }

    private func loansCard(_ e: GameEngine, _ cur: Currency, _ loans: [Loan]) -> some View {
        MoneyGroup("Your loans") {
            if loans.isEmpty { EmptyState(glyph: Glyph.check, title: "You owe nothing personally.", centered: false).padding(.vertical, Theme.Space.s) }
            ForEach(Array(loans.enumerated()), id: \.element.id) { n, l in
                if n > 0 { MoneyRule(inset: 0) }
                Button { Haptics.tap(); repaying = l } label: { loanRow(e, cur, l) }.buttonStyle(AcctPressStyle())
            }
        }
    }

    /// Name and terms on the left, what is left to pay and how much is repaid on the right.
    private func loanRow(_ e: GameEngine, _ cur: Currency, _ l: Loan) -> some View {
        let p = e.loanPayoff(loanID: l.id)
        let paid = l.originalAmount > 0 ? max(0, min(1, 1 - l.balance / l.originalAmount)) : 0
        let missed = l.int("miss")
        let terms: String = "\(Currency.percent(p?.yearlyRate ?? Banking.rate(of: l, state: e.state), decimals: 2)) \u{00B7} \(cur.tidyShort(l.monthlyPayment)) a month"
            + (p?.monthsLeft.map { " \u{00B7} \($0) months" } ?? "")
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.name.tidyText).textStyle(.headline).lineLimit(1)
                    Text(terms.tidyText).textStyle(.caption).lineLimit(2)
                    if missed > 0 { Text("\(missed) instalment\(missed == 1 ? "" : "s") missed").textStyle(.caption, tint: P.loss, weight: .medium) }
                }
                Spacer(minLength: Theme.Space.s)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(cur.tidyShort(l.balance)).textStyle(.headline, numeric: true).moneyFlash(l.balance)
                    Text("\(Int((paid * 100).rounded()))% repaid").textStyle(.caption, tint: P.inkFaint, numeric: true)
                }
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint)
            }
            ProgressLine(fraction: paid, height: 3)
        }
        .padding(.vertical, Theme.Space.m).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Pay back part or all of one loan: presets for one instalment, half and everything, with the balance after.
struct RepayPersonalLoanSheet: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var loanID: Int
    @State private var amount = 0.0

    var body: some View {
        Group {
            Group {
                if let e = store.engine, let l = e.state.loans.first(where: { $0.id == loanID }) {
                    let cur = l.companyID == 0 ? e.homeCurrency : (e.state.company(l.companyID).map { e.currency(for: $0) } ?? e.homeCurrency)
                    let p = e.loanPayoff(loanID: l.id)
                    let pay = min(amount, l.balance)
                    let available = l.companyID == 0 ? e.state.cash + e.state.savings : (e.state.company(l.companyID)?.cash ?? 0)
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(l.name).capsLabel()
                            Text(cur.tidyDisplay(l.balance)).font(.hero(34))
                            Text("left to pay · \(cur.tidyShort(l.monthlyPayment)) a month" + (p?.monthsLeft.map { " · \($0) months to go" } ?? "")).popupText(.caption)
                        }
                        HStack {
                            Button("One instalment") { amount = min(l.balance, l.monthlyPayment) }.buttonStyle(SecondaryButtonStyle(size: .compact))
                            Button("Half") { amount = (l.balance / 2).rounded() }.buttonStyle(SecondaryButtonStyle(size: .compact))
                            Button("All") { amount = l.balance }.buttonStyle(SecondaryButtonStyle(size: .compact))
                        }
                        AmountField(title: "Pay back", currency: cur, amount: $amount)
                        KeyFigures(items: [
                            .init(label: "You pay now", value: pay > 0 ? cur.tidyShort(pay) : "–"),
                            .init(label: "Left after", value: cur.tidyShort(max(0, l.balance - pay))),
                            .init(label: "Available", value: cur.tidyShort(available), tint: available < pay ? P.loss : P.ink, sub: l.companyID == 0 ? "cash and savings" : "company cash"),
                        ])
                        Button(pay > 0 ? "Pay back \(cur.tidyShort(pay))" : "Choose an amount") {
                            if store.act({ $0.repayLoan(id: loanID, amount: pay) }) == true {
                                Haptics.success()
                                store.show(pay >= l.balance - 0.5 ? "\(l.name) is paid off." : "\(cur.tidyShort(pay)) paid back.", tone: "good")
                                dismiss()
                            } else { Haptics.warning(); store.show("Not enough money to pay that back.", tone: "warn") }
                        }.buttonStyle(GoldButtonStyle()).disabled(pay <= 0)
                    }
                } else {
                    Text("This loan is paid off.").foregroundStyle(P.inkSoft)
                }
            }
        }
    }
}
