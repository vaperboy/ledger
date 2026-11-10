import Foundation
import GameCore
import Countries
import Finance

public enum ManagerOpening {
    static let windowWeeks = 8

    static func expectedShare(_ co: Company, week: Int) -> Double {
        let age = max(0, week - (co.openedWeek ?? co.foundedWeek))
        return min(1, 0.5 + 0.1 * Double(age) + (ManagerModel.direction(of: co) == .grow ? 0.2 : 0))
    }

    public static func runDay(_ s: inout GameState, data: GameData) {
        for ci in s.companies.indices {
            let co = s.companies[ci]
            guard co.status == .open, co.managerID != nil, let n = co.managerID.flatMap({ s.people[$0] }), let bd = data.catalog[co.type],
                  s.week - (co.openedWeek ?? co.foundedWeek) < windowWeeks, ManagerModel.budget(of: co).actsAlone else { continue }
            if !bd.hasTrait("noStaff"), bd.family != "rent", hireOne(&s, ci, bd, data: data) { continue }
            if buyEquipment(&s, ci, bd, data: data) { continue }
            if let spent = StockHandling.managerOrder(&s, ci, bd, manager: n, data: data) {
                let cur = World(state: s, data: data).currency(s.companies[ci])
                ManagerVoice.record(&s, companyIndex: ci, "Ordered \(cur.display(spent)) of stock for the opening days.")
            }
        }
    }

    private static func hireOne(_ s: inout GameState, _ ci: Int, _ bd: Trade, data: GameData) -> Bool {
        let co = s.companies[ci]
        guard let boss = StaffingPlan.hirer(s, co, data: data) else { return false }
        let rows = StaffingPlan.permanentRows(s, co, bd, boss, data: data).filter { $0.vacancies > 0 }
        let weekCost = ManagerModel.weekCost(s, co, data: data)
        for row in rows {
            guard ManagerHiring.verdict(s, companyID: co.id, role: row.role, target: row.target, data: data).allowed else { continue }
            let wage = ManagerModel.marketWage(s, co, role: row.role, data: data)
            guard co.cash > weekCost * 4 + wage * 2 else { continue }
            let found = Hiring.search(role: row.role, company: co, mode: .network, faces: false, state: &s, data: data)
            guard !found.isEmpty, let p = AutoHire.hireWorker(role: row.role, companyID: co.id, candidates: found, hirer: AutoHire.hirer(person: s.people[co.managerID ?? 0]), state: &s, data: data) else { continue }
            StaffingPlan.hired(&s, companyIndex: ci, role: row.role, data: data)
            ManagerVoice.record(&s, companyIndex: ci, "Hired \(p.name) as \(row.roleName.lowercased()) to fill the plan.")
            return true
        }
        return false
    }

    private static func buyEquipment(_ s: inout GameState, _ ci: Int, _ bd: Trade, data: GameData) -> Bool {
        let co = s.companies[ci]
        let w = World(state: s, data: data)
        let share = expectedShare(co, week: s.week)
        let std = CompanySetup.standardEquipment(bd, size: co.size)
        let weekCost = ManagerModel.weekCost(s, co, data: data)
        for e in bd.equipment where CompanySetup.opensTheTrade(e, bd, tables: data.catalog.tables) {
            let full = std[e.id] ?? 1
            let want = e.isRequired && full * share < 1 ? 1 : (full * share).rounded(.up)
            let missing = want - CapacityModel.equipmentCount(co, e)
            guard missing > 0 else { continue }
            let unit = e.vehicleModels != nil ? (data.catalog.tables.vehicles[e.vehicleModels![0]]?.price ?? 0) * w.inflationIndex * 0.2 : CompanySetup.equipmentPrice(e, company: co, w)
            var q = missing
            while q >= 1, !(ManagerModel.withinBudget(co, amount: unit * q, s, data: data) && co.cash >= unit * q + weekCost * 3) { q -= 1 }
            if q < 1 {
                var fl = s.companies[ci].value("flags")
                if fl["opnAsk_\(e.id)"].isNull {
                    fl["opnAsk_\(e.id)"] = 1; s.companies[ci].set("flags", fl)
                    ManagerVoice.record(&s, companyIndex: ci, "Would buy \(e.name) for the customers expected, but one is above my budget. Your call.")
                }
                continue
            }
            guard CompanySetup.buyEquipment(&s, companyID: co.id, equipmentID: e.id, quantity: q, data: data, forceFinancing: true) else { continue }
            ManagerVoice.record(&s, companyIndex: ci, "Bought \(Int(q)) x \(e.name) for the customers expected.")
            return true
        }
        return false
    }
}
