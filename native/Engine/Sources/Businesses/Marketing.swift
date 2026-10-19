import Foundation
import GameCore
import Countries
import Finance

/// Marketing channels and the weekly awareness model. Originals: `mktWeekCore` (engine/company/company.js),
/// awareness.js, organic_awareness.js. Channel data is in `marketing_insurance.json`.
///
/// A campaign never promises customers: it raises *awareness*, how many potential customers know you, by an
/// amount that depends on budget (with diminishing returns), how well the channel fits your trade and audience,
/// how long it has run, and chance for the high-variance channels. Awareness fades every week.
public struct MarketingChannel: Sendable {
    public var id: String
    public var name: String
    /// Strength per week at a full budget
    public var efficiency: Double
    /// Budget at which returns start to flatten
    public var scale: Double
    /// How local (1) or national (0) it is, and how well it reaches business customers
    public var localShare: Double
    public var businessShare: Double
    /// Minimum campaign length in weeks
    public var minimumWeeks: Int
    public var note: String
    public var budgetOptions: [Double]
    public var isHighVariance: Bool
    public var isSlow: Bool
    public var isLoyalty: Bool
    public var isPrimeTime: Bool
    public var isNational: Bool
    public var onlyInCountry: String?
}

public struct MarketingTables: Sendable {
    public var channels: [String: MarketingChannel]
    public var insuranceProducts: [String: [JSONValue]]
    public var goodsClasses: [(cost: Double, quality: Double)]
    /// How well each channel suits a family / a trade (1 = normal). Original: `CHAFF_FAM`, `CHAFF_TYPE`.
    public var affinityByFamily: [String: [String: Double]]
    public var affinityByTrade: [String: [String: Double]]
    /// Channels that can make a trade go viral. Original: `VH_FAM`, `VH_TYPE`.
    public var viralByFamily: [String: [String]]
    public var viralByTrade: [String: [String]]

    public init(json j: JSONValue) {
        channels = j["CH"].object.mapValues { c in
            MarketingChannel(id: "", name: c["n"].string, efficiency: c["eff"].double, scale: c["sc"].double, localShare: c["loc"].double,
                             businessShare: c["b2b"].double, minimumWeeks: c["mw"].int, note: c["note"].string,
                             budgetOptions: c["opts"].array.map { $0.double }, isHighVariance: c["var"].bool, isSlow: c["slow"].bool,
                             isLoyalty: c["loyal"].bool, isPrimeTime: c["prem"].bool, isNational: c["nat"].bool,
                             onlyInCountry: c["only"].isNull ? nil : c["only"].string)
        }
        for (k, _) in channels { channels[k]!.id = k }
        insuranceProducts = j["INSP"].object.mapValues { $0.array }
        goodsClasses = j["GOODS_CLS"].array.map { ($0["c"].double, $0["q"].double) }
        func table(_ v: JSONValue) -> [String: [String: Double]] { v.object.mapValues { $0.object.mapValues { $0.double } } }
        affinityByFamily = table(j["CHAFF_FAM"])
        affinityByTrade = table(j["CHAFF_TYPE"])
        viralByFamily = j["VH_FAM"].object.mapValues { $0.array.map { $0.string } }
        viralByTrade = j["VH_TYPE"].object.mapValues { $0.array.map { $0.string } }
    }

    public static func bundled() throws -> MarketingTables {
        guard let url = Bundle.module.url(forResource: "marketing_insurance", withExtension: "json", subdirectory: "Resources") else { throw CocoaError(.fileNoSuchFile) }
        return MarketingTables(json: try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)))
    }
}

public enum Marketing {
    /// How the weekly awareness fades. Original: `awareDecayCore`, then the step 'local_prices awareDecay':
    /// a company that spends nothing on marketing is forgotten 4% faster.
    public static func decay(_ co: Company) -> Double {
        let core = clamp(0.955 - max(0, 55 - co.reputation) * 0.0015 - max(0, 55 - co.quality) * 0.001 + clamp((co.reputation - 60) * 0.0004, 0, 0.012), 0.9, 0.968)
        let spend = co.value("mkt").object.values.reduce(0) { $0 + $1["b"].double }
        return spend > 0 ? core : core * 0.96
    }

