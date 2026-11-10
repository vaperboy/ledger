import Foundation
import GameCore
import Countries
import Employees

public struct DemandResult: Equatable {
    public var customers: Double
    public var parts: [(name: String, value: Double)]

    public func part(_ name: String) -> Double? { parts.first { $0.name == name }?.value }
    public static func == (a: DemandResult, b: DemandResult) -> Bool { a.customers == b.customers && a.parts.map { $0.name } == b.parts.map { $0.name } }
}

public enum DemandModel {
    public static func compute(_ co: Company, _ bd: Trade, _ w: World) -> DemandResult {
        var parts: [(name: String, value: Double)] = [("base", bd.normalDemand)]
        let city = w.city(co)
        let cityDemand = city?.demand ?? 1
        var D = bd.normalDemand * w.balance.demandDesignFactor * cityDemand
        func apply(_ name: String, _ f: Double) { D *= f; parts.append((name, f)) }

        parts.append(("city", cityDemand))
        apply("season", season(bd, w, for: co))
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
        let channel = SalesChannel.demandFactor(co, week: w.week, seed: w.state.seed)
        if channel != 1 { apply("channel", channel) }
        apply("economy", 1 + (w.economy.demand - 1) * (w.balance.economySensitivity[bd.family] ?? 0.8))
        let credit = creditFactor(co, w)
        if credit != 1 { apply("credit", credit) }
        apply("rivals", Competition.rivalFactor(co, w))
        let own = Competition.ownOutletShare(co, w)
        D *= own
        if own < 1 { parts.append(("own", own)) }
        let share = CityShare.factor(co, w)
        if share != 1 { apply("city share", share) }
        let events = modifier(co, "dem")
        apply("events", events)
        let players = PlayerDemand.factor(country: co.countryCode)
        if players != 1 { apply("players", players) }
        var fy = w.balance.firstYear.demandMultiplier(week: FirstYear.companyAge(co, week: w.state.week))
        if w.balance.firstYear.untended(w.state) { fy = min(fy, 1) * w.balance.firstYear.untendedDemand }
        if fy != 1 { apply("firstYear", fy) }
        if co.value("franchise")["fran"].bool { D *= 1 + co.value("franchise")["brand"].double * 0.002 }

        var r = DemandResult(customers: max(0, D) * SalesItems.demandGate(co), parts: parts)
        applySteps(&r, co, bd, w)
        return r
    }

    static let rateSensitivity: [String: Double] = ["estate": 0.8, "realdev": 1.0, "construction": 0.7, "cardealer": 0.9, "carrental": 0.3,
                                                     "boutique": 0.4, "furniture": 0.5]

    static func creditFactor(_ co: Company, _ w: World) -> Double {
        guard let k = rateSensitivity[co.type] else { return 1 }
        return clamp(1 - (w.economy.policyRate - 0.04) * k * 1.0, 0.96, 1.03)
    }

    static func modifier(_ co: Company, _ key: String) -> Double {
        co.value("mods").array.filter { $0["k"].string == key }.reduce(1) { $0 * $1["m"].double } * (key == "cogsup" ? VolumeTenders.qualityUplift(co) : 1)
    }

    static func season(_ bd: Trade, _ w: World, for co: Company? = nil) -> Double {
        let curve = w.catalog.tables.seasons[bd.seasonKey] ?? Array(repeating: 1, count: 12)
        let month = GameCalendar.month(week: w.week)
        let south = co.map { CountryTraits.isSouthernHemisphere($0.countryCode) } ?? false
        return curve[south ? (month + 6) % 12 : month]
    }

    static func awarenessFactor(_ co: Company) -> Double {
        0.08 + 1.5 * pow(clamp(co.awareness, 0, 100) / 100, 0.8)
    }

