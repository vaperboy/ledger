import Foundation
import GameCore
import Finance
import Businesses

/// What paying a coming bill early did.
public enum EarlyPaymentOutcome: Equatable, Sendable {
    /// Settled in full; `amount` is what left the account (in the company's currency).
    case paid(amount: Double)
    /// Nothing moved; the reason, in plain words.
    case refused(String)
}

public extension GameEngine {
    /// Pay a coming bill now instead of on its date (Bank > Bills). It is the same payment the due date makes, through the same code:
    /// rent and supplier bills (`Payday.payBillsEarly`, landlord paid too), supplier invoices (`SupplyTerms.payNow`), last year's corporate tax
    /// (`MonthEnd.settleTax`) and the VAT return (booked as the filing books it). Once paid the liability is gone, so the date charges nothing
    /// more for it; only costs that build up afterwards are still charged then. All or nothing: if the company's account (with its overdraft
    /// room) cannot cover the whole amount, nothing moves. Payroll and loan instalments have their own actions (`resolvePayrollAlert`, `repayLoan`).
    @discardableResult
    mutating func payObligationNow(_ o: Obligation) -> EarlyPaymentOutcome {
        var result = EarlyPaymentOutcome.refused("This payment cannot be paid early here.")
        let today = Payday.dayNumber(week: state.week, day: state.day)
        update { s, _, ctx in
            guard let i = s.companyIndex(o.companyID), s.companies[i].status.isLive else { result = .refused("That company is no longer trading."); return }
            let co = s.companies[i]
            let room = max(0, co.cash + ctx.overdraftRoom(co, s))
            func short(_ need: Double) -> Bool {
                if room >= need - 0.5 { return false }
                result = .refused("The account does not hold \(ctx.currency(co.countryCode, s).display(need)) yet. Move money in first.")
                return true
            }
            switch o.kind {
            case .bills:
                let owed = (co.payables["rent"] ?? 0) + (co.payables["other"] ?? 0)
                guard owed > 1 else { result = .refused("Nothing is owed on rent or supplier bills."); return }
                if short(owed) { return }
                if let paid = Payday.payBillsEarly(&s, i, today: today, context: ctx) { result = .paid(amount: paid) }
            case .invoice:
                // id: "inv<company>|<supplier>|<due week>"
                let parts = o.id.dropFirst(3).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 3, let week = Int(parts[parts.count - 1]) else { return }
                let name = parts[1..<(parts.count - 1)].joined(separator: "|")
                let owed = SupplyTerms.invoices(s, buyer: co.id).filter { $0.providerName == name && $0.dueWeek == week }.reduce(0) { $0 + $1.amount }
                guard owed > 0 else { result = .refused("That invoice is already paid."); return }
                if short(owed) { return }
                result = .paid(amount: SupplyTerms.payEarly(&s, buyer: co.id, providerName: name, dueWeek: week))
            case .tax where o.id.hasPrefix("ctax"):
                let due = min(co.payables["tax"] ?? 0, co.taxPrevYear)
                guard co.taxDue, due > 1 else { result = .refused("No corporate tax is waiting to be paid."); return }
                if short(due) { return }
                let left = MonthEnd.settleTax(&s, companyIndex: i, context: ctx, early: true)
                result = .paid(amount: due - left)
            case .tax where o.id.hasPrefix("vat"):
                let v = jsRound(co.vatBalance)
                guard v > 1 else { result = .refused("No VAT is owed."); return }
                if short(v) { return }
                // As the return books it: cash out, "VAT settlement", counted as tax paid, the balance and any arrears cleared.
                Ledger.moveRaw(&s, .company(co.id), -v)
                s.companies[i].addTransaction(week: s.week, amount: -v, label: "VAT settlement")
                s.stats.taxPaid += v
                s.companies[i].vatBalance = 0
                s.companies[i].set("vatOver", 0)
                result = .paid(amount: v)
            case .tax, .payroll, .loan:
                result = .refused("Payroll and loan instalments are paid with their own buttons.")
            }
        }
        return result
    }
}
