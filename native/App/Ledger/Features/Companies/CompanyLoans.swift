import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

struct CompanyLoans: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var repaying: Loan?

    var body: some View {
        let cur = engine.currency(for: company)
        let loans = engine.state.loans.filter { $0.companyID == company.id }
        let shift = Banking.countryRateShift(companyID: company.id, state: engine.state, context: engine.context)
        let missedTotal = loans.reduce(0) { $0 + $1.int("miss") }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if missedTotal > 0 || company.int("loanCall") != 0 {
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    LedgerGlyph(glyph: Glyph.warning, size: Theme.Icon.medium, tint: P.loss).padding(.top, Theme.Space.xxs)
                    Text(company.int("loanCall") != 0 ? "The bank has called a loan. Pay the next instalment in time or the company is wound up."
                         : "\(missedTotal) missed \(missedTotal == 1 ? "instalment" : "instalments"). Penalties are added each month until the loan is back on track.")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(P.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            CardSection(title: "What the company owes", trailing: {
                Text(loans.isEmpty ? "no loans" : cur.tidyShort(loans.reduce(0) { $0 + $1.balance }) + " · " + cur.tidyShort(loans.reduce(0) { $0 + $1.monthlyPayment }) + " a month")
                    .font(.system(size: 11.5).monospacedDigit()).foregroundStyle(P.inkFaint)
            }) {
                if loans.isEmpty { Text("No loans. Apply for one above.").textStyle(.body, tint: P.inkSoft) }
                VStack(spacing: 0) {
                    ForEach(Array(loans.enumerated()), id: \.element.id) { n, l in
                        if n > 0 { Hairline() }
                        HStack(alignment: .center, spacing: Theme.Space.m) {
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(l.name).textStyle(.body, tint: P.ink)
                                Text("Interest \(Currency.percent(Banking.rate(of: l, state: engine.state, modifiers: engine.context.lending, countryShift: shift), decimals: 2)) · \(cur.tidyDisplay(l.monthlyPayment)) a month" + (l.termMonths > 0 ? " · \(l.termMonths / 12 >= 1 && l.termMonths % 12 == 0 ? "\(l.termMonths / 12)-year" : "\(l.termMonths)-month") term" : "") + (l.isGuaranteed ? " · you guarantee it" : ""))
                                    .font(.system(size: 11)).foregroundStyle(P.inkFaint).fixedSize(horizontal: false, vertical: true)
                                if l.int("miss") > 0 { Text("\(l.int("miss")) instalment\(l.int("miss") == 1 ? "" : "s") missed").textStyle(.caption, tint: P.loss) }
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                                Text(cur.tidyShort(l.balance)).textStyle(.headline, tint: P.ink, numeric: true)
                                Button("Details…") { repaying = l }.buttonStyle(QuietButtonStyle())
                                    .accessibilityIdentifier("company-loan-details")
                            }
                        }.padding(.vertical, Theme.Space.s)
                    }
                }
            }
        }
        .centerSheet(item: $repaying, title: "Loan details") { l in
            LoanDetailSheet(loanID: l.id).environmentObject(store)
        }
    }
}

struct RepayLoanSheet: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var engine: GameEngine
    var company: Company
    var loan: Loan
    @State private var amount = 0.0
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        let cash = store.engine?.state.company(company.id)?.cash ?? company.cash
        Group {
            Group {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    KeyFigures(items: [
                        .init(label: "Left to pay", value: cur.tidyShort(loan.balance)),
                        .init(label: "A month now", value: cur.tidyShort(loan.monthlyPayment)),
                        .init(label: "Company cash", value: cur.tidyShort(cash), tint: cash < loan.balance ? P.caution : P.ink),
                    ])
                    AmountField(title: "Repay", currency: cur, amount: $amount)
                    if cash < loan.balance { Text("The company holds less than the whole balance: put money in first to repay it all.").popupText(.risk) }
                    HStack {
                        Button("Repay this amount…") { confirmRepay(min(amount, loan.balance), cur, cash) }.buttonStyle(QuietButtonStyle()).disabled(amount <= 0)
                        Button("Repay all…") { confirmRepay(loan.balance, cur, cash) }.buttonStyle(QuietButtonStyle())
                    }
                    Text("Paid from the company's cash, with no fee for paying early. Less owed means less interest; the monthly instalment falls with the balance.")
                        .popupText(.caption)
                }
            }
        }
        .confirmAction($pending)
    }

    private func confirmRepay(_ v: Double, _ cur: Currency, _ cash: Double) {
        guard v > 0 else { return }
        pending = PendingAction(title: "Repay \(cur.tidyDisplay(v))?", message: "Leaves \(cur.tidyDisplay(cash - v)) in company cash. No fee for paying early; the balance falls to \(cur.tidyDisplay(max(0, loan.balance - v))).",
                                button: "Repay", destructive: v >= cash * 0.9, amount: v, currency: cur) { repay(v, cur) }
    }

    private func repay(_ v: Double, _ cur: Currency) {
        guard v > 0 else { return }
        if store.act({ $0.repayLoan(id: loan.id, amount: v) }) == true {
            Haptics.success(); store.show(v >= loan.balance - 1 ? "\(loan.name) paid off." : "Repaid \(cur.tidyDisplay(v)).", tone: "good"); dismiss()
        } else {
            Haptics.warning(); store.show("\(company.name) does not have \(cur.tidyDisplay(v)) in cash. Put money in first.", tone: "warn")
        }
    }
}
