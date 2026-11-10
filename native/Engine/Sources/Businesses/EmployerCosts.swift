import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum EmployerCosts {
    public struct CompanyCost: Equatable, Sendable {
        public var people: [Int: EmployerCost.Breakdown]
        public var manager: EmployerCost.Breakdown?
        public var managerBonus: Double
        public var perksAndExpenses: Double
        public var totalMonthly: Double
        public var totalAnnual: Double { totalMonthly * 12 }
    }

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

    public static func hire(companyID: Int, personID: Int, offered: Double, terms: Hiring.Terms, state s: GameState, data: GameData) -> EmployerCost.Breakdown? {
        guard let co = s.company(companyID), let n = s.people[personID] else { return nil }
        let w = World(state: s, data: data)
        let country = w.country(co), cur = w.currency(co)
        let m = Hiring.previewRecord(person: n, offered: max(offered, w.minimumWage(co)), terms: terms, company: co, week: s.week, data: data)
        return EmployerCost.monthly(m, country: country, benefitsMonthly: jobBenefits(m, company: co, country: country, currency: cur, data: data))
    }
}
