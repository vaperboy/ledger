import Foundation
import GameCore
import Countries
import Employees
import Finance

/// The weekly costs of running a company, and how they reach the books. Originals: `wagesWeek`, `rentWeek`,
/// `accWeek`, `insWeek`, `leaseWeek`, `premValueWeek`, `eqWeek` (engine/company/*.js).
///
/// Timing: wages and rent are *accrued* every week (they are an expense of the week and a debt to staff and
/// landlord); the cash leaves on payday (default the 25th) and on the last day of the month (rent, suppliers,
/// insurance, fees). See `Payday`.
public enum CompanyCosts {
    // MARK: Wages

    /// Commission owed on each seller's own full sales last week. Original: `commissionWeek`.
    static func commission(_ co: inout Company, _ bd: Trade, _ w: World) -> Double {
        let salesRoles = w.catalog.tables.salesRoles
        var staff = co.staff
        let sellerIdx = staff.indices.filter { salesRoles.contains(staff[$0].role) }
        if sellerIdx.isEmpty { return 0 }
        let rev = co.lastWeekRevenue
        let skills = sellerIdx.map { StaffModel.skill(staff[$0], person: w.state.people[staff[$0].id], salesRoles: salesRoles) + 10 }
        let total = skills.reduce(0, +)
        let daily = DailyTrade.tradesDaily(co, bd)
        var c = 0.0
        for (n, i) in sellerIdx.enumerated() {
            var s = staff[i]
            guard let mode = s.commissionMode, mode != "fix" else { continue }
            let rate = s.commissionRate
            let own = daily ? ((s.value("lw")["w"].int == w.week) ? s.value("lw")["r"].double : 0) * rate
                            : rev * skills[n] / max(1, total) * rate
            let ema = s.raw["commEma"].map { $0.isNull ? own : $0.double } ?? own
            s.set("commEma", ema * 0.9 + own * 0.1)
            s.set("lastComm", own)
            staff[i] = s
            c += own
        }
        co.staff = staff
        return c
    }

    /// Accrue this week's payroll. `factor` < 1 for a closed company. Returns the cost incl. employer charges.
    @discardableResult
    public static func wages(_ s: inout GameState, companyIndex i: Int, _ bd: Trade, data: GameData, factor f: Double = 1) -> Double {
        var co = s.companies[i]
        let w = World(state: s, data: data)
        let country = w.country(co)
        let holiday = 1 + country.leaveWeeks / 52 * 0.3  // cover for paid leave and sick days
        var gross = 0.0
        for m in co.staff where !m.isOffSeason { gross += m.monthlyWage * 12 / 52 * holiday }
        gross += co.status == .closed ? 0 : commission(&co, bd, w)
        if co.managerID != nil { gross += co.managerMonthlyWage * 12 / 52 }
        gross *= f
        let cost = gross * country.employerCostFactor
        co.addPayable("wages", cost)
        var b = co.books; b.add("wages", cost); co.books = b
        co.lastWages = cost
        s.companies[i] = co
        s.stats.wagesPaid += cost
        return cost
    }

    // MARK: Rent

    /// Rent accrues weekly; it is paid on the last day of the month. Original: `rentWeekCore`.
    public static func rent(_ s: inout GameState, companyIndex i: Int, data: GameData) {
        var co = s.companies[i]
        let prem = co.value("prem")
        if prem.isNull || prem["owned"].bool || prem["m2"].double <= 0 { return }
        let w = World(state: s, data: data)
        let currency = w.currency(co)
        if s.week > 0 && s.week % 52 == 0 {
            var p = prem
            p["rent"] = .number(currency.tidy(prem["rent"].double * (1 + max(0, s.economy.inflation))))
            co.set("prem", p)
        }
        let r = co.value("prem")["rent"].double * prem["m2"].double / 52
        co.addPayable("rent", r)
        var b = co.books; b.add("rent", r); co.books = b
        s.companies[i] = co
        PremisesExtras.rentToLandlord(&s, tenantIndex: i, rent: r)
    }

    // MARK: Fixed costs, accountant, insurance, leases

    /// Fixed overhead of the week at the company's size, city and the inflation since the start. Original: part of `weekEnd`.
    public static func fixedOverhead(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let size06 = pow(co.size, 0.6) * pow(w.city(co)?.rent ?? 1, 0.3)
        return (bd.fixedWeekly * size06 + Knobs.effect(co, bd, "w", w, sum: true)) * w.inflationIndex
    }

    /// Accountant's fee for the week. Original: `accWeek`.
    public static func accountant(_ co: Company, _ w: World) -> Double {
        let c = w.currency(co)
        var fee: Double
        if !co.value("acc").isNull { fee = co.value("acc")["fee"].double }
        else { fee = co.form == .soleTrader ? c.scaledPrice(480) : 0 }
        if w.state.hasHeadOffice("acc") { fee *= 0.8 }
        let heads = Double(co.staff.count + (co.managerID != nil ? 1 : 0))
        let sz = max(1, pow(heads / 8, 0.6))
        return fee * sz * pow(1 + max(0, w.economy.inflation), Double(w.week) / 52) * 12 / 52
    }