    /// Awareness people have without any advertising: a shop on a street is seen, a good name spreads. Original: `organic`.
    public static func organicAwareness(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        if bd.normalDemand == 0 || ["fin", "energy", "hold", "club", "rent"].contains(bd.family) { return 0 }
        let prem = co.value("prem")
        let kind = prem["kind"].string
        let foot = !prem.isNull && Competition.isFootTraffic(kind)
        let destinations: [String: Double] = ["skires": 38, "indoorski": 30, "fun": 24]
        let online: Set<String> = ["webshop", "webdev", "mktg", "tutor"]
        var base = destinations[bd.id] ?? (foot ? 20 : online.contains(bd.id) ? 9 : (bd.family == "project" || bd.family == "prod") ? 10 : bd.family == "logi" ? 11 : 12)
        if foot, prem["loc"].double != 0 { base *= clamp(prem["loc"].double, 0.8, 1.25) }
        let pop = w.city(co)?.population ?? 150
        base *= clamp(1.25 - log10(max(20, pop)) * 0.12, 0.85, 1.15)
        let rt = Pricing.rating(co)
        base *= clamp(0.55 + (rt - 3) * 0.45, 0.35, 1.35)
        let opened = Double(co.openedWeek ?? co.foundedWeek)
        let age = Double(w.week) - opened
        base *= clamp(0.35 + age / 52 * 0.65, 0.35, 1)
        return base
    }

    static func channelAffinity(_ bd: Trade, _ k: String, _ fam: [String: [String: Double]], _ type: [String: [String: Double]]) -> Double {
        (fam[bd.family]?[k] ?? 1) * (type[bd.id]?[k] ?? 1)
    }

    /// National reach: advertising nationally is wasted on a one-shop business. Original: `natFit`.
    static func nationalFit(_ co: Company, _ w: World) -> Double {
        let national: Set<String> = ["webshop", "shipping", "airline", "bank", "insco", "fund", "factory", "brewery", "furniture", "power", "mktg", "courier", "trucking", "casino", "hotel"]
        if national.contains(co.type) { return 1 }
        let n = Double(Competition.chainOutlets(co, w))
        return clamp(0.12 + 0.88 * min(1, log2(n) / 4), 0.12, 1)
    }

    /// The weekly marketing turn. Original: `mktWeekCore` + the 'campaigns end', 'organic awareness' steps.
    /// Returns the money spent on campaigns this week (booked and paid by the caller).
    public static func weekly(_ s: inout GameState, companyIndex i: Int, _ bd: Trade, data: GameData, tables: MarketingTables) {
        var co = s.companies[i]
        let w = World(state: s, data: data)
        // Campaigns end on their date.
        var mkt = co.value("mkt")
        var mktEnd = co.value("mktEnd")
        for (k, endWeek) in mktEnd.object where Double(s.week) >= endWeek.double {
            mkt = removing(mkt, k); mktEnd = removing(mktEnd, k)
        }
        co.set("mkt", mkt); co.set("mktEnd", mktEnd)
        var gain = 0.0, spend = 0.0
        var primeTimeActive = false
        // Advertising is paid in advance: with too little cash (after the owner's reserve) the campaigns pause instead of running up debt.
        let planned = co.value("mkt").object.values.reduce(0) { $0 + $1["b"].double }
        let reserve = s.policy.reserveWeeks * FinanceContext(countries: data.countries, trades: data.catalog).weeklyCost(co, s)
        let paused = planned > 0 && co.cash - planned < reserve
        if paused { var f = co.value("flags"); f["mktPausedWeek"] = .number(Double(s.week)); co.set("flags", f) }
        if paused && s.week % 4 == 0 {
            s.note("\(co.name): campaigns are paused this week, the company does not have the cash to pay for them and keep its reserve.", tone: "warn", companyID: co.id)
        }
        let scale = max(0.5, bd.normalDemand * bd.ticket / 8000)
        let fam = tables.affinityByFamily, type = tables.affinityByTrade
        for (k, m) in co.value("mkt").object.sorted(by: { $0.key < $1.key }) {
            guard !paused, let c = tables.channels[k] else { continue }
            let aud = bd.audience
            let fit = (1 - aud) * (c.localShare == 0 ? 0.5 : c.localShare) + aud * (c.businessShare == 0 ? 0.5 : c.businessShare)
            let sc = c.scale * max(0.4, min(8, scale * 0.9))
            var eff = c.efficiency * (1 - exp(-m["b"].double / sc)) * (0.45 + fit)
            if c.isHighVariance {
                if c.isPrimeTime { eff *= s.random.chance(0.18) ? 1.7 : (s.random.chance(0.6) ? 0.55 : 0.9) }
                else { eff *= s.random.chance(0.12) ? 3.0 : (s.random.chance(0.55) ? 0.35 : 0.9) }
            }
            if c.isNational { eff *= nationalFit(co, w) }
            eff *= channelAffinity(bd, k, fam, type)
            if c.isPrimeTime { primeTimeActive = true }
            if c.isSlow { eff *= clamp((Double(s.week) - m["since"].double) / 26, 0.2, 1.4) }
            if c.isLoyalty { eff *= 0.6 + co.awareness / 100 }
            let agency = s.companies.contains { $0.type == "mktg" && $0.status == .open && $0.id != co.id }
            gain += eff * (agency ? 1.1 : 1)
            spend += m["b"].double
        }
        if spend > 0 {
            let agency = s.companies.first { $0.type == "mktg" && $0.status == .open && $0.id != co.id }
            s.companies[i] = co
            Payments.companyPays(&s, companyID: co.id, amount: spend, category: "mkt")
            if let a = agency { Payments.companyReceives(&s, companyID: a.id, amount: spend * 0.85, category: "rev", label: "Marketing for \(co.name)") }
            co = s.companies[i]
        }
        let wom = co.num("wom")
        if wom > 0.4 { gain += wom * 0.2; co.set("wom", wom * 0.88) } else { co.set("wom", 0) }
        if s.hasHeadOffice("mkt") { gain *= 1.1 }
        co.awareness = clamp(co.awareness * decay(co) + gain, 0, 100)
        spill(&s, from: co, gain: gain)
        s.companies[i] = co
        viralRoll(&s, companyIndex: i, bd, w, primeTimeActive: primeTimeActive, tables: tables)
        // People find you without advertising: awareness drifts toward the organic level.
        co = s.companies[i]
        if co.status == .open {
            let a = organicAwareness(co, bd, w)
            co.set("aw23", jsRound(a * 10) / 10)
            if a > co.awareness { co.awareness = clamp(co.awareness / max(0.5, decay(co)) + (a - co.awareness) * 0.035, 0, a + 0.5) }
            s.companies[i] = co
        }
    }

