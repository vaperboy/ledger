import Foundation
import GameCore
import Countries
import Finance

/// The weekly model of a founded startup. A startup is a REAL company (trade "startup", started with `Startups.found`): its people are hired
/// and paid through the ordinary hiring and payroll, its cash, rent, tax and shares are the company's, its marketing campaigns are the
/// ordinary campaigns, and it is sold like any company. This file only supplies what makes it a startup: the product.
///
/// Product record (`rest["founded"][n]["sw16"]`, found by `cid` = the company id; the name is kept because other places read it):
/// { cat, prod, model, selfH, prog (0...1), phase: build | beta | ready | live, cust, revW, int, use, deals, price }.
///  - build / beta: developers on the payroll build it. Speed is the sum of each developer's output (their real skill), plus your own hours.
///  - ready: finished; the owner decides the launch (price, marketing, support) - nothing is sold before `Startups.launch`.
///  - live: new customers follow awareness (marketing), quality, price against the sector's reference price and the support capacity; customers
///    churn with quality and overload; revenue is customers x price; hosting and payment costs follow revenue. Wages, rent and tax are the company's.
public enum StartupModel {
    public static let tradeID = "startup"

    public static func isStartup(_ co: Company) -> Bool { co.type == tradeID }

    static func recordIndex(_ s: GameState, companyID: Int) -> Int? {
        (s.rest["founded"]?.array ?? []).firstIndex { $0["cid"].int == companyID }
    }

    /// People who build the product: developers (and designers at half output), by their real skill, 0.5 ... 1.5 each.
    public static func developerOutput(_ s: GameState, _ co: Company) -> Double {
        co.staff.filter { $0.noticeWeeks <= 0 }.reduce(0.0) { acc, m in
            let part = m.partTimeShare
            let skill = (s.people[m.id]?.skill ?? 50) / 100
            if m.role == "dev" { return acc + (0.5 + skill) * part }
            if m.role == "designer" { return acc + (0.25 + skill / 2) * part }
            return acc
        }
    }
    public static func developers(_ co: Company) -> Int { co.staff.filter { $0.role == "dev" }.count }

    /// Customers the team can look after: IT/support staff serve many, developers a few, your own hours some.
    public static func supportCapacity(_ s: GameState, _ co: Company, selfHours: Double) -> Double {
        let staff = co.staff.filter { $0.noticeWeeks <= 0 }
        let it = Double(staff.filter { $0.role == "ittech" || $0.role == "recept" }.count) * 150
        let dev = Double(staff.filter { $0.role == "dev" }.count) * 15
        return 25 + it + dev + selfHours * 1.5
    }

    /// 0...1 quality of the product: the founder's idea blended with the team's skill.
    public static func quality(_ s: GameState, _ co: Company, base q0: Double) -> Double {
        let devs = co.staff.filter { $0.role == "dev" }
        guard !devs.isEmpty else { return clamp(q0 * 0.8, 0.05, 0.95) }
        let avg = devs.reduce(0.0) { $0 + (s.people[$1.id]?.skill ?? 50) } / Double(devs.count) / 100
        return clamp(q0 * 0.55 + avg * 0.45, 0.05, 0.95)
    }

    /// The expected (no luck) funnel for a price and a marketing level: what the launch screen shows before anything is decided.
    public struct Funnel: Equatable, Sendable {
        public var newCustomersWeekly: Double
        public var capacity: Double
        public var weeklyRevenueAt: Double
    }
    public static func expectedFunnel(_ s: GameState, _ co: Company, sector d: StartupProducts.Sector, model: String, price: Double, awareness: Double, customers: Double, quality q: Double, currency cur: Currency) -> Funnel {
        let ref = cur.scaledPrice(d.arpu) / 12
        let priceF = clamp(pow(ref / max(1, price), 1.3), 0.05, 3)
        let nc = d.growth * 4 * (0.2 + awareness / 100 * 1.1) * (0.4 + q * 1.2) * priceF * (1 + customers / 250) * 0.9
        let cap = supportCapacity(s, co, selfHours: 0)
        let one = ["once", "sale", "lic"].contains(model)
        let n = max(0, min(nc, cap - customers))
        return Funnel(newCustomersWeekly: n, capacity: cap, weeklyRevenueAt: one ? n * price : (customers + n) * price * 12 / 52)
    }