    /// Insurance premium for one product, per week. Original: `insPremium`.
    public static func insurancePremium(_ co: Company, product k: String, rate: Double, _ w: World) -> Double {
        let base: Double
        if k == "prop" {
            let prem = co.value("prem")
            base = max(w.currency(co).scaledPrice(100000), CompanyFigures.equipmentBookValue(co) + co.inventory + (prem["owned"].bool ? prem["val"].double * 0.5 : 0))
        } else {
            let yearRev = co.books.year["rev"] ?? 0
            base = max(w.currency(co).scaledPrice(120000), yearRev != 0 ? yearRev : (co.value("lastW")["rev"].double * 52))
        }
        let riskUp = co.value("flags")["riskUp"].bool ? 0.4 : 0
        return jsRound(base * rate / 52 * (1 + riskUp) * Advisers.premiumFactor(co))
    }

    // MARK: Depreciation and wear

    /// Equipment and vehicle wear for the week: depreciation is an expense, condition falls with use, upkeep is paid.
    /// Original: `eqWeekCore`.
    public static func equipmentWeek(_ s: inout GameState, companyIndex i: Int, utilisation util: Double, _ bd: Trade, data: GameData) {
        var co = s.companies[i]
        var books = co.books
        let mm = [1.5, 1.0, 0.6][min(2, max(0, co.maintenance))]
        let mc = [0.005, 0.011, 0.02][min(2, max(0, co.maintenance))]
        var total = 0.0, weight = 0.0, eqv = 0.0
        var upkeep = 0.0
        var eq = co.value("eq")
        for (id, r) in eq.object {
            if id == "fit" && r["bv"].double > 0 {
                let d = min(r["bv"].double, r["cost"].double / ((r["life"].isNull ? 10 : r["life"].double) * 52))
                eq[id]["bv"] = .number(r["bv"].double - d)
                books.add("dep", d)
                continue
            }
            guard let spec = bd.equipment.first(where: { $0.id == id }), r["n"].double > 0 else { continue }
            let used = r["used"].bool
            let dep = r["cost"].double / max(1, spec.lifeYears * (used ? 0.6 : 1)) / 52
            let d = min(r["bv"].double, dep)
            eq[id]["bv"] = .number(r["bv"].double - d)
            books.add("dep", d)
            let rel = r["rel"].isNull ? 1 : r["rel"].double
            var cond = clamp(r["cond"].double - 0.0012 * mm * rel * (0.4 + util), 0.05, 1)
            total += cond * r["cost"].double
            weight += r["cost"].double
            eqv += r["cost"].double
            upkeep += r["cost"].double * mc / 52
            if co.maintenance == 2 { cond = clamp(cond + 0.0009, 0, 1) }
            eq[id]["cond"] = .number(cond)
        }
        var vehicles = co.value("veh").array
        for (n, v) in vehicles.enumerated() {
            let kind = data.catalog.tables.vehicles[v["model"].string]?.kind ?? ""
            let depRate: Double = ["plane": 0.05, "bus": 0.1, "truck": 0.12, "plant": 0.1, "van": 0.15, "car": 0.16, "bike": 0.2][kind] ?? 0.15
            let d = min(v["bv"].double, v["cost"].double * depRate / 52)
            vehicles[n]["bv"] = .number(v["bv"].double - d)
            books.add("dep", d)
            let rel = v["rel"].isNull ? 1 : v["rel"].double
            vehicles[n]["cond"] = .number(clamp(v["cond"].double - 0.0014 * mm * rel * (0.4 + util), 0.05, 1))
            total += vehicles[n]["cond"].double * v["cost"].double
            weight += v["cost"].double
            eqv += v["cost"].double
            vehicles[n]["km"] = .number(v["km"].double + (bd.trait("km") ?? 500) / Double(max(1, vehicles.count)) * util)
            upkeep += v["cost"].double * mc * 1.3 / 52
        }
        co.set("eq", eq)
        co.set("veh", .array(vehicles))
        co.books = books
        co.set("eqc", weight != 0 ? total / weight : 1)
        co.set("eqv", eqv)
        s.companies[i] = co
        if upkeep > 0 { Payments.companyPays(&s, companyID: co.id, amount: upkeep, category: "oth") }
    }

    /// Owned premises follow the housing market and cost 1% of their value per year to keep. Original: `premValueWeek`.
    public static func premisesValue(_ s: inout GameState, companyIndex i: Int) {
        var co = s.companies[i]
        var prem = co.value("prem")
        guard prem["owned"].bool, prem["val"].double > 0 else { return }
        let housing = s.economy.housing
        let h0 = prem["hw"].isNull || prem["hw"].double == 0 ? housing : prem["hw"].double
        prem["val"] = .number(prem["val"].double * housing / h0)
        prem["hw"] = .number(housing)
        co.set("prem", prem)
        s.companies[i] = co
        Payments.companyPays(&s, companyID: co.id, amount: prem["val"].double * 0.01 / 52, category: "oth")
    }
}
