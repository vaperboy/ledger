import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

public struct PayrollAlert: Equatable, Sendable, Identifiable {
    public var id: Int { companyID }
    public var companyID: Int
    public var companyName: String
    public var amount: Double
    public var dateText: String
    public var reason: String
    public var isLate: Bool
}

public extension GameEngine {
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
