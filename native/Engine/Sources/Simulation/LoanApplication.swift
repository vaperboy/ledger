import Foundation
import GameCore
import Countries
import Finance
import Businesses

// The Bank app's loan flow (Oct 2026): a quote with fee, disbursal and schedule, and an application with a documents form the bank checks.
// The loan itself is the existing `Banking.take`; this file adds the arrangement fee, the paperwork check and the figures a screen shows.

/// What the applicant hands in. The bank checks it against the game's own records.
public struct LoanDocuments: Equatable, Sendable {
    public enum IncomeProof: String, CaseIterable, Sendable { case none, payslips, taxReturn, bankStatements }
    public enum CompanyPapers: String, CaseIterable, Sendable { case none, registration, accounts }
    public var fullName: String
    public var incomeProof: IncomeProof
    public var companyPapers: CompanyPapers
    public init(fullName: String, incomeProof: IncomeProof = .none, companyPapers: CompanyPapers = .none) {
        self.fullName = fullName; self.incomeProof = incomeProof; self.companyPapers = companyPapers
    }
}

/// One instalment of the schedule at the quoted rate. (The bank re-works the payment every month at that month's rate; this is the schedule at today's.)
public struct LoanScheduleRow: Identifiable, Equatable, Sendable {
    public var id: Int { number }
    public var number: Int
    public var dateText: String
    public var payment: Double
    public var interest: Double
    public var principal: Double
    public var balance: Double
}

public struct LoanClause: Identifiable, Equatable, Sendable {
    public var id: String { title }
    public var title: String
    public var body: String
}

/// Everything the three-step apply flow shows. `refusal` is set when the bank would turn the amount down whatever the paperwork says.
public struct LoanApplicationQuote: Equatable, Sendable {
    public var kind: String
    public var amount: Double
    public var termMonths: Int
    public var minimum: Double
    public var maximum: Double
    public var minTermMonths: Int
    public var maxTermMonths: Int
    public var creditBand: String
    public var yearlyRate: Double
    public var feeRate: Double
    public var fee: Double
    /// What lands in the account: amount minus the fee. The loan owed is the full amount.
    public var disbursal: Double
    public var monthlyPayment: Double
    public var totalRepaid: Double
    public var totalInterest: Double
    public var firstPaymentText: String
    /// Instalments fall on the last day of each month.
    public var paymentDayText: String
    public var schedule: [LoanScheduleRow]
    public var refusal: String?
    public var needsIncomeProof: Bool
    public var needsCompanyPapers: Bool
}

public enum LoanApplicationOutcome: Equatable, Sendable {
    case approved(loanID: Int, fee: Double, disbursed: Double)
    case refused(String)
}

public extension Banking {
    /// The arrangement fee: a quarter of the bank's credit margin for the borrower's band (0.45% for A up to 3% for E), nothing when your own bank lends.
    static func arrangementFeeRate(credit: Double, ownBank: Bool) -> Double { ownBank ? 0 : creditMargin(credit) * 0.25 }
}

public extension GameEngine {
    /// The terms a slider may cover: the shortest and longest the screens have always offered.
    static var loanTermRange: ClosedRange<Int> { (loanTermChoices.min() ?? 12)...(loanTermChoices.max() ?? 120) }

    private func accountCurrency(_ companyID: Int?) -> Currency {
        companyID.flatMap { state.company($0) }.map { currency(for: $0) } ?? context.currency(state.homeCountryCode, state)
    }

    /// The last day of the month in which game week `week` (or the next month-end week after it) falls.
    private func monthEndDate(fromWeek week: Int) -> (week: Int, day: Int) {
        var w = week
        while !GameCalendar.isMonthEnd(week: w) { w += 1 }
        let m = GameCalendar.date(week: w).month
        var d = 0
        while d < 6, GameCalendar.date(week: w, dayOffset: d + 1).month == m { d += 1 }
        return (w, d)
    }

    func loanApplicationQuote(kind: String, amount: Double, termMonths: Int, companyID: Int?) -> LoanApplicationQuote {
        let range = Self.loanTermRange
        let term = min(max(termMonths, range.lowerBound), range.upperBound)
        let q = loanQuote(kind: kind, amount: amount, termMonths: term, companyID: companyID)
        let cur = accountCurrency(companyID)
        let feeRate = Banking.arrangementFeeRate(credit: state.credit, ownBank: q.fromOwnBank)
        let fee = (max(0, amount) * feeRate).rounded()
        let minimum = cur.scaledPrice(5000)
        var rows: [LoanScheduleRow] = []
        var balance = max(0, amount)
        var cursor = monthEndDate(fromWeek: state.week)
        var firstText = ""
        for n in 1...term {
            if n > 1 { cursor = monthEndDate(fromWeek: cursor.week + 1) }
            let text = GameCalendar.dateString(week: cursor.week, dayOffset: cursor.day)
            if n == 1 { firstText = text }
            let interest = balance * q.yearlyRate / 12
            let principal = n == term ? balance : min(balance, max(0, q.monthlyPayment - interest))
            balance -= principal
            rows.append(LoanScheduleRow(number: n, dateText: text, payment: interest + principal, interest: interest, principal: principal, balance: max(0, balance)))
        }
        var refusal: String?
        if amount < minimum { refusal = "The bank does not lend less than \(cur.display(minimum))." }
        else if q.maximum <= 0 { refusal = "The bank would not lend to you at the moment." }
        else if amount > q.maximum { refusal = "The bank would lend at most \(cur.display(q.maximum)) on today's figures." }
        return LoanApplicationQuote(kind: kind, amount: amount, termMonths: term, minimum: minimum, maximum: q.maximum, minTermMonths: range.lowerBound,
                                    maxTermMonths: range.upperBound, creditBand: q.creditBand, yearlyRate: q.yearlyRate, feeRate: feeRate, fee: fee,
                                    disbursal: max(0, amount - fee), monthlyPayment: q.monthlyPayment, totalRepaid: q.totalRepaid,
                                    totalInterest: q.totalInterest, firstPaymentText: firstText, paymentDayText: "Last day of each month",
                                    schedule: rows, refusal: refusal, needsIncomeProof: kind == "cons", needsCompanyPapers: kind == "biz")
    }

