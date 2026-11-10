import Foundation
import GameCore
import Finance
import Businesses

public enum EarlyPaymentOutcome: Equatable, Sendable {
    case paid(amount: Double)
    case refused(String)
}

public extension GameEngine {
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
                let parts = o.id.dropFirst(3).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 3, let week = Int(parts[parts.count - 1]) else { return }
                let name = parts[1..<(parts.count - 1)].joined(separator: "|")
                let owed = SupplyTerms.invoices(s, buyer: co.id).filter { $0.providerName == name && $0.dueWeek == week }.reduce(0) { $0 + $1.amount }
                guard owed > 0 else { result = .refused("That invoice is already paid."); return }
                if short(owed) { return }
                result = .paid(amount: SupplyTerms.payEarly(&s, buyer: co.id, providerName: name, dueWeek: week))
            case .tax where o.id.hasPrefix("ctax"):
                let due = co.payables["tax"] ?? 0
                guard co.taxDue, due > 1 else { result = .refused("No corporate tax is waiting to be paid."); return }
                if short(due) { return }
                let left = MonthEnd.settleTax(&s, companyIndex: i, context: ctx)
                result = .paid(amount: due - left)
            case .tax where o.id.hasPrefix("vat"):
                let v = jsRound(co.vatBalance)
                guard v > 1 else { result = .refused("No VAT is owed."); return }
                if short(v) { return }
                AccountingLedger.note(category: "tax", label: "VAT settlement")
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
