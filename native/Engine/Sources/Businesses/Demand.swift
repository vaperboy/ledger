import Foundation
import GameCore
import Countries
import Employees

/// How many customers want to buy this week, and why.
public struct DemandResult: Equatable {
    public var customers: Double
    /// The factors, in the order they were applied. Each is a multiplier (except `base`, the starting number).
    public var parts: [(name: String, value: Double)]

    public func part(_ name: String) -> Double? { parts.first { $0.name == name }?.value }
    public static func == (a: DemandResult, b: DemandResult) -> Bool { a.customers == b.customers && a.parts.map { $0.name } == b.parts.map { $0.name } }
}

/// The weekly demand model. Original: `demandCore` (engine/company/model.js) and its 'demand' steps.
///
/// customers = normal demand x city x season x how well known you are x chain x buzz x reputation x price x
///             business choices x economy x rivals x your other outlets x events, then adjusted by local market
///             fit, what local people can afford, the trade's fit with the country and tourists.
public enum DemandModel {
    public static func compute(_ co: Company, _ bd: Trade, _ w: World) -> DemandResult {
        var parts: [(String, Double)] = [("base", bd.normalDemand)]
        let city = w.city(co)
        let cityDemand = city?.demand ?? 1
        var D = bd.normalDemand * w.balance.demandDesignFactor * cityDemand
        func apply(_ name: String, _ f: Double) { D *= f; parts.append((name, f)) }

        parts.append(("city", cityDemand))
        apply("season", season(bd, w))
        apply("marketing", awarenessFactor(co))
        apply("chain", Competition.chainReachFactor(co, w))
        apply("buzz", 1 + co.num("hype") * 0.006)
        apply("reputation", 0.6 + 0.8 * co.reputation / 100)
        let pe = Pricing.demandEffect(co, bd, w)
        D *= pe
        let prem = co.value("prem")
        if !prem.isNull, prem["loc"].double != 0, Competition.isFootTraffic(prem["kind"].string) { D *= prem["loc"].double }
        parts.append(("price", pe))
        apply("choices", Knobs.effect(co, bd, "d", w))
        apply("economy", 1 + (w.economy.demand - 1) * (w.balance.economySensitivity[bd.family] ?? 0.8))
        apply("rivals", Competition.rivalFactor(co, w))
        let own = Competition.ownOutletShare(co, w)
        D *= own
        if own < 1 { parts.append(("own", own)) }
        let events = modifier(co, "dem")
        apply("events", events)
        if co.value("franchise")["fran"].bool { D *= 1 + co.value("franchise")["brand"].double * 0.002 }

        var r = DemandResult(customers: max(0, D), parts: parts)
        applySteps(&r, co, bd, w)
        return r
    }

    /// Temporary effects on a company (events, one-off bonuses). Original: `modProd(co, key)`.
    static func modifier(_ co: Company, _ key: String) -> Double {
        co.value("mods").array.filter { $0["k"].string == key }.reduce(1) { $0 * $1["m"].double }
    }

    static func season(_ bd: Trade, _ w: World) -> Double {
        let curve = w.catalog.tables.seasons[bd.seasonKey] ?? Array(repeating: 1, count: 12)
        return curve[GameCalendar.month(week: w.week)]
    }

    /// An unknown business gets few customers. Original: `window.mktMult` (realistic_odds.js).
    static func awarenessFactor(_ co: Company) -> Double {
        0.08 + 1.5 * pow(clamp(co.awareness, 0, 100) / 100, 0.8)
    }

    // MARK: Steps (original `addStep('demand', ...)` in later files, applied in this order)

