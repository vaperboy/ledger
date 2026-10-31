import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Investments

// Loans, Stage 2 (financial.md L1-L5): the two-stage flow (assessment, then the final agreement), early repayment that charges nothing twice,
// a schedule from the live loan, and loan records that Accounting can use as a source.
// Lending maths is unchanged (`Banking.offer`, `Banking.take`); this file is the flow and the read models around them.

/// Where the money of a loan lands.
public enum LoanPayout: String, CaseIterable, Sendable {
    /// The borrower's current account (a company's account for a company loan).
    case current
    /// A personal loan can be paid straight into savings.
    case savings
}

public struct LoanPayoutAccount: Equatable, Sendable, Identifiable {
    public var id: LoanPayout
    public var name: String
    public var balance: Double
}

public struct LoanExample: Equatable, Sendable, Identifiable {
    public var id: Int { termMonths }
    public var termMonths: Int
    public var monthlyPayment: Double
    public var totalInterest: Double
}

/// Stage 1 of a loan: what the bank would lend this borrower and on what terms. The player then chooses an amount up to `maximum`.
public struct LoanAssessment: Equatable, Sendable {
    public var kind: String
    public var companyID: Int?
    public var borrowerName: String
    public var approved: Bool
    /// Why the bank would not lend (nil when it would).
    public var refusal: String?
    public var minimum: Double
    public var maximum: Double
    public var creditBand: String
    public var yearlyRate: Double
    public var feeRate: Double
    public var termOptions: [Int]
    public var defaultTermMonths: Int
    /// The instalment and interest if the maximum were taken, for each term.
    public var examplesAtMaximum: [LoanExample]
    public var conditions: [String]
    public var payoutAccounts: [LoanPayoutAccount]
    public var personalGuarantee: Bool
    /// What the final agreement will ask for.
    public var requiredPapers: [String]
}

/// A loan as a record: the source Accounting uses for loan transactions and financing documents.
public struct LoanRecord: Equatable, Sendable, Identifiable {
    public var id: Int
    public var number: String
    public var name: String
    public var kind: String
    public var lender: String
    public var borrowerName: String
    public var companyID: Int
    public var principal: Double
    public var balance: Double
    public var yearlyRate: Double
    public var termMonths: Int
    public var monthsLeft: Int
    public var startWeek: Int
    public var startDateText: String
    public var instalment: Double
    public var nextInstalmentText: String
    /// This month's instalment is settled (collected or paid early).
    public var thisMonthSettled: Bool
    public var arrangementFee: Double
    public var personallyGuaranteed: Bool
    public var missedInstalments: Int
    public var payoutAccount: String
}

public extension GameEngine {
    // MARK: Stage 1: assessment

    func loanAssessment(kind: String, companyID: Int?) -> LoanAssessment {
        let cur = companyID.flatMap { state.company($0) }.map { currency(for: $0) } ?? context.currency(state.homeCountryCode, state)
        let borrower = companyID.flatMap { state.company($0)?.name } ?? state.player.name
        let offer = loanOffer(kind: kind, amount: 0, companyID: companyID)
        let minimum = cur.scaledPrice(5000)
        let terms = Self.loanTermChoices
        let defaultTerm = terms.contains(36) ? 36 : (terms.first ?? 12)
        let supported = kind == "cons" || kind == "biz"
        var refusal: String?
        if !supported { refusal = "The bank does not offer that loan here." }
        else if kind == "biz", companyID.flatMap({ state.company($0) }) == nil { refusal = "That company is no longer trading." }
        else if offer.maximum <= 0 { refusal = "The bank would not lend to you at the moment." }
        else if offer.maximum < minimum { refusal = "The bank would lend less than its smallest loan (\(cur.display(minimum)))." }
        let approved = refusal == nil
        let atMax = approved ? offer.maximum : 0
        let probe = loanApplicationQuote(kind: kind, amount: max(minimum, atMax), termMonths: defaultTerm, companyID: companyID)
        let examples: [LoanExample] = approved ? terms.map { t in
            let q = loanQuote(kind: kind, amount: atMax, termMonths: t, companyID: companyID)
            return LoanExample(termMonths: t, monthlyPayment: q.monthlyPayment, totalInterest: q.totalInterest)
        } : []
        let guarantee = kind == "biz" ? (companyID.flatMap { state.company($0) }?.form != .limited) : false
        var conditions = [
            "The loan owed is the full amount you choose; the arrangement fee of \(String(format: "%.2f%%", probe.feeRate * 100)) is taken when the money is paid out.",
            "Interest follows the central bank rate plus the bank's margin for credit band \(offer.creditBand). The instalment is re-worked every month at that month's rate.",
            "Instalments are taken on the last day of each month. A payment the account cannot cover adds the unpaid interest and a penalty and lowers the credit score.",
        ]
        if kind == "biz" { conditions.append(guarantee ? "You are personally liable for this loan." : "Loans signed earlier keep your personal guarantee; this new one is the company's.") }
        var accounts: [LoanPayoutAccount] = []
        if let c = companyID.flatMap({ state.company($0) }) {
            accounts.append(LoanPayoutAccount(id: .current, name: c.name + " account", balance: c.cash))
        } else {
            accounts.append(LoanPayoutAccount(id: .current, name: "Your personal account", balance: state.cash))
            accounts.append(LoanPayoutAccount(id: .savings, name: "Your savings", balance: state.savings))
        }
        return LoanAssessment(kind: kind, companyID: companyID, borrowerName: borrower, approved: approved, refusal: refusal, minimum: minimum, maximum: atMax,
                              creditBand: offer.creditBand, yearlyRate: probe.yearlyRate, feeRate: probe.feeRate, termOptions: terms, defaultTermMonths: defaultTerm,
                              examplesAtMaximum: examples, conditions: conditions, payoutAccounts: accounts, personalGuarantee: guarantee,
                              requiredPapers: kind == "cons" ? ["Full name", "Proof of income"] : ["Full name", "Company papers (registration or accounts)"])
    }

