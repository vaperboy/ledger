import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Investments

/// The world outside the player's companies, once a week: the economy, competitors, markets.
/// Original: `econWeek` (economy_markets.js), `rivalsWeekCore` (competitors), `disruptWeek` (abroad.js).
public enum WorldWeek {
    /// Boom, steady, slowdown, recession; inflation, interest rates, fuel and material prices. Original: `econWeek`.
    public static func economy(_ s: inout GameState, data: GameData) {
        var E = s.economy
        E.weeksLeftInPhase -= 1
        if E.weeksLeftInPhase <= 0 {
            var next: [String: [String]] = [:]
            next["boom"] = ["steady", "slowdown"]
            next["steady"] = ["boom", "slowdown", "steady"]
            next["slowdown"] = ["recession", "steady"]
            next["recession"] = ["steady", "steady", "boom"]
            E.phase = s.random.pick(next[E.phase] ?? ["steady"])
            E.weeksLeftInPhase = s.random.int(20, 80)
            s.news("The economy shifts to a \"\(E.phase)\" phase.", tone: E.phase == "recession" ? "bad" : E.phase == "boom" ? "good" : "n")
        }
        let targets: [String: Double] = ["boom": 1.05, "steady": 1.0, "slowdown": 0.96, "recession": 0.9]
        let tgt = targets[E.phase] ?? 1
        E.demand += (tgt - E.demand) * 0.04 + s.random.gauss() * 0.002
        func meanRevert(_ x: Double, _ m: Double, _ k: Double, _ v: Double, _ r: inout DeterministicRandom) -> Double { x + (m - x) * k + r.gauss() * v }
        E.fuel = clamp(meanRevert(E.fuel, 1.0 + (E.phase == "boom" ? 0.1 : 0), 0.03, 0.02, &s.random), 0.6, 2.2)
        E.materials = clamp(meanRevert(E.materials, 1.0, 0.02, 0.012, &s.random), 0.75, 1.6)
        E.power = clamp(meanRevert(E.power, 1.0, 0.03, 0.05, &s.random), 0.3, 3)
        E.oil = clamp(meanRevert(E.oil, 1.0, 0.02, 0.03, &s.random), 0.3, 2.5)
        E.freight = clamp(meanRevert(E.freight, E.demand, 0.04, 0.03, &s.random), 0.5, 2.2)
        E.salmon = clamp(meanRevert(E.salmon, 1.0, 0.03, 0.03, &s.random), 0.55, 1.8)
        E.housing = clamp(E.housing * (1 + 0.0007 + (E.demand - 1) * 0.004 - (E.policyRate - 0.04) * 0.012 / 4 + s.random.gauss() * 0.0025), 0.6, 2.2)
        E.inflation = clamp(E.inflation + (0.025 + (E.demand - 1) * 0.15 - E.inflation) * 0.01 + s.random.gauss() * 0.0003, 0.0, 0.1)
        s.economy = E
        if GameCalendar.isMonthEnd(week: s.week) {
            let home = data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode)
            let want = clamp(home.startingPolicyRate + (E.inflation - 0.03) * 0.9 + (E.demand - 1) * 0.5, 0.0025, 0.2)
            if abs(want - s.economy.policyRate) > 0.0035 && s.random.chance(0.35) {
                let old = s.economy.policyRate
                s.economy.policyRate = jsRound((old + (want > old ? 0.0025 : -0.0025)) * 10000) / 10000
                let bank = home.pack["authorities"]["cb"].string
                s.news("\(bank) \(s.economy.policyRate > old ? "raises" : "cuts") the policy rate to \(Currency.percent(s.economy.policyRate, decimals: 2)).", tone: s.economy.policyRate > old ? "bad" : "good")
            }
        }
    }

    /// Local competitor markets: prices drift, rivals enter and leave. Original: `rivalsWeekCore`.
    public static func competitors(_ s: inout GameState, data: GameData) {
        var groups: [String: [Int]] = [:]
        for (i, c) in s.companies.enumerated() where c.status == .open && c.type != "club" {
            groups[c.type + "|" + c.cityID, default: []].append(i)
        }
        var mk = s.rest["mk"] ?? .object([:])
        for key in groups.keys.sorted() {
            guard let idxs = groups[key], let first = idxs.first else { continue }
            let co0 = s.companies[first]
            guard let bd = data.catalog[co0.type] else { continue }
            var m = mk[key]
            if m.isNull {
                let city = data.countries.city(co0.cityID, preferring: co0.countryCode)?.city
                let scale = (bd.family == "fin" || bd.family == "energy") ? 0.3 : 1.0
                m = .object(["key": .string(key), "n": .number(max(1, jsRound(1 + (city?.population ?? 100) / 120 + s.random.range(0, 2) * scale))),
                             "pi": 1.0, "str": .number(s.random.range(0.3, 0.8)), "aggr": .number(s.random.range(0.2, 0.9)),
                             "since": 0, "uw": 0, "calls": 0, "ev": 0])
            }
            var pi = m["pi"].double
            pi += (1 - pi) * 0.012 + s.random.gauss() * 0.003
            pi = clamp(pi, 0.78, 1.25)
            var share = 0.0
            let w = World(state: s, data: data)
            for i in idxs {
                let co = s.companies[i]
                let p = Pricing.priceIndex(co, w)
                let marketRev = max(1, (bd.normalDemand == 0 ? 1 : bd.normalDemand) * bd.ticket * (w.city(co)?.demand ?? 1) * (m["n"].double + 1))
                share += co.lastWeekRevenue / marketRev
                let aggr = m["aggr"].double
                if p < pi - 0.035 && s.random.chance(0.12 * aggr) {
                    pi = max(0.8, p + 0.01)
                } else if p > pi + 0.07 && s.random.chance(0.04 * aggr) {
                    pi = min(1.2, pi + 0.03)
                }
                let monthRev = co.books.month["rev"] ?? 0
                if p < 0.9 && co.lastWeekRevenue > 0 && monthRev > 0 && Books.expenses(co.books.month) > monthRev * 1.05 { m["uw"] = .number(m["uw"].double + 1) }
                else { m["uw"] = .number(max(0, m["uw"].double - 1)) }
            }
            m["pi"] = .number(pi)
            disruption(&s, &m, idxs, bd, data)
            if share > 0.4 && m["uw"].double > 6 && s.random.chance(0.06) { m["uw"] = 0 }
            if s.random.chance(0.0035 + (s.economy.demand > 1.02 ? 0.002 : 0)) && m["n"].double < 10 {
                m["n"] = .number(m["n"].double + 1)
                m["pi"] = .number(max(0.8, m["pi"].double - 0.015))
                s.note("A new competitor enters the \(bd.name.lowercased()) market in \(data.countries.city(co0.cityID, preferring: co0.countryCode)?.city.name ?? "town").", tone: "n")
            } else if s.random.chance(0.0025 + (s.economy.demand < 0.96 ? 0.003 : 0)) && m["n"].double > 1 {
                m["n"] = .number(m["n"].double - 1)
                s.note("A competitor in \(data.countries.city(co0.cityID, preferring: co0.countryCode)?.city.name ?? "town") closes down.", tone: "good", companyID: co0.id)
            }
            mk[key] = m
        }
        s.rest["mk"] = mk
    }

    /// A cheap rival with a loophole enters and drags prices; regulators eventually close it. Original: `disruptWeek`.
    static func disruption(_ s: inout GameState, _ m: inout JSONValue, _ idxs: [Int], _ bd: Trade, _ data: GameData) {
        let c0 = s.companies[idxs[0]]
        if !m["dis"].isNull {
            let d = m["dis"]
            if Double(s.week) - d["w0"].double > d["dur"].double || s.random.chance(0.004) {
                s.note("The cheap rival \(d["name"].string) is shut down by regulators. Prices recover.", tone: "good", companyID: c0.id)
                m["dis"] = .null
                m["dcool"] = .number(Double(s.week + 52))
            }
            return
        }
        if s.week < 30 || (!m["dcool"].isNull && Double(s.week) < m["dcool"].double) || bd.family == "fin" || bd.family == "energy" { return }
        let pl = data.countries[c0.countryCode]?.priceLevel ?? 1
        guard s.random.chance(0.0016 * (0.6 + pl)) else { return }
        let reasons = ["uses undeclared cheap labour", "dumps products below cost", "found a loophole in the licensing rules", "is backed by investors and burning cash", "skips costly safety routines"]
        let name = s.random.pick(["Budget", "Quick", "Smart", "Value", "Low Cost"]) + " " + s.random.pick(["Group", "Direct", "Partners"])
        let depth = s.random.range(0.12, 0.32), dur = s.random.int(40, 110)
        let why = s.random.pick(reasons)
        m["dis"] = .object(["w0": .number(Double(s.week)), "depth": .number(depth), "dur": .number(Double(dur)), "name": .string(name), "why": .string(why)])
        for i in idxs {
            let co = s.companies[i]
            let city = data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? "town"
            s.addMessage(from: "Market", title: "A cheap rival enters your market",
                         body: "\(name) \(why) and sells far below normal prices in \(city). Expensive operations are hit hardest. You can cut costs, lower prices, or build quality and brand to keep loyal customers.",
                         companyID: co.id, tone: "bad")
        }
    }
}