    public static func removing(_ v: JSONValue, _ key: String) -> JSONValue {
        var o = v.object
        o.removeValue(forKey: key)
        return .object(o)
    }

    /// Awareness leaks a little into other countries. Original: `awareSpill`.
    static func spill(_ s: inout GameState, from co: Company, gain: Double) {
        if gain <= 0 { return }
        for i in s.companies.indices where s.companies[i].id != co.id && s.companies[i].type == co.type && s.companies[i].status == .open && s.companies[i].countryCode != co.countryCode {
            s.companies[i].awareness = min(100, s.companies[i].awareness + gain * 0.03)
        }
    }

    /// Going viral: every kind of business has its own hook. Buzz is short-lived and only sticks if you deliver.
    /// Original: `viralRoll`.
    static func viralRoll(_ s: inout GameState, companyIndex i: Int, _ bd: Trade, _ w: World, primeTimeActive: Bool, tables: MarketingTables) {
        var co = s.companies[i]
        if co.status != .open { return }
        let hooks = tables.viralByTrade[co.type] ?? tables.viralByFamily[bd.family] ?? ["tiktok", "meta"]
        var fit = 0.0
        for k in hooks {
            if let m = co.value("mkt")[k] as JSONValue?, !m.isNull, let c = tables.channels[k] {
                fit += min(1, m["b"].double / (c.scale * 0.7)) * (c.isHighVariance ? 1.4 : 1)
            }
        }
        if primeTimeActive { fit += 1.2 }
        let season: Double = DemandModel.season(bd, w) > 1.06 ? 1.5 : 1
        var p = (0.0006 + 0.0035 * min(2.5, fit)) * season
        if co.quality >= 70 && co.reputation >= 65 { p += 0.0004 }
        if !s.random.chance(p) { return }
        let size = s.random.range(28, 60)
        co.set("hype", min(100, co.num("hype") + size))
        co.set("wom", co.num("wom") + size * 0.3)
        s.companies[i] = co
        for j in s.companies.indices where s.companies[j].id != co.id && s.companies[j].type == co.type && s.companies[j].status == .open {
            if s.random.chance(0.5) { s.companies[j].set("hype", min(100, s.companies[j].num("hype") + size * 0.25)) }
        }
        s.addMessage(from: "Market", title: "\(co.name) is suddenly everywhere", body: "A post about \(co.name) is spreading fast. The buzz brings people in. Whether it lasts depends on how you deliver.", companyID: co.id, tone: "good")
    }

}
