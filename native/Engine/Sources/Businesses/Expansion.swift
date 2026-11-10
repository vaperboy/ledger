import Foundation
import GameCore
import Countries
import Finance

public enum Expansion {
    public struct Readiness: Equatable, Sendable {
        public var startCost: Double
        public var rampWeeks: Int
        public var rampReserve: Double
        public var cashNeeded: Double
        public var cannibalisation: Double
        public var cashFree: Double
        public var weeklyProfitNow: Double
        public var enoughCash: Bool
        public var advice: [String]
    }

    static func rampWeeks(_ bd: Trade) -> Int {
        bd.family == "project" || bd.family == "prod" ? 52 : bd.audience > 0.5 ? 40 : 30
    }

    public static func readiness(_ s: GameState, data: GameData, companyID: Int, cityID: String, size: Double = 1) -> Readiness? {
        guard let co = s.company(companyID), let bd = data.catalog[co.type],
              let est = CompanySetup.estimate(tradeID: co.type, cityID: cityID, size: size, countryCode: co.countryCode, state: s, data: data) else { return nil }
        let w = World(state: s, data: data)
        let fc = FinanceContext(countries: data.countries, trades: data.catalog)
        let weeks = rampWeeks(bd)
        let weekly = fc.weeklyCost(co, s) * size
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
        if cannibal > 0.05 { advice.append("Same city: it will take about \(Int(saturating: (cannibal * 100).rounded()))% of the customers the two would otherwise share. Another city shares none.") }
        advice.append("Expect it to lose money for the first \(weeks / 2) weeks and carry itself after about \(weeks).")
        return Readiness(startCost: start, rampWeeks: weeks, rampReserve: reserve, cashNeeded: needed, cannibalisation: cannibal, cashFree: free, weeklyProfitNow: profitNow,
                         enoughCash: free >= needed, advice: advice)
    }
}
