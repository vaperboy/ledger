import Foundation
import GameCore
import Countries
import Finance

/// Money a failing company handed to its owner is taken back for its creditors when it goes bankrupt.
///
/// With one account the owner never draws money out of a company in a separate step: everything a company receives
/// (sales, loans) lands in the owner's account at once, and dividends or withdrawals move nothing. So "taken out" is the
/// company's retained cash (`Company.retainedCash`): what it brought into the account and did not spend on itself
/// (its costs, instalments, taxes), never below zero because the owner covers any shortfall. The claw-back counts the
/// rise in retained cash over each month of the last twelve whose month end found the company's loans and bills above
/// the value of its things, plus the rise since the last month end (a company going bankrupt is insolvent now).
/// It never exceeds what the creditors lost.
public enum ClawBack {
    public static let windowMonths = 12
    public static let repayMonths = 36

    /// Month-end marks the claw-back reads later: retained cash, and whether debts exceeded the company's things.
    static func mark(_ r: inout MonthRecord, _ co: Company, loans: [Loan]) {
        r.set("sur", co.retainedCash)
        r.set("insol", CompanyFigures.debts(co, loans: loans) > max(0, CompanyFigures.assets(co)) + 0.5)
    }

    /// Money the company handed its owner while it could not pay its debts, in the last twelve months.
    public static func takenOut(_ s: GameState, _ co: Company) -> Double {
        let now = GameCalendar.monthIndex(week: s.week)
        var before = 0.0
        var taken = 0.0
        for r in co.monthlyHistory where r.raw["sur"] != nil {
            let v = r.num("sur")
            if r.monthIndex > now - windowMonths, r.flag("insol") { taken += v - before }
            before = v
        }
        taken += co.retainedCash - before
        return max(0, taken)
    }

    /// Takes `amount` back from the owner: from the account while it holds money, the rest as a personal debt repaid monthly.
    @discardableResult
    static func collect(_ s: inout GameState, amount: Double, from co: Company) -> (paid: Double, owed: Double) {
        let amt = jsRound(amount)
        guard amt >= 1 else { return (0, 0) }
        let paid = jsRound(min(amt, max(0, s.cash)))
        if paid > 0 { Payments.playerPays(&s, paid, label: "Paid back to the estate of \(co.name)", companyID: co.id) }
        let owed = amt - paid
        if owed >= 1 {
            var l = Loan(raw: [:])
            l.id = s.makeID(); l.kind = "cons"; l.name = "Owed to the estate of \(co.name)"
            l.balance = owed; l.originalAmount = owed; l.margin = Banking.creditMargin(s.credit)
            l.termMonths = repayMonths; l.companyID = 0; l.startWeek = s.week; l.isGuaranteed = false
            l.monthlyPayment = Loans.annuity(principal: owed, yearlyRate: s.economy.policyRate + l.margin, months: Double(repayMonths))
            s.loans.append(l)
        }
        return (paid, max(0, owed))
    }
}