    static func applySteps(_ r: inout DemandResult, _ co: Company, _ bd: Trade, _ w: World) {
        // 20: local market size, concept fit and price drift
        if bd.normalDemand != 0 && !Pricing.noWorkFamilies.contains(bd.family) {
            let city = w.city(co)
            let k = w.balance.demandLevelByTrade[bd.id] ?? w.balance.defaultDemandLevel
            let dem = city?.demand ?? 1
            let ref = referenceStaffing(co, bd, w)
            let scale = ref * k * pow(dem, 0.3) / (w.balance.demandDesignFactor * dem)
            let pe = Pricing.elasticityDrift(co, bd, w)
            let inflationHold = pow(co.num("ig", 1), (bd.elasticity == 0 ? 1 : bd.elasticity) * 0.7)
            let projectScale = (bd.family == "project" && !bd.hasTrait("dev")) ? 1 / Pricing.jobScale(co) : 1
            r.customers *= scale * conceptFit(co, w) * pe * inflationHold * projectScale
            if let i = r.parts.firstIndex(where: { $0.name == "price" }) { r.parts[i].value *= pe * inflationHold }
        }
        // 50: what local people can afford
        if bd.normalDemand != 0 && !["fin", "energy", "hold", "club"].contains(bd.family) {
            let a = affordability(co, bd, w)
            if a != 1 { r.customers *= a; r.parts.append(("affordability", a)) }
        }
        // 60: commodities sell all they make (farms)
        // 86: some trades fit some countries better
        let fit = tradeCountryFit(co, w)
        if fit != 1 && r.customers > 0 { r.customers *= fit }
        // 90: ways to sell (platforms, memberships, peak seasons, contracts)
        applyWaysToSell(&r, co, bd, w)
        // 94: tourists
        let ts = touristShare(co, bd, w)
        let tf = ts > 0.01 ? 1 + ts * (touristSeason(co, w) - 1) : 1
        let wx = Weather.effect(for: co, trade: bd, week: w.week, seed: w.state.seed, tables: w.balance.weather).demand
        r.customers *= wx * tf
        if wx != 1 { r.parts.append(("weather", jsRound(wx * 100) / 100)) }
        if tf != 1 { r.parts.append(("tourists", jsRound(tf * 100) / 100)) }
        // 96: a manager nobody checks on lets service slip
        let drift = managerDrift(co, bd, w)
        if drift != 0 && r.customers != 0 { r.customers *= 1 - drift * 0.5 }
        // 85: a sales director brings more customers, most in business-to-business trades (ManagerTeam)
        let salesHead = co.value("tm")["sales"].double
        if salesHead > 0 && r.customers != 0 { r.customers *= 1 + (0.035 + 0.055 * bd.businessShare) * salesHead }
        // 100: own premises: business clients trust you more
        let homeKind = bd.premisesKind == "home"
        if homeKind && (co.value("prem")["m2"].double > 0) && bd.businessShare >= 0.4 && r.customers != 0 { r.customers *= 1.06 }
        // 110: from home, clients come slowly
        if homeKind && !(co.value("prem")["m2"].double > 0) && r.customers != 0 {
            r.customers *= max(0.72, min(0.95, 0.72 + co.awareness * 0.005))
        }
    }

    /// A manager nobody has met for months works a little worse. Original: `OA59.drift`.
    static func managerDrift(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        guard co.managerID != nil, w.state.people[co.managerID!] != nil, co.status == .open, bd.family != "club", co.type != "hold" else { return 0 }
        let lastMeeting = co.value("meetW").isNull ? -1e9 : co.num("meetW")
        let started = co.value("mgrW0").isNull ? Double(co.openedWeek ?? 0) : co.num("mgrW0")
        let since = Double(w.week) - max(lastMeeting, started)
        let weeks = since - 8
        if weeks <= 0 { return 0 }
        return min(0.12, weeks * 0.005 * (co.flag("boss56") ? 0.5 : 1))   // a boss above the manager halves the pace (ManagerTeam.teamWeek)
    }

