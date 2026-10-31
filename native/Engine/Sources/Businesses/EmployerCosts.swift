import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Employer cost with the company's own benefits added: the single place (on top of `EmployerCost`) that hiring previews, profiles, Team, forecasts and
/// Accounting call. Benefits that belong to one job are its bonus plan (the expected monthly amount with its on-cost) and own-car mileage;
/// perks and expense accruals are paid per company/job group and are carried as `companyLevelMonthly`.
public enum EmployerCosts {
    public struct CompanyCost: Equatable, Sendable {
        public var people: [Int: EmployerCost.Breakdown]
        public var manager: EmployerCost.Breakdown?
        /// Manager's profit share at its expected size.
        public var managerBonus: Double
        /// Perks and expense accruals (company-wide).
        public var perksAndExpenses: Double
        public var totalMonthly: Double
        public var totalAnnual: Double { totalMonthly * 12 }
    }

    /// Benefits of one job a month: the bonus plan with its on-cost, own-car mileage.
    public static func jobBenefits(_ m: StaffMember, company co: Company, country: Country, currency cur: Currency, data: GameData) -> Double {
        var b = 0.0
        if let lvl = WorkerBonus.level(of: m) { b += WorkerBonus.expectedMonthly(lvl, wage: m.monthlyWage) * (1 + country.employerOnCost(monthlyWage: m.monthlyWage)) }
        if m.flag("ownCar"), let bd = data.catalog[co.type] { b += PersonalEquipment.mileagePerMonth(cur, country: country, bd, tables: data.catalog.tables) }
        return b
    }

    public static func staff(_ m: StaffMember, company co: Company, state s: GameState, data: GameData) -> EmployerCost.Breakdown {
        let w = World(state: s, data: data)
        let country = w.country(co), cur = w.currency(co)
        return EmployerCost.monthly(m, country: country, benefitsMonthly: jobBenefits(m, company: co, country: country, currency: cur, data: data))
    }

    /// The whole company's monthly cost of its people: every job's breakdown, the manager (wage, on-cost, leave cover, profit share), perks and expenses.
    public static func company(_ co: Company, state s: GameState, data: GameData) -> CompanyCost {
        let w = World(state: s, data: data)
        let country = w.country(co), cur = w.currency(co)
        var people: [Int: EmployerCost.Breakdown] = [:]
        var sum = 0.0
        for m in co.staff {
            let b = EmployerCost.monthly(m, country: country, benefitsMonthly: jobBenefits(m, company: co, country: country, currency: cur, data: data))
            people[m.id] = b
            sum += b.totalMonthly
        }
        var mgr: EmployerCost.Breakdown?
        var bonus = 0.0
        if co.managerID != nil {
            let b = EmployerCost.monthly(wage: co.managerMonthlyWage, country: country)
            mgr = b
            bonus = ManagerModel.bonusWorth(co, co.managerProfitBonus)
            sum += b.totalMonthly + bonus
        }
        let other = StaffExpenses.monthlyCost(co, currency: cur) + StaffPerks.totalMonthlyCost(co, currency: cur)
        return CompanyCost(people: people, manager: mgr, managerBonus: bonus, perksAndExpenses: other, totalMonthly: sum + other)
    }

    /// What hiring `personID` at `offered` (monthly pay for a full week, as the offer is made) will cost, built exactly as `Hiring.hire` builds the
    /// staff record (minimum wage, pay basis, hours, seasonal), so the preview is the cost payroll books.
    public static func hire(companyID: Int, personID: Int, offered: Double, terms: Hiring.Terms, state s: GameState, data: GameData) -> EmployerCost.Breakdown? {
        guard let co = s.company(companyID), let n = s.people[personID] else { return nil }
        let w = World(state: s, data: data)
        let country = w.country(co), cur = w.currency(co)
        var m = StaffMember(raw: [:])
        m.id = personID; m.set("role", n.role)
        m.monthlyWage = max(offered, w.minimumWage(co))
        m.payBasis = Hiring.payBasis(n, terms: terms, fixedSalaryRoles: Hiring.fixedSalaryNorm).basis
        if terms.isPartTime { StaffTalks.applyPartTime(&m, terms: terms, week: s.week) } else if terms.ownCar { m.set("ownCar", 1) }
        if terms.payPlan == "com", PayPlans.eligible(role: n.role, trade: co.type, salesRoles: data.catalog.tables.salesRoles) { m.monthlyWage = 0 }
        return EmployerCost.monthly(m, country: country, benefitsMonthly: jobBenefits(m, company: co, country: country, currency: cur, data: data))
    }
}