    static func applySteps(_ r: inout DemandResult, _ co: Company, _ bd: Trade, _ w: World) {
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
        if bd.normalDemand != 0 && !["fin", "energy", "club"].contains(bd.family) {
            let a = affordability(co, bd, w)
            if a != 1 { r.customers *= a; r.parts.append(("affordability", a)) }
        }
        if bd.normalDemand != 0 && !["fin", "energy", "club"].contains(bd.family) {
            let c = CityMarket.demandFactor(co, bd, w)
            if c != 1 { r.customers *= c; r.parts.append(("market class", c)) }
        }
        let fit = tradeCountryFit(co, w)
        if fit != 1 && r.customers > 0 { r.customers *= fit }
        applyWaysToSell(&r, co, bd, w)
        let fleet = PersonalEquipment.demandFactor(co, bd, w)
        if fleet != 1 { r.customers *= fleet }
        let gifts = Giving.demandFactor(co, w.state) * Luxury.wineFactor(co, w.state)
        if gifts != 1 { r.customers *= gifts }
        let ts = touristShare(co, bd, w)
        let tf = ts > 0.01 ? 1 + ts * (touristSeason(co, w) - 1) : 1
        let wx = Weather.effect(for: co, trade: bd, week: w.week, seed: w.state.seed, tables: w.balance.weather).demand
        r.customers *= wx * tf
        if wx != 1 { r.parts.append(("weather", jsRound(wx * 100) / 100)) }
        if tf != 1 { r.parts.append(("tourists", jsRound(tf * 100) / 100)) }
        let drift = managerDrift(co, bd, w)
        if drift != 0 && r.customers != 0 { r.customers *= 1 - drift * 0.5 }
        let salesHead = co.value("tm")["sales"].double
        if salesHead > 0 && r.customers != 0 { r.customers *= 1 + (0.035 + 0.055 * bd.businessShare) * salesHead }
        let chase = ManagerTargets.demandFactor(co, week: w.week)
        if chase != 1 && r.customers != 0 { r.customers *= chase }
        let homeKind = bd.premisesKind == "home"
        if homeKind && (co.value("prem")["m2"].double > 0) && bd.businessShare >= 0.4 && r.customers != 0 { r.customers *= 1.06 }
        if r.customers != 0, !w.state.rest["founded"].isNullOrEmpty {
            let x = StartupProducts.effectNow(co, w.state, trade: bd)
            if x.d != 0 { r.customers *= 1 + x.d; r.parts.append(("own product", 1 + x.d)) }
        }
        if homeKind && !(co.value("prem")["m2"].double > 0) && r.customers != 0 {
            r.customers *= max(0.72, min(0.95, 0.72 + co.awareness * 0.005))
        }
        let kept = EquipmentOutage.compute(co, bd, w).kept
        if kept < 1 && r.customers != 0 { r.customers *= kept; r.parts.append(("machines in repair", kept)) }
    }

    static func managerDrift(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        guard co.managerID != nil, w.state.people[co.managerID!] != nil, co.status == .open, bd.family != "club" else { return 0 }
        let lastMeeting = co.value("meetW").isNull ? -1e9 : co.num("meetW")
        let started = co.value("mgrW0").isNull ? Double(co.openedWeek ?? 0) : co.num("mgrW0")
        let since = Double(w.week) - max(lastMeeting, started)
        let weeks = since - 8
        if weeks <= 0 { return 0 }
        return min(0.12, weeks * 0.005 * (co.flag("boss56") ? 0.5 : 1))
    }

    static func applyWaysToSell(_ r: inout DemandResult, _ co: Company, _ bd: Trade, _ w: World) {
        let ways = w.balance.salesWays[co.type] ?? []
        guard !ways.isEmpty || SalesChannel.takesContracts(co), co.status == .open, r.customers >= 0 else { return }
        let s = co.value("sw33")
        let on = s["on"]
        let d0 = r.customers
        var f = 1.0
        func way(_ k: String) -> Balance.SalesWay? { ways.first { $0.kind == k } }
        if let p = way("platform"), on["platform"].bool {
            let fill = (p.options["deliv"] ?? 0) > 0 ? IntercompanySupply.deliveryFill(w.state, buyer: co, way: p) : 1
            f *= 1 + (p.options["lift"] ?? 0.2) * fill
        }
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

    public static func conceptFit(_ co: Company, _ w: World) -> Double {
        if !co.value("fit").isNull { return co.num("fit") }
        var r = HashedRandom("\(w.state.seed):fit:\(co.id)")
        let u = max(1e-6, r.next()), v = r.next()
        let g = (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v)
        return jsRound(clamp(exp(g * w.balance.fitSpread), 0.5, 1.7) * 1000) / 1000
    }

    static func affordability(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let bp = w.country(co).buyingPower
        if abs(bp - 1) < 0.005 { return 1 }
        let tk = max(1, bd.ticket * bd.ticketMultiplier)
        let dear = clamp(log10(tk / 150) / 2.5, 0, 1)
        var ex = (0.2 + 0.9 * dear) * (1 - 0.6 * bd.audience) * clamp(Pricing.priceIndex(co, w), 0.7, 1.6)
        ex *= 1 - 0.15 * clamp((co.reputation - 50) / 50, 0, 1)
        return pow(bp, ex)
    }

    static func tradeCountryFit(_ co: Company, _ w: World) -> Double {
        guard let t = w.balance.tradeCountryFit.demand[co.type] else { return 1 }
        return t[co.countryCode] ?? t["_"] ?? 1
    }

    static func touristShare(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let trade = w.balance.tourismShareByTrade[co.type] ?? 0.03
        let visitors = CityMarket.visitorShare(country: w.country(co), city: w.city(co))
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
