import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The company's loans: what it owes and on what terms, early repayment, and a new loan with a chosen term.
/// Original: money.js `loansheet/loanterm/loango/repaysheet/repaygo`. Uses the engine's `takeLoan` and `repayLoan`.
struct CompanyLoans: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var loanAmount = 0.0
    @State private var term = 60
    @State private var repaying: Loan?
    @State private var pending: PendingAction?
    static let terms = [12, 24, 36, 60, 120]

    var body: some View {
        let cur = engine.currency(for: company)
        let loans = engine.state.loans.filter { $0.companyID == company.id }
        let shift = Banking.countryRateShift(companyID: company.id, state: engine.state, context: engine.context)
        let missedTotal = loans.reduce(0) { $0 + $1.int("miss") }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if missedTotal > 0 || company.int("loanCall") != 0 {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.loss).padding(.top, 2)
                    Text(company.int("loanCall") != 0 ? "The bank has called a loan. Pay the next instalment in time or the company is wound up."
                         : "\(missedTotal) missed \(missedTotal == 1 ? "instalment" : "instalments"). Penalties are added each month until the loan is back on track.")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                }
            }
            LedgerSection(title: "What the company owes", trailing: {
                Text(loans.isEmpty ? "no loans" : cur.tidyShort(loans.reduce(0) { $0 + $1.balance }) + " · " + cur.tidyShort(loans.reduce(0) { $0 + $1.monthlyPayment }) + " a month")
                    .font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
            }) {
                if loans.isEmpty { Text("This company has no loans. Borrowing is below.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
                VStack(spacing: 0) {
                    ForEach(Array(loans.enumerated()), id: \.element.id) { n, l in
                        if n > 0 { Hairline() }
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text("Interest \(Currency.percent(Banking.rate(of: l, state: engine.state, modifiers: engine.context.lending, countryShift: shift), decimals: 2)) · \(cur.tidyDisplay(l.monthlyPayment)) a month" + (l.termMonths > 0 ? " · \(l.termMonths / 12 >= 1 && l.termMonths % 12 == 0 ? "\(l.termMonths / 12)-year" : "\(l.termMonths)-month") term" : "") + (l.isGuaranteed ? " · you guarantee it" : ""))
                                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                                if l.int("miss") > 0 { Text("\(l.int("miss")) instalment\(l.int("miss") == 1 ? "" : "s") missed").font(.system(size: 11)).foregroundStyle(Theme.loss) }
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(cur.tidyShort(l.balance)).font(.system(size: 15, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                                Button("Repay…") { repaying = l }.buttonStyle(QuietButtonStyle())
                            }
                        }.padding(.vertical, 9)
                    }
                }
            }
            borrow(cur, shift)
        }
        .confirmAction($pending)
        .sheet(item: $repaying) { l in
            RepayLoanSheet(engine: engine, company: company, loan: l).environmentObject(store)
        }
    }

    @ViewBuilder private func borrow(_ cur: Currency, _ shift: Double) -> some View {
        let offer = engine.loanOffer(kind: "biz", amount: loanAmount, companyID: company.id)
        let rate = engine.state.economy.policyRate + shift + offer.margin
        LedgerSection(title: "Borrow for this company", trailing: {
            Text("credit " + offer.creditBand.lowercased()).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if company.flag("loanFrozen") {
                    Text("Credit restricted: the bank lends nothing new until the missed instalments are paid.").font(.caption).foregroundStyle(Theme.caution)
                }
                Text("The bank would lend up to \(cur.tidyDisplay(offer.maximum)) at about \(Currency.percent(rate, decimals: 1)) a year.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                AmountField(title: "Loan amount", currency: cur, amount: $loanAmount)
                Text("Term").font(.caption).foregroundStyle(Theme.ivoryMuted)
                SectionTabs(items: Self.terms, title: { $0 < 12 || $0 % 12 != 0 ? "\($0) mo" : "\($0 / 12) yr" }, selection: $term).padding(.horizontal, -Theme.Space.margin)
                if loanAmount > 0 {
                    let pay = engine.companyLoanPayment(amount: loanAmount, termMonths: term, companyID: company.id)
                    KeyFigures(items: [
                        .init(label: "A month", value: cur.tidyShort(pay)),
                        .init(label: "Paid in total", value: cur.tidyShort(pay * Double(term))),
                        .init(label: "Interest", value: cur.tidyShort(max(0, pay * Double(term) - loanAmount)), tint: Theme.caution),
                    ])
                    if loanAmount > offer.maximum { Text("More than the bank will lend.").font(.caption).foregroundStyle(Theme.loss) }
                }
                Text(company.form == .soleTrader ? "As a sole trader you are personally liable: if the company cannot pay, the bank comes to you." : "A limited company borrows on its own account; the instalments come out of company cash at month end.")
                    .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                Button("Take the loan…") { confirmBorrow(cur) }.buttonStyle(GoldButtonStyle()).disabled(company.flag("loanFrozen") || (loanAmount > 0 && loanAmount > offer.maximum))
            }
        }
    }

    private func confirmBorrow(_ cur: Currency) {
        guard loanAmount > 0 else { Haptics.warning(); store.show("Enter an amount first.", tone: "warn"); return }
        let amount = loanAmount, months = term
        let pay = engine.companyLoanPayment(amount: amount, termMonths: months, companyID: company.id)
        pending = PendingAction(title: "Borrow \(cur.tidyDisplay(amount))?", message: "\(cur.tidyDisplay(pay)) a month for \(months) months, \(cur.tidyDisplay(pay * Double(months))) in total. Missed instalments add penalties and can get the loan called.", button: "Take the loan") {
            switch store.act({ $0.takeLoan(kind: "biz", amount: amount, termMonths: months, companyID: company.id) }) {
            case .ok?: Haptics.success(); loanAmount = 0; store.show("Loan granted: \(cur.tidyDisplay(amount)) paid into \(company.name).", tone: "good")
            case .tooSmall?: Haptics.warning(); store.show("The bank won't lend that little.", tone: "warn")
            case nil: break
            default: Haptics.warning(); store.show("The bank declined \(cur.tidyDisplay(amount)). Try a smaller amount or a longer term.", tone: "bad")
            }
        }
    }
}

/// Pay a loan off early, in part or in full, from company cash.
struct RepayLoanSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var engine: GameEngine
    var company: Company
    var loan: Loan
    @State private var amount = 0.0
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        let cash = store.engine?.state.company(company.id)?.cash ?? company.cash
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    KeyFigures(items: [
                        .init(label: "Left to pay", value: cur.tidyShort(loan.balance)),
                        .init(label: "A month now", value: cur.tidyShort(loan.monthlyPayment)),
                        .init(label: "Company cash", value: cur.tidyShort(cash), tint: cash < loan.balance ? Theme.caution : Theme.ivory),
                    ])
                    AmountField(title: "Repay", currency: cur, amount: $amount)
                    if cash < loan.balance { Text("The company holds less than the whole balance: put money in first to repay it all.").font(.caption).foregroundStyle(Theme.caution) }
                    HStack {
                        Button("Repay this amount…") { confirmRepay(min(amount, loan.balance), cur, cash) }.buttonStyle(QuietButtonStyle()).disabled(amount <= 0)
                        Button("Repay all…") { confirmRepay(loan.balance, cur, cash) }.buttonStyle(QuietButtonStyle())
                    }
                    Text("Paid from the company's cash, with no fee for paying early. Less owed means less interest; the monthly instalment falls with the balance.")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Space.margin)
            }
            .ledgerBackground()
            .navigationTitle(loan.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
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