    /// The agreement the applicant reads, with the quote's own figures in it.
    func loanAgreement(kind: String, amount: Double, termMonths: Int, companyID: Int?) -> [LoanClause] {
        let q = loanApplicationQuote(kind: kind, amount: amount, termMonths: termMonths, companyID: companyID)
        let cur = accountCurrency(companyID)
        let borrower = companyID.flatMap { state.company($0)?.name } ?? state.player.name
        let pct = { (r: Double) in String(format: "%.2f%%", r * 100) }
        return [
            LoanClause(title: "1. The loan", body: "The bank lends \(borrower) \(cur.display(q.amount)) for \(q.termMonths) months. The loan owed is the full \(cur.display(q.amount))."),
            LoanClause(title: "2. Fee and disbursal", body: "An arrangement fee of \(cur.display(q.fee)) (\(pct(q.feeRate))) is taken when the money is paid out, so \(cur.display(q.disbursal)) reaches the account."),
            LoanClause(title: "3. Interest", body: "Interest is the central bank rate plus the bank's margin for credit band \(q.creditBand): \(pct(q.yearlyRate)) a year today. The rate follows the central bank and the bank re-works the instalment each month so the loan ends on time."),
            LoanClause(title: "4. Repayment", body: "\(cur.display(q.monthlyPayment)) a month at today's rate, \(cur.display(q.totalRepaid)) in all, of which \(cur.display(q.totalInterest)) interest. Payments are taken on the \(q.paymentDayText.lowercased()), the first on \(q.firstPaymentText)."),
            LoanClause(title: "5. Missed payments", body: "A payment the account cannot cover adds the unpaid interest and a penalty to the loan and lowers the credit score. A second miss restricts further credit; a third lets the bank call the loan."),
        ]
    }

    /// Apply: the bank checks the documents, then the amount, and pays the loan out less the fee. Nothing moves when it refuses.
    @discardableResult
    mutating func applyForLoan(kind: String, amount: Double, termMonths: Int, companyID: Int?, documents: LoanDocuments, agreed: Bool) -> LoanApplicationOutcome {
        guard kind == "cons" || kind == "biz" else { return .refused("The bank does not offer that loan here.") }
        guard agreed else { return .refused("The agreement has to be accepted first.") }
        let squash = { (t: String) in t.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        guard !documents.fullName.trimmingCharacters(in: .whitespaces).isEmpty else { return .refused("The application needs your full name.") }
        guard squash(documents.fullName) == squash(state.player.name) else { return .refused("The name on the application does not match the name the bank holds for you.") }
        if kind == "cons", documents.incomeProof == .none { return .refused("The bank needs proof of income for a personal loan.") }
        if kind == "biz" {
            guard let co = companyID.flatMap({ state.company($0) }) else { return .refused("That company is no longer trading.") }
            if documents.companyPapers == .none { return .refused("The bank needs the company's papers for a business loan.") }
            if documents.companyPapers == .registration, co.monthlyHistory.count >= 3 {
                return .refused("\(co.name) has been trading for \(co.monthlyHistory.count) months. The bank wants its accounts, not only the registration certificate.")
            }
        }
        let quote = loanApplicationQuote(kind: kind, amount: amount, termMonths: termMonths, companyID: companyID)
        if let r = quote.refusal { return .refused(r) }
        let before = Set(state.loans.map(\.id))
        switch takeLoan(kind: kind, amount: amount, termMonths: quote.termMonths, companyID: companyID) {
        case .declined: return .refused("The bank declined the loan on today's figures.")
        case .tooSmall: return .refused("The amount is below the bank's smallest loan.")
        case .ok: break
        }
        guard let loan = state.loans.first(where: { !before.contains($0.id) }) else { return .refused("The bank could not book the loan.") }
        let fee = quote.fee
        if fee > 0 {
            update { s, _, _ in
                if let c = companyID { Payments.companyPays(&s, companyID: c, amount: fee, category: "int", label: "Loan arrangement fee") }
                else { Payments.playerPays(&s, fee, label: "Loan arrangement fee") }
            }
        }
        return .approved(loanID: loan.id, fee: fee, disbursed: amount - fee)
    }
}
