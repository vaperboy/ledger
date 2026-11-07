import Foundation
import GameCore
import Countries
import Finance

/// Opening another outlet of a trade you already run: what it takes in cash, how long until it carries itself, and what it takes from the store you have.
/// A read for the planner and the manager's advice; opening itself is `CompanySetup` / `Chains.openStore`.
///
/// The rules the numbers follow (all in the engine already, this only adds them up):
///  - a new outlet starts unknown (awareness 10) and its name builds over a year (`Marketing.organicAwareness`), so it loses money at first;
///  - two outlets of one trade in one city share their customers (`Competition.ownOutletShare`), a second city shares none;
///  - the first year of a company is kinder (`FirstYear`), a later outlet does not get that.
public enum Expansion {
    public struct Readiness: Equatable, Sendable {
        /// What opening costs (premises, equipment, first team, a first buffer)
        public var startCost: Double
        /// Weeks until the new outlet is expected to cover its own costs
        public var rampWeeks: Int
        /// Cash to keep on top of the start cost so the ramp-up does not run you dry
        public var rampReserve: Double
        /// Start cost + reserve: the cash you should have free before you open
        public var cashNeeded: Double
        /// Share of the customers you win in that city that the new outlet takes from your existing one (0 in another city)
        public var cannibalisation: Double
        /// Your cash that is free (personal account and savings) and the existing outlet's weekly profit
        public var cashFree: Double
        public var weeklyProfitNow: Double
        public var enoughCash: Bool
        /// Short lines for the screen, most important first
        public var advice: [String]
    }

    /// Weeks a new outlet of a trade needs to find its customers: from its own name-building curve, longer for trades that live on a known name.
    static func rampWeeks(_ bd: Trade) -> Int {
        bd.family == "project" || bd.family == "prod" ? 52 : bd.audience > 0.5 ? 40 : 30
    }

    public static func readiness(_ s: GameState, data: GameData, companyID: Int, cityID: String, size: Double = 1) -> Readiness? {
        guard let co = s.company(companyID), let bd = data.catalog[co.type],
              let est = CompanySetup.estimate(tradeID: co.type, cityID: cityID, form: co.form, size: size, countryCode: co.countryCode, state: s, data: data) else { return nil }
        let w = World(state: s, data: data)
        let fc = FinanceContext(countries: data.countries, trades: data.catalog)
        let weeks = rampWeeks(bd)
        let weekly = fc.weeklyCost(co, s) * size
        // The new outlet earns a growing share of a full outlet's revenue over its ramp: on average about a third short for the whole ramp.
        let reserve = weekly * Double(weeks) * 0.35
        let start = est.total * 1.15
        let cannibal = cityID == co.cityID ? Competition.overlap(co, co, w) : 0
        let free = max(0, Payments.liquid(s))
        let history = co.monthlyHistory.suffix(6)
        let profitNow = history.isEmpty ? 0 : history.reduce(0) { $0 + $1.profit } / Double(history.count) * 12 / 52
        let needed = start + reserve
        var advice: [String] = []
        if free < needed { advice.append("Keep \(w.currency(co).short(needed)) free before you open: \(w.currency(co).short(start)) to open and \(w.currency(co).short(reserve)) to carry it for about \(weeks) weeks.") }
        if history.count < 6 || profitNow <= 0 { advice.append("Your current outlet is not yet making a steady profit. A second one doubles the bills before it brings in money.") }
        if cannibal > 0.05 { advice.append("Same city: it will take about \(Int((cannibal * 100).rounded()))% of the customers the two would otherwise share. Another city shares none.") }
        advice.append("Expect it to lose money for the first \(weeks / 2) weeks and carry itself after about \(weeks).")
        return Readiness(startCost: start, rampWeeks: weeks, rampReserve: reserve, cashNeeded: needed, cannibalisation: cannibal, cashFree: free, weeklyProfitNow: profitNow,
                         enoughCash: free >= needed, advice: advice)
    }
}
