import Foundation
import GameCore
import Countries
import Finance

public struct MarketingChannel: Sendable {
    public var id: String
    public var name: String
    public var efficiency: Double
    public var scale: Double
    public var localShare: Double
    public var businessShare: Double
    public var minimumWeeks: Int
    public var note: String
    public var budgetOptions: [Double]
    public var isHighVariance: Bool
    public var isSlow: Bool
    public var isLoyalty: Bool
    public var isPrimeTime: Bool
    public var isNational: Bool
    public var onlyInCountry: String?
    public var popScaled: Bool = false
    public var needsCountryMedia: Bool = false

    func populationFactor(_ country: Country) -> Double { popScaled ? (max(2, country.populationMillions) / 5).squareRoot() * 0.9 : 1 }

    public func budgets(in cur: Currency) -> [Double] { budgetOptions.map { $0 == 0 ? 0 : cur.scaledPrice($0 * populationFactor(cur.country)) } }
    public func scale(in cur: Currency) -> Double { scale * cur.country.costIndex * populationFactor(cur.country) }

    public func offered(in country: Country) -> MarketingChannel? {
        guard needsCountryMedia else { return self }
        let media = country.pack["media"]["prime"]
        guard !media.isNull, !media[0].string.isEmpty else { return nil }
        var c = self
        c.name = media[0].string
        c.note = (media[1].string.isEmpty ? "" : media[1].string + " ") + note
        return c
    }
}

public struct MarketingReturn: Sendable {
    public var gain = 1.0
    public var additive = true
    public var launchWeeks = 4.0
    public var launchBoost = 0.35
    public var cityLocalPenalty = 0.25
    public var cityOnlineBonus = 0.15
    public var lifetimeFactor = 1.0
    init(json j: JSONValue) {
        func n(_ k: String, _ d: Double) -> Double { j[k].isNull ? d : j[k].double }
        gain = n("gain", gain); additive = j["additive"].isNull ? additive : j["additive"].bool
        launchWeeks = n("launchWeeks", launchWeeks); launchBoost = n("launchBoost", launchBoost)
        cityLocalPenalty = n("cityLocalPenalty", cityLocalPenalty); cityOnlineBonus = n("cityOnlineBonus", cityOnlineBonus)
        lifetimeFactor = n("lifetimeFactor", lifetimeFactor)
    }
}

public struct MarketingTables: Sendable {
    public var channels: [String: MarketingChannel]
    public var insuranceProducts: [String: [JSONValue]]
    public var goodsClasses: [(cost: Double, quality: Double)]
    public var affinityByFamily: [String: [String: Double]]
    public var affinityByTrade: [String: [String: Double]]
    public var viralByFamily: [String: [String]]
    public var viralByTrade: [String: [String]]
    public var ret: MarketingReturn