    /// Ways to sell. Original: the 'ways to sell' demand step (trade_sales_mechanics.js).
    static func applyWaysToSell(_ r: inout DemandResult, _ co: Company, _ bd: Trade, _ w: World) {
        guard let ways = w.balance.salesWays[co.type], !ways.isEmpty, co.status == .open, r.customers >= 0 else { return }
        let s = co.value("sw33")
        let on = s["on"]
        let d0 = r.customers
        var f = 1.0
        func way(_ k: String) -> Balance.SalesWay? { ways.first { $0.kind == k } }
        if let p = way("platform"), on["platform"].bool { f *= 1 + (p.options["lift"] ?? 0.2) }
        if way("members") != nil, on["members"].bool {
            let dc = max(0.3, bd.normalDemand * (w.city(co)?.demand ?? 1))
            f *= 1 + min(0.2, s["mem"].double / (dc * 6 + 1))
        }
        if let pk = way("peak"), pk.peakMonths.contains(GameCalendar.month(week: w.week) + 1) { f *= 1 + (pk.options["b"] ?? 0.3) }
        if way("emergency") != nil, on["emergency"].bool { f *= 1.07 }
        let referral = way("referral") != nil ? s["ref"].double : 0
        let contracts = s["ct"].array.reduce(0) { $0 + $1["u"].double }
        let oneOffs = s["one"].array.filter { $0["w"].int == w.week }.reduce(0) { $0 + $1["u"].double }
        r.customers = d0 * f + referral + contracts + oneOffs
        r.parts.append(("sales33", d0 > 0 ? r.customers / d0 : 1))
    }

    /// A bigger customer-facing team brings in more customers. Original: `demRef`.
    static func referenceStaffing(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let face = w.balance.customerFacingRoles
        let fr = bd.standardStaff.filter { face.contains($0.role) }
        if fr.isEmpty { return 0.5 * co.size + 0.5 * clamp(co.size, 0.2, 2.5) }
        let ownF = (bd.standardStaff.first.map { face.contains($0.role) } ?? false) ? bd.ownerFTE : 0
        let heads = fr.reduce(0) { $0 + $1.count } + ownF
        let have = Double(co.staff.filter { face.contains($0.role) }.count)
            + (co.managerID != nil ? 0.5 : min(1, co.ownerHours / 40) * ownF)
        return 0.5 * co.size + 0.5 * clamp(have / max(1, heads), 0.2, 2.5)
    }

    /// The hidden "fit" of the concept: location, timing, idea. Nobody sees it, results show it.
    /// Original: `fitOf` (stored in `co.fit` the first time it is needed).
    public static func conceptFit(_ co: Company, _ w: World) -> Double {
        if !co.value("fit").isNull { return co.num("fit") }
        var r = HashedRandom("\(w.state.seed):fit:\(co.id)")
        let u = max(1e-6, r.next()), v = r.next()
        let g = (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v)
        return jsRound(clamp(exp(g * w.balance.fitSpread), 0.5, 1.7) * 1000) / 1000
    }

    /// Low incomes cut back hard on expensive things, a little on cheap ones. Original: `R20.afford`.
    static func affordability(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let bp = w.country(co).buyingPower
        if abs(bp - 1) < 0.005 { return 1 }
        let tk = max(1, bd.ticket * bd.ticketMultiplier)
        let dear = clamp(log10(tk / 150) / 2.5, 0, 1)
        var ex = (0.2 + 0.9 * dear) * (1 - 0.6 * bd.audience) * clamp(Pricing.priceIndex(co, w), 0.7, 1.6)
        ex *= 1 - 0.15 * clamp((co.reputation - 50) / 50, 0, 1)
        return pow(bp, ex)
    }

    /// Original: `FIT57.dem`.
    static func tradeCountryFit(_ co: Company, _ w: World) -> Double {
        guard let t = w.balance.tradeCountryFit.demand[co.type] else { return 1 }
        return t[co.countryCode] ?? t["_"] ?? 1
    }

    /// Share of customers who are visitors. Original: `WX56.share`.
    static func touristShare(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let trade = w.balance.tourismShareByTrade[co.type] ?? 0.03
        let country = w.country(co).pack["tourism"]["share"]
        let visitors = country.isNull ? 0.1 : country.double
        return min(0.55, trade * (0.2 + 0.8 * visitors))
    }

    static func touristSeason(_ co: Company, _ w: World) -> Double {
        let table = w.balance.tourismSeasonByCountry[co.countryCode] ?? Array(repeating: 1, count: 12)
        var f = table[GameCalendar.month(week: w.week)]
        for e in w.state.rest["wx56"]?["ev"].array ?? [] {
            let wk = Double(w.week)
            if e["cc"].string == co.countryCode && wk >= e["w0"].double && wk < e["end"].double && (e["city"].isNull || e["city"].string == co.cityID) { f *= e["f"].double }
        }
        return f
    }
}
