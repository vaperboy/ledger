import Foundation
import GameCore
import Countries
import Finance

/// The salmon farm: fish are stocked in cohorts, grow for about 78 weeks, and are harvested at the market price. Nothing is sold for
/// over a year. Disease (sea lice, storms, algae) lowers the number of fish. Original: `FAM.salmon` (engine/company/family_basic.js).
///
/// Kept in the save under `fm`: `coh` [{n fish, kg each, age weeks, dead, illx extra illness}], `bio` tonnes in the water,
/// `price` per kilo. `flags.autoStock` and `flags.harvest` set to 0 stop stocking and harvesting.
public enum SalmonModel {
    public struct Cohort: Equatable {
        public var n: Double, kg: Double, age: Double, dead: Double, illness: Double
        init(_ j: JSONValue) { n = j["n"].double; kg = j["kg"].double; age = j["age"].double; dead = j["dead"].double; illness = j["illx"].double }
        var json: JSONValue { .object(["n": .number(n), "kg": .number(kg), "age": .number(age), "dead": .number(dead), "illx": .number(illness)]) }
        public init(n: Double, kg: Double, age: Double, dead: Double, illness: Double) { self.n = n; self.kg = kg; self.age = age; self.dead = dead; self.illness = illness }
    }

    /// Spot price per kilo at the market index. Original: `84 * S.econ.salmon`.
    public static func spotPerKilo(economy salmon: Double) -> Double { 84 * salmon }

    /// Smolt in a new cohort: a fish count from the farm's size, then divided by the density choice (as in the original).
    public static func smoltCount(tonnes: Double, densityCapacityEffect k: Double) -> Double { jsRound(tonnes / 4.6 * 1000 * 0.98 / k) }
    public static func smoltCost(count: Double, inflation: Double, week: Int) -> Double { count * 14.5 * pow(1 + inflation, Double(week) / 52) }

    /// One week of one cohort: growth, deaths and feed cost. `chanceHit` is the roll for a sudden disease event.
    /// Original: the `fm.coh.forEach` body.
    public static func growWeek(_ c: inout Cohort, growWeeks: Double, growthQuality: Double, illness ill: Double, feedChange: Double, month: Int, diseaseHit: Bool) -> Double {
        c.age += 1
        let summer = [6, 7, 8, 9].contains(month) ? 1.0 : 0.5
        let g = (5.3 - 0.1) / growWeeks * growthQuality * (1 + 0.15 * sin(c.age / 6)) * (0.8 + 0.4 * summer)
        c.kg += g
        let mort = 0.0016 * ill * (1 + c.illness * 10) + (diseaseHit ? 0.04 : 0)
        let dead = c.n * min(0.5, mort)
        c.n -= dead
        c.dead += dead
        if c.illness != 0 { c.illness *= 0.8 }
        return g * c.n * 1.25 * 27 * (1 + feedChange)
    }

    static func context(_ s: inout GameState, _ i: Int, _ bd: Trade, _ data: GameData) -> CompanyWeek.WeekContext {
        var co = s.companies[i]
        var fm = co.value("fm")
        var cohorts = fm["coh"].array.map { Cohort($0) }
        let w = World(state: s, data: data)
        let feedChange = Knobs.effect(co, bd, "c", w, sum: true)
        let growthQuality = 1 + Knobs.effect(co, bd, "q", w, sum: true) * 0.01
        let ill = Knobs.effect(co, bd, "r", w)
        let tonnes = bd.trait("tonnes") ?? 3500, grow = bd.trait("grow") ?? 78
        let month = GameCalendar.month(week: s.week)
        let autoStock = co.value("flags")["autoStock"].isNull || co.value("flags")["autoStock"].double != 0
        let harvestOn = co.value("flags")["harvest"].isNull || co.value("flags")["harvest"].double != 0
        // Stock a new cohort if there is none, or the last is older than 38 weeks and there are fewer than two, and the cash allows.
        if autoStock, cohorts.count < 2, cohorts.isEmpty || (cohorts.last?.age ?? 0) > 38 {
            let n = smoltCount(tonnes: tonnes, densityCapacityEffect: Knobs.effect(co, bd, "k", w))
            let cost = smoltCost(count: n, inflation: s.economy.inflation, week: s.week)
            if co.cash > cost * 1.1 {
                Payments.companyPays(&s, companyID: co.id, amount: cost, category: "cogs", label: "Smolt")
                cohorts.append(Cohort(n: n, kg: 0.1, age: 0, dead: 0, illness: 0))
                s.note("New salmon cohort stocked at \(co.name).", tone: "n", companyID: co.id)
            }
        }
        var rev = 0.0, cogs = 0.0, biomass = 0.0, units = 0.0
        for k in cohorts.indices {
            let hit = s.random.chance(0.002 * ill)
            cogs += growWeek(&cohorts[k], growWeeks: grow, growthQuality: growthQuality, illness: ill, feedChange: feedChange, month: month, diseaseHit: hit)
            biomass += cohorts[k].n * cohorts[k].kg / 1000
        }
        let spot = spotPerKilo(economy: s.economy.salmon)
        co = s.companies[i]
        let cur = Currency(country: data.countries.resolve(co.countryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values))
        var kept: [Cohort] = []
        for c in cohorts {
            if c.kg >= 5.1 && harvestOn {
                let t = c.n * c.kg * 0.88 / 1000
                let r = t * 1000 * spot
                rev += r
                units += t
                s.note("Harvest at \(co.name): \(Int(jsRound(t))) tonnes sold at \(Int(jsRound(spot))) per kg = \(cur.short(r)).", tone: "good", companyID: co.id)
            } else { kept.append(c) }
        }
        cogs += biomass * 1000 * 0.15
        fm["coh"] = .array(kept.map { $0.json })
        fm["bio"] = .number(biomass)
        fm["price"] = .number(spot)
        co.set("fm", fm)
        s.companies[i] = co
        return CompanyWeek.WeekContext(units: units, rev: rev, cogs: cogs, D: 0, cap: 0, util: 0.7, price: spot * 1000, paidDuringWeek: 0)
    }

    /// An illness event hits every cohort. Original: `FAM.salmon.fx`.
    public static func applyIllness(_ s: inout GameState, companyIndex i: Int, amount: Double) {
        guard amount != 0 else { return }
        var fm = s.companies[i].value("fm")
        fm["coh"] = .array(fm["coh"].array.map { var c = $0; c["illx"] = .number(c["illx"].double + amount); return c })
        s.companies[i].set("fm", fm)
    }

    /// Cash needed to stock the first cohort. Original: the checklist of `FAM.prod`.
    public static func firstStockingCash(_ bd: Trade) -> Double { (bd.trait("tonnes") ?? 3500) / 4.6 * 1000 * 14.5 }

    /// Extra buffer for the 15 months with no sales, in the start-up estimate. Original: `setupEstimate` (salmon step).
    public static func startupBuffer(_ bd: Trade, size: Double, country: Country) -> Double {
        country.costIndex * 2_300_000 * pow(size, 0.9) * 0.85 * (bd.trait("grow") ?? 78)
    }

    // MARK: Reading for screens

    public struct FishCohort: Identifiable, Equatable {
        public var id: Int
        public var age: Int
        public var fish: Double
        public var kilosEach: Double
        public var readyShare: Double
    }
    public static func cohorts(_ co: Company) -> [FishCohort] {
        co.value("fm")["coh"].array.enumerated().map { FishCohort(id: $0.offset, age: $0.element["age"].int, fish: $0.element["n"].double, kilosEach: $0.element["kg"].double, readyShare: min(1, $0.element["kg"].double / 5.1)) }
    }
}
