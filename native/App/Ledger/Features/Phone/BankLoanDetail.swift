import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// One loan: what is left, the terms, the schedule from the live balance, this month's instalment paid now (taken once), an early
/// payoff with its quote (balance plus the interest accrued since the last month end), part repayment, and, for a company loan you guaranteed, the
/// bank discussion about releasing the guarantee (it stays after a conversion to a limited company). Every action is the engine's and reports its result.
struct LoanDetailSheet: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var loanID: Int
    @State private var showSchedule: Bool = false
    @State private var pending: PendingAction?
    @State private var partial: Bool = false
    @State private var offer: Double = 0.01
    @State private var talk: String = ""

    var body: some View {
        Group {
            if let e = store.engine, let l = e.state.loans.first(where: { $0.id == loanID }), let rec = record(e, l) {
                content(e, rec)
            } else {
                Text("This loan is paid off.").foregroundStyle(P.inkSoft)
            }
        }
        .confirmAction($pending)
        .centerSheet(isPresented: $partial, title: "Pay back") { partialSheet }
    }

    private func record(_ e: GameEngine, _ l: Loan) -> LoanRecord? {
        let owner: Int? = l.companyID == 0 ? nil : l.companyID
        return e.loanRecords(companyID: owner).first(where: { $0.id == l.id })
    }

    private func currency(_ e: GameEngine, _ rec: LoanRecord) -> Currency {
        if rec.companyID == 0 { return e.homeCurrency }
        return e.state.company(rec.companyID).map { e.currency(for: $0) } ?? e.homeCurrency
    }

    private func accountName(_ e: GameEngine, _ rec: LoanRecord) -> String {
        if rec.companyID == 0 { return "your current account" }
        return (e.state.company(rec.companyID)?.name ?? "the company") + "'s account"
    }

    // MARK: Content

    @ViewBuilder private func content(_ e: GameEngine, _ rec: LoanRecord) -> some View {
        let cur: Currency = currency(e, rec)
        VStack(alignment: .leading, spacing: 14) {
            LoanSummaryPanel(rec: rec, cur: cur)
            termsCard(rec, cur)
            scheduleToggle
            if showSchedule { scheduleCard(e, rec, cur) }
            guarantee(e, rec)
        }
        .popupFooter { actions(e, rec, cur) }
    }

    private func termsCard(_ rec: LoanRecord, _ cur: Currency) -> some View {
        let period: String = "\(rec.termMonths) months (\(rec.monthsLeft) left)"
        let payout: String = rec.payoutAccount == "savings" ? "Savings" : (rec.companyID == 0 ? "Current account" : "Company account")
        return PopupSection(title: rec.number) {
            VStack(spacing: 0) {
                FlatRow(label: "Interest rate", value: Currency.percent(rec.yearlyRate, decimals: 2) + " a year", rule: false)
                FlatRow(label: "Repayment period", value: period)
                FlatRow(label: "Monthly payment", value: cur.tidyDisplay(rec.instalment), sub: rec.thisMonthSettled ? "this month's is paid" : "")
                FlatRow(label: "Next payment", value: rec.nextInstalmentText)
                FlatRow(label: "Lender", value: rec.lender)
                FlatRow(label: "Borrower", value: rec.borrowerName)
                FlatRow(label: "Paid out into", value: payout, sub: rec.arrangementFee > 0.5 ? "arrangement fee " + cur.tidyShort(rec.arrangementFee) : "")
                if rec.personallyGuaranteed { FlatRow(label: "Guarantee", value: "You are personally liable", tint: P.caution) }
                if rec.missedInstalments > 0 { FlatRow(label: "Missed instalments", value: "\(rec.missedInstalments)", tint: P.loss) }
            }
        }
    }

    // MARK: Actions

    /// The money actions stay pinned under the scrolling detail.
    private func actions(_ e: GameEngine, _ rec: LoanRecord, _ cur: Currency) -> some View {
        VStack(spacing: 10) {
            if !rec.thisMonthSettled {
                PopupOptionButton(title: "Pay this month's instalment now", identifier: "loan-pay-instalment") { confirmInstalment(e, rec, cur) }
            }
            HStack(spacing: 10) {
                PopupOptionButton(title: "Pay off early", identifier: "loan-payoff") { confirmPayoff(e, rec, cur) }
                PopupOptionButton(title: "Pay back part", identifier: "loan-pay-part") { partial = true }
            }
        }
    }

    @ViewBuilder private var scheduleToggle: some View {
        if let e = store.engine, let l = e.state.loans.first(where: { $0.id == loanID }), let rec = record(e, l), rec.thisMonthSettled {
            Text("This month's instalment is paid. It is not taken again on the due date.").popupText(.subtitle)
        }
        PopupOptionButton(title: showSchedule ? "Hide schedule" : "View schedule", identifier: "loan-schedule") { Motion.animate(Motion.quickAnimation) { showSchedule.toggle() } }
    }

    private func confirmInstalment(_ e: GameEngine, _ rec: LoanRecord, _ cur: Currency) {
        let id: Int = rec.id
        let from: String = accountName(e, rec)
        let message: String = "\(cur.tidyDisplay(rec.instalment)) is taken from \(from) today. It is not taken again at month end, and the loan keeps its schedule."
        pending = PendingAction(title: "Pay this month's instalment now?", message: message, button: "Pay \(cur.tidyShort(rec.instalment))", amount: rec.instalment, currency: cur) {
            BankPay.instalment(store, loanID: id)
        }
    }

    private func confirmPayoff(_ e: GameEngine, _ rec: LoanRecord, _ cur: Currency) {
        guard let q = e.loanPayoffQuote(loanID: rec.id) else { store.show("That loan is already paid off.", tone: "n"); return }
        let id: Int = rec.id
        let name: String = rec.name
        let funds: Double = rec.companyID == 0 ? e.state.cash + e.state.savings : (e.state.company(rec.companyID)?.cash ?? 0)
        var message: String = "Balance \(cur.tidyDisplay(q.balance)) plus \(cur.tidyDisplay(q.accruedInterest)) interest accrued since the last month end: \(cur.tidyDisplay(q.total)) from \(accountName(e, rec)). "
        message += "There is no early repayment fee, the interest still to come is saved and the loan ends today. "
        message += funds >= q.total ? "About \(cur.tidyShort(funds - q.total)) is left afterwards." : "It holds \(cur.tidyShort(funds)), which is not enough."
        pending = PendingAction(title: "Pay off \(name) in full?", message: message, button: "Pay off \(cur.tidyShort(q.total))", amount: q.total, currency: cur) {
            let ok: Bool = store.act({ (g: inout GameEngine) -> Bool in g.payOffLoan(loanID: id) }) ?? false
            if ok {
                Haptics.success()
                store.show("\(name) is paid off.", tone: "good")
                dismiss()
            } else {
                Haptics.warning()
                store.show("Not enough money to pay \(name) off now.", tone: "warn")
            }
        }
    }

    @ViewBuilder private var partialSheet: some View {
        if let e = store.engine, let l = e.state.loans.first(where: { $0.id == loanID }) {
            if l.companyID == 0 {
                RepayPersonalLoanSheet(loanID: loanID)
            } else if let co = e.state.company(l.companyID) {
                RepayLoanSheet(engine: e, company: co, loan: l).environmentObject(store)
            }
        }
    }

    // MARK: Schedule

    private func scheduleCard(_ e: GameEngine, _ rec: LoanRecord, _ cur: Currency) -> some View {
        let rows: [LoanScheduleRow] = e.loanSchedule(loanID: rec.id)
        let columns: [TableColumn] = [TableColumn(title: "Date"), TableColumn(title: "Pay", width: 78), TableColumn(title: "Left", width: 78)]
        return VStack(alignment: .leading, spacing: 6) {
            Text("REPAYMENT SCHEDULE").capsLabel()
            if rows.isEmpty {
                Text("Nothing is left to schedule.").popupText(.subtitle)
            } else {
                SharpTable {
                    TableHeader(columns: columns)
                    ForEach(rows) { (r: LoanScheduleRow) in
                        TableRow(columns: columns, title: r.dateText, note: "Payment \(r.number)", values: [cur.tidyShort(r.payment), cur.tidyShort(r.balance)])
                    }
                }
                Text("At today's rate. The bank re-works the instalment each month at that month's rate.").popupText(.caption)
            }
        }
    }

    // MARK: Guarantee renegotiation

    @ViewBuilder private func guarantee(_ e: GameEngine, _ rec: LoanRecord) -> some View {
        if rec.personallyGuaranteed, let t = e.guaranteeTerms(loanID: rec.id) {
            PopupSection(title: "Personal guarantee") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(t.guaranteed ? "You guarantee it." : "Released.").popupText(.caption)
                    Text("You guaranteed this loan personally. The guarantee stays with you, also after a company becomes a limited company, until the bank agrees to release it for a higher margin.")
                        .popupText(.subtitle)
                    if let why = t.unavailable {
                        Text(why.tidyText).popupText(.risk)
                            .accessibilityIdentifier("loan-guarantee-unavailable")
                    } else {
                        negotiation(t)
                    }
                    if !talk.isEmpty {
                        Text(talk).popupText(.body)
                            .accessibilityIdentifier("loan-guarantee-answer")
                    }
                }
            }
        }
    }

    @ViewBuilder private func negotiation(_ t: LoanGuarantee.Terms) -> some View {
        let pct: String = Currency.percent(offer, decimals: 2)
        Stepper(value: $offer, in: 0.001...0.05, step: 0.001) {
            Text("Extra margin you offer: \(pct) a year").popupText(.body)
        }
        .onAppear {
            if let c = t.counter { offer = c } else if t.lastOffer > 0 { offer = t.lastOffer }
        }
        if let c = t.counter {
            Text("The bank's standing counter: " + Currency.percent(c, decimals: 2) + " a year extra.").popupText(.caption)
        }
        PopupOptionButton(title: "Ask the bank to release it", identifier: "loan-guarantee-offer") { confirmOffer(t) }
    }

    private func confirmOffer(_ t: LoanGuarantee.Terms) {
        let id: Int = t.loanID
        let margin: Double = offer
        let pct: String = Currency.percent(margin, decimals: 2)
        let message: String = "You offer \(pct) a year on top of the loan's margin for the rest of its term. If the bank agrees, the guarantee ends and the instalments rise. If you push too hard it may walk away and will not talk again for about six months."
        pending = PendingAction(title: "Ask the bank to release the guarantee?", message: message, button: "Make the offer") {
            let answer: LoanGuarantee.Answer? = store.act({ (g: inout GameEngine) -> LoanGuarantee.Answer in g.offerGuaranteeRelease(loanID: id, extraMargin: margin) })
            switch answer {
            case .released(let m)?:
                Haptics.success()
                talk = "The bank agreed: the guarantee is released for \(Currency.percent(m, decimals: 2)) a year extra."
                store.show("The personal guarantee is released.", tone: "good")
            case .counter(let m, let isFinal)?:
                Haptics.tap()
                offer = m
                talk = "The bank would do it for \(Currency.percent(m, decimals: 2)) a year extra" + (isFinal ? " and will not go lower." : ".")
            case .refused?:
                Haptics.warning()
                talk = "The bank refused that offer."
            case .walkedAway?:
                Haptics.warning()
                talk = "The bank ended the talk. It will not discuss this again for now."
            case .notPossible(let why)?:
                Haptics.warning()
                talk = why
            case nil:
                break
            }
        }
    }
}

/// The ivory block at the top of the loan: what is left to pay, how much is repaid, in the colours of the Banking mockup.
private struct LoanSummaryPanel: View {
    @Environment(\.outsidePalette) private var P
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var rec: LoanRecord
    var cur: Currency

    var body: some View {
        let repaid: Double = rec.principal > 0 ? max(0, min(1, 1 - rec.balance / rec.principal)) : 0
        VStack(alignment: .leading, spacing: 8) {
            Text(rec.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(P.inkSoft)
            Text(cur.tidyDisplay(rec.balance)).font(.hero(34)).foregroundStyle(P.ink).minimumScaleFactor(0.6).lineLimit(1).moneyFlash(rec.balance)
            Text("left to pay of " + cur.tidyDisplay(rec.principal)).font(.system(size: 12.5)).foregroundStyle(P.inkFaint)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(P.lineStrong.opacity(0.35))
                    Capsule().fill(P.accent).frame(width: geo.size.width * repaid)
                        .animation(Motion.fill(reduceMotion), value: repaid)
                }
            }
            .frame(height: 6)
            Text("\(Int((repaid * 100).rounded()))% repaid").font(.system(size: 12)).foregroundStyle(P.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }
}
