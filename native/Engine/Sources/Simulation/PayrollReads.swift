import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses


/// A company whose payroll is late because its cash did not cover it (the Bank app's red bubble). Payroll itself is automatic: the owner fixes it by
/// putting money in, and the back pay then goes out by itself.
public struct PayrollAlert: Equatable, Sendable, Identifiable {
    public var id: Int { companyID }
    public var companyID: Int
    public var companyName: String
    /// The wages still owed.
    public var amount: Double
    /// The pay day the wages were due ("25 February 2027").
    public var dateText: String
    public var reason: String
    public var isLate: Bool
}

public extension GameEngine {
    /// Companies with wages owed because the last payroll could not be paid in full.
    func payrollAlerts() -> [PayrollAlert] {
        let t = Payday.dayNumber(week: state.week, day: state.day)
        return state.liveCompanies.compactMap { co -> PayrollAlert? in
            let cfg = Payday.config(co, today: t)
            let owed = co.payables["wages"] ?? 0
            guard cfg.lateSince != nil, owed >= 1 else { return nil }
            return PayrollAlert(companyID: co.id, companyName: co.name, amount: max(owed, co.wageShortfall),
                                dateText: Payday.dateText(Payday.nextPay(co, config: cfg, today: t)),
                                reason: "The company's cash did not cover it.", isLate: true)
        }
    }

    /// What moving a home-based company back home from its place would return, so the screen can say it before asking.
    /// `proceeds` is cash back (deposit, or the sale value less the mortgage); `shortfall` is what an owned place would still owe.
    func moveHomeQuote(companyID: Int) -> (isOwned: Bool, proceeds: Double, shortfall: Double)? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], PremisesExtras.isHomeTrade(bd) else { return nil }
        let prem = co.value("prem")
        guard prem["m2"].double > 0 else { return nil }
        if prem["owned"].bool {
            let debt = state.loans.first { $0.id == prem["loan"].int }?.balance ?? 0
            let value = prem["val"].double
            return (true, max(0, value - debt), max(0, debt - value))
        }
        return (false, prem["dep"].double, 0)
    }
}