    /// The company's week. Called by `CompanyWeek` (through `SpecialFamilies`) instead of the demand model.
    static func context(_ s: inout GameState, _ i: Int, _ bd: Trade, _ data: GameData) -> CompanyWeek.WeekContext {
        let empty = CompanyWeek.WeekContext(units: 0, rev: 0, cogs: 0, D: 0, cap: 0, util: 0, price: 1, paidDuringWeek: 0)
        let co = s.companies[i]
        guard let k = recordIndex(s, companyID: co.id), var list = s.rest["founded"]?.array else { return empty }
        var f = list[k]
        var w = f["sw16"]
        guard !w.isNull, let d = StartupProducts.sector(w["cat"].string) else { return empty }
        let cur = World(state: s, data: data).currency(co)
        let selfH = w["selfH"].double
        let q = quality(s, co, base: f["q0"].isNull ? 0.45 : f["q0"].double)
        f["q"] = .number(q)
        var phase = w["phase"].string, prog = w["prog"].double, cust = w["cust"].double
        let name = co.name
        if phase == "build" || phase == "beta" {
            let speed = developerOutput(s, co) + selfH / 40 * 0.7 * CapacityModel.ownerFactor(s)
            prog = min(1, prog + speed / d.work * (0.7 + q * 0.6))
            if phase == "build" && prog >= 0.5 { phase = "beta"; s.note("\(name) is ready to test. You can switch it on in your own companies.", tone: "good", companyID: co.id) }
            if prog >= 1 {
                phase = "ready"
                s.addMessage(kind: "info", from: name, title: "\(name): the product is finished", body: "Development is done. Decide the launch: the price, how much to spend on marketing, and who looks after customers. Until you launch, nothing is sold and the team's wages keep running.",
                             companyID: co.id, tone: "good")
            }
        } else if phase == "ready", s.week % 8 == 0 {
            s.note("\(name) is finished but not launched. Every week without sales costs wages.", tone: "n", companyID: co.id)
        }
        var rev = 0.0, cogs = 0.0, nc = 0.0, price = w["price"].double
        let cap = supportCapacity(s, co, selfHours: selfH)
        if phase == "live" {
            let ref = cur.scaledPrice(d.arpu) / 12
            let priceF = clamp(pow(ref / max(1, price), 1.3), 0.05, 3)
            let aware = 0.2 + co.awareness / 100 * 1.1
            let model = w["model"].string
            let raw = d.growth * 4 * aware * (0.4 + q * 1.2) * priceF * (1 + cust / 250) * s.random.range(0.5, 1.3)
            nc = max(0, min(raw.rounded(), cap - cust))
            let overload = cap > 0 ? max(0, cust / cap - 1) : 1
            let churn = 0.005 + (1 - q) * 0.02 + overload * 0.04 + (priceF < 0.5 ? 0.01 : 0)
            cust = (cust * (1 - churn)).rounded() + nc
            let one = ["once", "sale", "lic"].contains(model)
            rev = one ? nc * price : cust * price * 12 / 52 * (model == "both" ? 1.15 : 1)
            cogs = rev * bd.costOfSales
        } else if phase == "beta" || phase == "build" { cust = max(cust, phase == "beta" ? 2 + (prog * 8).rounded(.down) : 0) }
        // Your other companies that use the product pay its internal price.
        for idv in w["use"].array {
            guard let ci = s.companyIndex(idv.int), s.companies[ci].status == .open, ["beta", "live"].contains(phase) else { continue }
            let fee = jsRound(cur.scaledPrice(d.arpu) * w["int"].double / 100 * 12 / 52)
            if fee > 0 { _ = Payments.companyPays(&s, companyID: s.companies[ci].id, amount: fee, category: "oth", label: "Own product: \(name)"); rev += fee }
            if phase == "beta" && s.random.chance(0.1) {
                var g = s.companies[ci].value("gl16"); g[String(co.id)] = .number(Double(s.week + 1)); s.companies[ci].set("gl16", g)
                s.note("\(name) (test version) failed at \(s.companies[ci].name) this week.", tone: "bad", companyID: s.companies[ci].id)
            }
            if let b = data.catalog[s.companies[ci].type], let x = StartupProducts.effect(sector: w["cat"].string, product: w["prod"].string, trade: b), x.c > 0 {
                PriceMoves.addModifier(&s, ci, key: "cogsup", multiplier: 1 - x.c * (phase == "live" ? 1 : 0.6) * (0.6 + q * 0.6), weeks: 2)
            }
        }
        w["phase"] = .string(phase); w["prog"] = .number(prog); w["cust"] = .number(cust); w["revW"] = .number(jsRound(rev))
        f["sw16"] = w
        f["tr"] = .number(clamp(f["tr"].double + (q - 0.3) * 0.012 + (phase == "live" ? 0.004 : 0), 0, 1))
        list[k] = f
        s.rest["founded"] = .array(list)
        let util = cap > 0 ? min(2, cust / cap) : 0
        return CompanyWeek.WeekContext(units: nc, rev: rev, cogs: cogs, D: nc, cap: cap, util: util, price: price, paidDuringWeek: 0)
    }

    /// What an investor would pay for the company today (before the round). Pre-revenue: what was put in, rising as the product nears launch;
    /// with sales: a multiple of the yearly run rate, higher for a product customers like. Never below the company's net assets.
    public static func value(_ co: Company, state s: GameState, net: Double) -> Double {
        guard let k = recordIndex(s, companyID: co.id), let f = s.rest["founded"]?.array[k] else { return max(0, net) }
        let w = f["sw16"]
        let invested = max(co.injectedCapital, 1)
        if w["phase"].string == "live" {
            let run = w["revW"].double * 52
            let mult = 1.5 + 5 * clamp(f["q"].double, 0, 1) + 3 * clamp(f["tr"].double, 0, 1)
            return max(net, run * mult, 0)
        }
        return max(net, invested * (0.8 + 0.8 * w["prog"].double))
    }
}