    public init(json j: JSONValue) {
        ret = MarketingReturn(json: j["RET"])
        channels = j["CH"].object.mapValues { c in
            MarketingChannel(id: "", name: c["n"].string, efficiency: c["eff"].double, scale: c["sc"].double, localShare: c["loc"].double,
                             businessShare: c["b2b"].double, minimumWeeks: c["mw"].int, note: c["note"].string,
                             budgetOptions: c["opts"].array.map { $0.double }, isHighVariance: c["var"].bool, isSlow: c["slow"].bool,
                             isLoyalty: c["loyal"].bool, isPrimeTime: c["prem"].bool, isNational: c["nat"].bool,
                             onlyInCountry: c["only"].isNull ? nil : c["only"].string,
                             popScaled: c["pop"].bool, needsCountryMedia: c["media"].bool)
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

public struct CampaignPlan: Equatable, Sendable {
    public var lockedWeeks: Int
    public var weeks: Int?
    public var totalCost: Double?
    public var nearCapacity: Bool
    public var runByChain: Bool
    public var blocked: String?
    public init(lockedWeeks: Int, weeks: Int?, totalCost: Double?, nearCapacity: Bool, runByChain: Bool, blocked: String? = nil) {
        self.lockedWeeks = lockedWeeks; self.weeks = weeks; self.totalCost = totalCost; self.nearCapacity = nearCapacity; self.runByChain = runByChain; self.blocked = blocked
    }
}

public enum Marketing {
    public static func runByChain(_ co: Company, channel: String, state s: GameState) -> Bool {
        guard let ch = Chains.chain(s, of: co), ch["rules"]["mkt"].string != "own" else { return false }
        return co.value("mk12").array.contains { $0.string == channel }
    }

    public static func lengthChoices(_ c: MarketingChannel) -> [Int] { [4, 12, 26, 52].filter { $0 >= c.minimumWeeks } }

    public static func decay(_ co: Company) -> Double {
        let core = clamp(0.955 - max(0, 55 - co.reputation) * 0.0015 - max(0, 55 - co.quality) * 0.001 + clamp((co.reputation - 60) * 0.0004, 0, 0.012), 0.9, 0.968)
        let spend = co.value("mkt").object.sorted(by: { $0.key < $1.key }).reduce(0) { $0 + $1.value["b"].double }
        return spend > 0 ? core : core * 0.96
    }

    public static func organicAwareness(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        if bd.normalDemand == 0 || ["fin", "energy", "hold", "club", "rent"].contains(bd.family) { return 0 }
        let prem = co.value("prem")
        let kind = prem["kind"].string
        let foot = !prem.isNull && Competition.isFootTraffic(kind)
        let destinations: [String: Double] = ["skires": 38, "indoorski": 30, "fun": 24, "airline": 30, "hotel": 24, "shipping": 24, "vineyard": 22]
        let online: Set<String> = ["webshop", "webdev", "mktg", "tutor"]
        let neighbourhood: [String: Double] = ["grocery": 48, "kiosk": 44, "bakery": 40, "pharmacy": 44, "hardware": 38, "cafe": 32]
        var base = destinations[bd.id] ?? (foot ? (neighbourhood[bd.id] ?? 20) : online.contains(bd.id) ? 9 : (bd.family == "project" || bd.family == "prod") ? 10 : bd.family == "logi" ? 11 : 12)
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

    static func strength(_ co: Company, _ bd: Trade, _ w: World, channel c: MarketingChannel, budget: Double, since: Double, tables: MarketingTables) -> Double {
        let scale = max(0.5, bd.normalDemand * bd.ticket / 8000)
        let aud = bd.audience
        let fit = (1 - aud) * (c.localShare == 0 ? 0.5 : c.localShare) + aud * (c.businessShare == 0 ? 0.5 : c.businessShare)
        let sc = c.scale(in: w.currency(co)) * max(0.4, min(8, scale * 0.9))
        var eff = c.efficiency * (1 - exp(-budget / sc)) * (0.45 + fit)
        if c.isNational { eff *= nationalFit(co, w) }
        eff *= channelAffinity(bd, c.id, tables.affinityByFamily, tables.affinityByTrade)
        if c.isSlow { eff *= clamp((Double(w.week) - since) / 26, 0.2, 1.4) }
        if c.isLoyalty { eff *= 0.6 + co.awareness / 100 }
        return eff * campaignFactor(c, since: since, week: w.week, cityTerm: CityMarket.sizeTerm(w.city(co)?.population ?? 150), tables.ret)
    }

    static func campaignFactor(_ c: MarketingChannel, since: Double, week: Int, cityTerm: Double, _ r: MarketingReturn) -> Double {
        let age = Double(week) - since
        let launch = r.launchWeeks > 0 ? 1 + r.launchBoost * max(0, 1 - age / r.launchWeeks) : 1
        let city = 1 - r.cityLocalPenalty * cityTerm * c.localShare + r.cityOnlineBonus * cityTerm * (1 - c.localShare)
        return launch * max(0.4, city)
    }

    static func channelAffinity(_ bd: Trade, _ k: String, _ fam: [String: [String: Double]], _ type: [String: [String: Double]]) -> Double {
        (fam[bd.family]?[k] ?? 1) * (type[bd.id]?[k] ?? 1)
    }

    static func nationalFit(_ co: Company, _ w: World) -> Double {
        let national: Set<String> = ["webshop", "shipping", "airline", "bank", "insco", "fund", "factory", "brewery", "furniture", "power", "mktg", "courier", "trucking", "casino", "hotel"]
        if national.contains(co.type) { return 1 }
        let n = Double(Competition.chainOutlets(co, w))
        return clamp(0.12 + 0.88 * min(1, log2(n) / 4), 0.12, 1)
    }

    public static func weekly(_ s: inout GameState, companyIndex i: Int, _ bd: Trade, data: GameData, tables: MarketingTables) {
        var co = s.companies[i]
        let w = World(state: s, data: data)
        var mkt = co.value("mkt")
        var mktEnd = co.value("mktEnd")
        for (k, endWeek) in mktEnd.object.sorted(by: { $0.key < $1.key }) {
            if mkt[k].isNull { mktEnd = removing(mktEnd, k); continue }
            if Double(s.week) >= endWeek.double {
                mkt = removing(mkt, k); mktEnd = removing(mktEnd, k)
                s.note("\(co.name): the \(tables.channels[k]?.name ?? "marketing") campaign has run its length and stopped.", tone: "n", companyID: co.id)
            }
        }
        co.set("mkt", mkt); co.set("mktEnd", mktEnd)
        var gain = 0.0, spend = 0.0
        var primeTimeActive = false
        let planned = co.value("mkt").object.sorted(by: { $0.key < $1.key }).reduce(0) { $0 + $1.value["b"].double }
        let reserve = Delegation.cashReserveWeeks * FinanceContext(countries: data.countries, trades: data.catalog).weeklyCost(co, s)
        let paused = planned > 0 && co.cash - planned < reserve
        if paused { var f = co.value("flags"); f["mktPausedWeek"] = .number(Double(s.week)); co.set("flags", f) }
        if paused && s.week % 4 == 0 {
            s.note("\(co.name): campaigns are paused this week, the company does not have the cash to pay for them and keep its reserve.", tone: "warn", companyID: co.id)
        }
        for (k, m) in co.value("mkt").object.sorted(by: { $0.key < $1.key }) {
            guard !paused, let c = tables.channels[k] else { continue }
            var eff = strength(co, bd, w, channel: c, budget: m["b"].double, since: m["since"].double, tables: tables)
            if c.isHighVariance {
                if c.isPrimeTime { eff *= s.random.chance(0.18) ? 1.7 : (s.random.chance(0.6) ? 0.55 : 0.9) }
                else { eff *= s.random.chance(0.12) ? 3.0 : (s.random.chance(0.55) ? 0.35 : 0.9) }
            }
            if c.isPrimeTime { primeTimeActive = true }
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
        if co.value("tm")["mkt"].double > 0 { gain *= 1 + 0.14 * co.value("tm")["mkt"].double }
        gain *= RoleEffects.awarenessFactor(co)
        if co.flag("brdMkt") { gain *= 1.05 }
        gain *= tables.ret.gain
        let ceiling = CityMarket.awarenessCeiling(co, bd, w)
        if tables.ret.additive {
            let d = decay(co)
            var base = max(0, co.awareness - co.num("adOn"))
            if co.status == .open {
                let a = organicAwareness(co, bd, w) * w.balance.mastery.organicScale
                let faded = base * d
                base = a > faded ? clamp(faded / max(0.5, d) + (a - faded) * 0.035, 0, a + 0.5) : faded
            } else { base *= d }
            let acc = max(0, co.num("adAcc") * d + gain)
            let room = max(1, ceiling - base)
            let on = min(room, room * (1 - exp(-acc / room)))
            co.set("adAcc", acc); co.set("adOn", on)
            co.awareness = clamp(base + on, 0, ceiling)
            spill(&s, from: co, gain: gain)
            s.companies[i] = co
            viralRoll(&s, companyIndex: i, bd, w, primeTimeActive: primeTimeActive, tables: tables)
            return
        }
        co.awareness = clamp(co.awareness * decay(co) + gain, 0, ceiling)
        spill(&s, from: co, gain: gain)
        s.companies[i] = co
        viralRoll(&s, companyIndex: i, bd, w, primeTimeActive: primeTimeActive, tables: tables)
        co = s.companies[i]
        if co.status == .open {
            let a = organicAwareness(co, bd, w)
            if a > co.awareness { co.awareness = clamp(co.awareness / max(0.5, decay(co)) + (a - co.awareness) * 0.035, 0, a + 0.5) }
            s.companies[i] = co
        }
    }

    public struct Estimate: Equatable, Sendable {
        public var weeklyBudget: Double
        public var awarenessWithout: Double
        public var awarenessWith: Double
        public var demandLift: Double
        public var weeklyExtraProfit: Double
        public var netPerWeek: Double
        public var paybackWeeks: Int?
        public var atCapacity: Bool
    }

    public static func estimate(_ co: Company, channel: String, weeklyBudget: Double, state s: GameState, data: GameData, tables: MarketingTables) -> Estimate? {
        guard let c = tables.channels[channel], let bd = data.catalog[co.type] else { return nil }
        let w = World(state: s, data: data)
        let mkt = co.value("mkt")
        func expected(_ ch: MarketingChannel) -> Double { ch.isPrimeTime ? 0.872 : ch.isHighVariance ? 0.886 : 1 }
        var others = 0.0
        for (k, m) in mkt.object where k != channel {
            guard let oc = tables.channels[k] else { continue }
            others += strength(co, bd, w, channel: oc, budget: m["b"].double, since: m["since"].double, tables: tables) * expected(oc)
        }
        let since = mkt[channel]["since"].isNull ? Double(w.week) - 99 : mkt[channel]["since"].double
        let mine = weeklyBudget > 0 ? strength(co, bd, w, channel: c, budget: weeklyBudget, since: since, tables: tables) * expected(c) : 0
        let d = decay(co)
        let organic = organicAwareness(co, bd, w) * w.balance.mastery.organicScale
        let ceiling = CityMarket.awarenessCeiling(co, bd, w)
        func settled(_ gain: Double) -> Double {
            let room = max(1, ceiling - organic)
            let acc = gain * tables.ret.gain / max(0.02, 1 - d)
            return min(ceiling, organic + room * (1 - exp(-acc / room)))
        }
        let without = settled(others), with = settled(others + mine)
        var a = co, b = co
        a.awareness = without; b.awareness = with
        let ratio = DemandModel.awarenessFactor(b) / max(0.01, DemandModel.awarenessFactor(a))
        let lw = co.value("lastW")
        let units = lw["units"].double, rev = lw["rev"].double, cap = lw["cap"].double, wanted = max(units, lw["D"].double)
        let perUnit = units > 0 ? rev / units : 0
        let margin = rev > 0 ? clamp(1 - lw["cogs"].double / rev, 0.05, 1) : 0.5
        let have = cap > 0 ? min(wanted, cap) : units
        let more = cap > 0 ? min(wanted * ratio, cap) : units * ratio
        let extra = max(0, more - have) * perUnit * margin * tables.ret.lifetimeFactor
        let net = extra - weeklyBudget
        var pay: Int? = nil
        if weeklyBudget <= 0 { pay = 0 }
        else if extra > weeklyBudget {
            var cum = 0.0
            for t in 1...520 {
                cum += extra * (1 - pow(d, Double(t))) - weeklyBudget
                if cum >= 0 { pay = t; break }
            }
        }
        return Estimate(weeklyBudget: weeklyBudget, awarenessWithout: without, awarenessWith: with, demandLift: ratio - 1, weeklyExtraProfit: extra, netPerWeek: net,
                        paybackWeeks: pay, atCapacity: cap > 0 && wanted >= cap * 0.98)
    }

    public static func removing(_ v: JSONValue, _ key: String) -> JSONValue {
        var o = v.object
        o.removeValue(forKey: key)
        return .object(o)
    }

    static func spill(_ s: inout GameState, from co: Company, gain: Double) {
        if gain <= 0 { return }
        for i in s.companies.indices where s.companies[i].id != co.id && s.companies[i].type == co.type && s.companies[i].status == .open && s.companies[i].countryCode != co.countryCode {
            s.companies[i].awareness = min(100, s.companies[i].awareness + gain * 0.03)
        }
    }

    static func viralRoll(_ s: inout GameState, companyIndex i: Int, _ bd: Trade, _ w: World, primeTimeActive: Bool, tables: MarketingTables) {
        var co = s.companies[i]
        if co.status != .open { return }
        let hooks = tables.viralByTrade[co.type] ?? tables.viralByFamily[bd.family] ?? ["tiktok", "meta"]
        var fit = 0.0
        for k in hooks {
            if let m = co.value("mkt")[k] as JSONValue?, !m.isNull, let c = tables.channels[k] {
                fit += min(1, m["b"].double / (c.scale(in: w.currency(co)) * 0.7)) * (c.isHighVariance ? 1.4 : 1)
            }
        }
        if primeTimeActive { fit += 1.2 }
        let season: Double = DemandModel.season(bd, w, for: co) > 1.06 ? 1.5 : 1
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