    // MARK: Early repayment

    /// Pay this month's instalment now. It is taken once: the month-end collection skips a loan whose month is settled.
    @discardableResult
    mutating func payLoanInstalmentNow(loanID: Int) -> Banking.EarlyInstalment {
        var r = Banking.EarlyInstalment.noLoan
        update { s, _, ctx in r = Banking.payInstalmentNow(loanID: loanID, state: &s, context: ctx) }
        return r
    }

    /// What closing the loan today costs: the balance plus the interest accrued since the last month end.
    func loanPayoffQuote(loanID: Int) -> Banking.Payoff? { Banking.payoff(loanID: loanID, state: state, context: context) }

    /// Repay everything owed on the loan today (balance and accrued interest).
    @discardableResult
    mutating func payOffLoan(loanID: Int) -> Bool {
        guard let q = loanPayoffQuote(loanID: loanID) else { return false }
        return repayLoan(id: loanID, amount: q.balance)
    }

    /// The remaining schedule of a running loan from its live balance, today's rate and the months left. The first row is the next instalment
    /// that is still to be collected (the next month end, or the one after when this month is already settled).
    func loanSchedule(loanID: Int) -> [LoanScheduleRow] {
        guard let l = state.loans.first(where: { $0.id == loanID }), l.balance > 0 else { return [] }
        let inst = Banking.instalment(of: l, state: state, context: context)
        var week = state.week
        if Banking.instalmentSettled(l, state: state) || GameCalendar.monthIndex(week: week) < 0 { week += 5 }
        var cursor = Self.monthEndDate(fromWeek: week)
        var balance = l.balance
        var rows: [LoanScheduleRow] = []
        let n = max(1, inst.monthsLeft)
        for k in 1...n {
            if k > 1 { cursor = Self.monthEndDate(fromWeek: cursor.week + 1) }
            let interest = balance * inst.yearlyRate / 12
            let principal = k == n ? balance : min(balance, max(0, inst.payment - interest))
            balance -= principal
            rows.append(LoanScheduleRow(number: k, dateText: GameCalendar.dateString(week: cursor.week, dayOffset: cursor.day), payment: interest + principal,
                                        interest: interest, principal: principal, balance: max(0, balance)))
            if balance < 1 { break }
        }
        return rows
    }

    // MARK: Loan records

    func loanRecords(companyID: Int?) -> [LoanRecord] {
        state.loans.filter { $0.kind != "start" || companyID == nil }.filter { companyID == nil || $0.companyID == companyID }.compactMap { l in
            guard l.balance > 0 else { return nil }
            let inst = Banking.instalment(of: l, state: state, context: context)
            let settled = Banking.instalmentSettled(l, state: state)
            var w = state.week
            if settled { w += 5 }
            let next = Self.monthEndDate(fromWeek: w)
            let app = l.value("app")
            let lender = l.bankCompanyID != 0 ? (state.company(l.bankCompanyID)?.name ?? "Bank") : "Bank"
            return LoanRecord(id: l.id, number: "LN-\(String(format: "%05d", l.id))", name: l.name, kind: l.kind, lender: lender,
                              borrowerName: l.companyID == 0 ? state.player.name : (state.company(l.companyID)?.name ?? "Company"), companyID: l.companyID,
                              principal: l.originalAmount, balance: l.balance, yearlyRate: inst.yearlyRate, termMonths: l.termMonths, monthsLeft: inst.monthsLeft,
                              startWeek: l.startWeek, startDateText: GameCalendar.dateString(week: l.startWeek), instalment: inst.total,
                              nextInstalmentText: GameCalendar.dateString(week: next.week, dayOffset: next.day), thisMonthSettled: settled,
                              arrangementFee: app["fee"].double, personallyGuaranteed: l.isGuaranteed, missedInstalments: l.int("miss"),
                              payoutAccount: app["into"].isNull ? (l.companyID == 0 ? "current" : "company") : app["into"].string)
        }
    }
}
