import Foundation
import GameCore
import Countries

public struct KnobPreview: Equatable, Sendable {
    public struct Range: Equatable, Sendable {
        public var low: Double
        public var typical: Double
        public var high: Double
    }
    public struct Measure: Equatable, Sendable {
        public var now: Range
        public var after: Range
        public var change: Double { after.typical - now.typical }
        public var uncertain: Bool { after.low <= now.high && now.low <= after.high }
    }
    public var horizon: Int
    public var demand: Measure
    public var capacity: Measure
    public var price: Measure
    public var revenue: Measure
    public var margin: Measure
    public var marginShareNow: Double
    public var marginShareAfter: Double
    public var capacityBoundAfter: Bool
    public var waitingForLicence: [String]
    public var notes: [String]
}

public extension KnobChange {
    static let previewHorizon = 8

    static func preview(_ s: GameState, _ data: GameData, marketing: MarketingTables, companyID: Int, knob knobID: String, value: Int) -> KnobPreview? {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type], let k = bd.knobs.first(where: { $0.id == knobID }) else { return nil }
        let co = s.companies[i]
        guard co.status == .open || co.status == .setup, !RentalFinance.handles(bd), bd.family != "project", !SpecialFamilies.handles(bd), CompanyWeek.isSupported(bd) else { return nil }
        let valid = k.isMulti ? (value >= 0 && value < (1 << k.options.count)) : k.options.indices.contains(value)
        guard valid else { return nil }
        let old = currentValue(co, k)

        var proposed = s
        var waiting: [String] = []
        var knobs = proposed.companies[i].value("knob"); knobs[knobID] = .number(Double(value)); proposed.companies[i].set("knob", knobs)
        let gained: [KnobOption] = k.isMulti
            ? k.options.enumerated().filter { (value & ~old) & (1 << $0.offset) != 0 }.map { $0.element }
            : (value != old ? [k.options[value]] : [])
        var docs = proposed.companies[i].value("docs")
        for o in gained {
            for id in o.requiredDocs where !Knobs.documentOK(co, id) {
                docs[id] = .object(["st": .string("ok")])
                if !waiting.contains(o.name) { waiting.append(o.name) }
            }
        }
        proposed.companies[i].set("docs", docs)

        var nowW: [Week] = [], afterW: [Week] = []
        for ahead in 0..<previewHorizon {
            nowW.append(week(s, data, marketing, i, ahead: ahead))
            afterW.append(week(s, data, marketing, i, ahead: ahead, replacing: proposed.companies[i]))
        }
        func measure(_ f: (Week) -> Double, spread: Bool) -> KnobPreview.Measure {
            .init(now: range(nowW.map(f), spread: spread), after: range(afterW.map(f), spread: spread))
        }
        var notes: [String] = []
        if !waiting.isEmpty { notes.append("\(waiting.joined(separator: ", ")) needs a licence: nothing changes until it is approved, and these figures assume it is.") }
        notes.append("Seasons, weather, rivals and week-to-week luck move sales; the ranges cover the next \(previewHorizon) weeks, and a bad stretch can be worse than the low end.")
        let revNow = nowW.map { $0.revenue }.reduce(0, +), revAfter = afterW.map { $0.revenue }.reduce(0, +)
        let marNow = nowW.map { $0.margin }.reduce(0, +), marAfter = afterW.map { $0.margin }.reduce(0, +)
        let boundAfter = afterW.map { $0.demand }.reduce(0, +) > afterW.map { $0.capacity }.reduce(0, +)
        return KnobPreview(horizon: previewHorizon,
                           demand: measure({ $0.demand }, spread: false), capacity: measure({ $0.capacity }, spread: false), price: measure({ $0.price }, spread: false),
                           revenue: measure({ $0.revenue }, spread: true), margin: measure({ $0.margin }, spread: true),
                           marginShareNow: revNow > 0 ? marNow / revNow : 0, marginShareAfter: revAfter > 0 ? marAfter / revAfter : 0,
                           capacityBoundAfter: boundAfter, waitingForLicence: waiting, notes: notes)
    }

    private struct Week { var demand: Double, capacity: Double, price: Double, revenue: Double, margin: Double }

    private static func week(_ s: GameState, _ data: GameData, _ marketing: MarketingTables, _ i: Int, ahead: Int, replacing company: Company? = nil) -> Week {
        var t = s
        if let company { t.companies[i] = company }
        t.week += ahead
        let co = t.companies[i]
        guard let bd = data.catalog[co.type] else { return Week(demand: 0, capacity: 0, price: 0, revenue: 0, margin: 0) }
        let w = World(state: t, data: data)
        let demand = DemandModel.compute(co, bd, w).customers
        let cap = CapacityModel.compute(co, bd, w).capacity
        let price = Pricing.ticket(co, bd, w)
        let rate = CompanyWeek.costRate(co, bd, w, state: t, goods: CompanyWeek.goodsEffect(co, bd, marketing, t, data))
        let sold = max(0, min(demand, cap))
        let revenue = sold * price
        return Week(demand: demand, capacity: cap, price: price, revenue: revenue, margin: revenue * (1 - rate) - CompanyCosts.fixedOverhead(co, bd, w))
    }

    private static func range(_ v: [Double], spread: Bool) -> KnobPreview.Range {
        guard let lo = v.min(), let hi = v.max() else { return .init(low: 0, typical: 0, high: 0) }
        let mean = v.reduce(0, +) / Double(v.count)
        let e = spread ? 2 * CompanyWeek.salesNoise : 0
        return .init(low: lo - abs(lo) * e, typical: mean, high: hi + abs(hi) * e)
    }
}
