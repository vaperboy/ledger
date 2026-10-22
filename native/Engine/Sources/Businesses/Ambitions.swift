import Foundation
import GameCore
import Countries
import Finance

/// Ambitions: pick what kind of empire to build; each path has milestones in tiers, a perk, and a legacy score.
/// Original: features/player/ambitions.js (`PATHS`, `check`, `R27.perk`, `ACT.amb27pick`).
/// Market share and rank milestones read `MarketMap` and `CompanyRanking`; the price-war and rival-purchase counters are incremented by
/// `countEvent` (the share of all bank deposits in your country, f3a, still reads zero).
public enum Ambitions {
    public struct Milestone: Equatable, Sendable { public var id: String; public var text: String; public var now: Double; public var target: Double; public var done: Int? }
    public struct Path: Equatable, Sendable, Identifiable { public var id: String; public var name: String; public var detail: String }

    public static let roman = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
    public static let paths: [Path] = [
        Path(id: "titan", name: "Industrial titan", detail: "Build a chain of companies that feed each other: materials, production, transport, sales. Lower costs and steadier supply, but one weak link hurts the whole group."),
        Path(id: "dynasty", name: "Family dynasty", detail: "Own your companies outright, keep control, pay yourself well and never go bust. Slower, but nobody can take it from you."),
        Path(id: "dominator", name: "Market dominator", detail: "Be the biggest name in your markets: win share, buy rivals, outlast price wars. Watch the competition authority."),
        Path(id: "champion", name: "Hidden champion", detail: "Small, excellent and very profitable. Few companies, the best reviews and margins nobody else gets."),
        Path(id: "financier", name: "Financier", detail: "Make money with money: a holding company, a bank, investments and stakes. Leverage works both ways."),
        Path(id: "global", name: "Global group", detail: "Plant your flag in many countries. More markets, more currencies, more rules to follow."),
    ]
    public static func path(_ id: String) -> Path? { paths.first { $0.id == id } }

    static func state(_ s: GameState) -> JSONValue {
        s.rest["amb27"] ?? .object(["path": .null, "tier": .object([:]), "done": .object([:]), "score": 0, "since": 0, "cnt": .object(["buy": 0, "pw": 0, "bankfin": 0, "ipo": 0]), "hist": .array([]), "ask": 0])
    }
    public static func legacyScore(_ s: GameState) -> Double { state(s)["score"].double }
    public static func currentPath(_ s: GameState) -> String? { let p = state(s)["path"]; return p.isNull ? nil : p.string }
    public static func tier(_ s: GameState, _ k: String) -> Int { state(s)["tier"][k].int }
    public static func history(_ s: GameState) -> [(week: Int, text: String, pathName: String, points: Double)] {
        state(s)["hist"].array.map { ($0["w"].int, $0["t"].string, path($0["path"].string)?.name ?? "", $0["pts"].double) }
    }

    /// Legacy points from anything that earns them (giving, milestones). Original: `legacy(pts, t)`.
    public static func addLegacy(_ s: inout GameState, points: Double, text: String, path: String) {
        var a = state(s)
        a["score"] = .number(a["score"].double + points)
        var h = a["hist"].array
        h.insert(.object(["w": .number(Double(s.week)), "t": .string(text), "path": .string(path), "pts": .number(points)]), at: 0)
        if h.count > 40 { h.removeLast(h.count - 40) }
        a["hist"] = .array(h); s.rest["amb27"] = a
    }

    /// Count a win that other systems report: "buy" (a rival bought), "pw" (a price war won), "bankfin", "ipo".
    public static func countEvent(_ s: inout GameState, _ key: String) {
        var a = state(s); var c = a["cnt"]; c[key] = .number(c[key].double + 1); a["cnt"] = c; s.rest["amb27"] = a
    }

    // MARK: Facts

    final class Facts {
        let s: GameState, data: GameData, live: [Company], w: World
        init(_ s: GameState, _ data: GameData) { self.s = s; self.data = data; live = s.companies.filter { $0.status == .open || $0.status == .closed }; w = World(state: s, data: data) }
        func ann(_ c: Company) -> Double {
            let h = c.monthlyHistory.suffix(3)
            return h.isEmpty ? c.lastWeekRevenue * 52 : h.reduce(0) { $0 + $1.revenue } / Double(h.count) * 12
        }
        func ebit(_ c: Company) -> Double { CompanyFigures.yearlyProfitEstimate(c, currentWeek: s.week) }
        var rev: Double { live.reduce(0) { $0 + ann($1) * c100($1) / 100 } }
        func c100(_ c: Company) -> Double { c.ownership == 0 ? 100 : c.ownership }
        var jobs: Double { live.reduce(0) { $0 + Double($1.staff.count + ($1.managerID != nil ? 1 : 0)) } + Double((s.rest["office"]?["staff"].array ?? []).count) }
        var nw: Double { Valuation.netWorth(s, trades: data.catalog).total }
        var links: Double { Double(IntercompanySupply.links(s).count) }
        var fams: Double { Double(Set(live.compactMap { data.catalog[$0.type]?.family }).count) }
        var prodOwn: Bool { live.contains { ["prod", "project"].contains(data.catalog[$0.type]?.family ?? "") } }
        var full: Double { Double(live.filter { $0.type != "hold" && c100($0) >= 99.9 && ebit($0) > 0 }.count) }
        var years: Double { Double(s.week) / 52 }
        var control: Bool { live.filter { $0.type != "hold" }.allSatisfy { c100($0) >= 67 } }
        func rating(_ minStars: Double, _ n: Double) -> Double { Double(live.filter { $0.num("rvN") >= n && Pricing.rating($0) >= minStars }.count) }
        func marginBest(_ minRev: Double) -> Double { live.map { c in let r = ann(c); return r >= minRev && r > 0 ? ebit(c) / r : 0 }.max() ?? 0 }
        var profitPerPerson: Double { live.reduce(0) { $0 + ebit($1) * c100($1) / 100 } / max(1, jobs) }
        var abroad: Bool { live.contains { $0.countryCode != s.homeCountryCode } }
        var countries: Double { Double(Set(live.map { $0.countryCode }).count) }
        var abroadShare: Double { let t = rev; return t > 0 ? live.filter { $0.countryCode != s.homeCountryCode }.reduce(0) { $0 + ann($1) * c100($1) / 100 } / t : 0 }
        func has(_ t: String) -> Bool { live.contains { $0.type == t && $0.status == .open } }
        var listedHold: Bool { live.contains { $0.type == "hold" && $0.flag("listed") } }
        var portfolio: Double { let n = Valuation.netWorth(s, trades: data.catalog); return n.investments }
        var stakes: Double { Double((s.rest["startups"]?.array ?? []).filter { $0["st"].string != "exit" && $0["pct"].double > 0 }.count) }
        var franchAbroad: Bool { live.contains { $0.countryCode != s.homeCountryCode && (!$0.value("franchise").isNull || !$0.value("foreignOf").isNull || !$0.value("branch").isNull) } || s.companies.contains { !$0.value("fr")["masters"].array.isEmpty } }
        /// Share of the biggest market and number of markets led (more share than every rival there). Original: `shareTop`.
        lazy var marketShare: (best: Double, no1: Double) = {
            var best = 0.0, no1 = 0.0
            for m in MarketMap.markets(self.s, data: self.data) {
                let t = MarketMap.truth(self.s, m, data: self.data)
                best = max(best, t.share)
                if t.players.allSatisfy({ $0.share < t.share }) { no1 += 1 }
            }
            return (best, no1)
        }()
        /// Your place by sales: "cc" in your country, "ind" among your industries, "world". 999 without a ranking. Original: `rank`.
        func rank(_ scope: String) -> Double {
            let sc: CompanyRanking.Scope = scope == "ind" ? .industries : scope == "world" ? .world : .country
            return CompanyRanking.yourRank(self.s, data: self.data, scope: sc, metric: .revenue).map { Double($0.rank) } ?? 999
        }
    }

    static func mshort(_ v: Double, _ s: GameState, _ data: GameData) -> String {
        Currency(country: data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values)).display(v)
    }

    /// The milestones of a tier. Past tier III a path keeps going: targets triple each level. Original: `tierList`.
    public static func milestones(_ s: GameState, _ data: GameData, path k: String, tier t: Int) -> [Milestone] {
        let F = Facts(s, data)
        let cur = Currency(country: data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values))
        func K(_ v: Double) -> Double { cur.scaledPrice(v) }
        func ms(_ v: Double) -> String { cur.display(K(v)) }
        let f = t < 3 ? 1.0 : pow(3, Double(t - 2))
        let lg = f > 1 ? log(f) / log(3) : 0
        let done = state(s)["done"]
        func m(_ id: String, _ text: String, _ now: Double, _ target: Double) -> Milestone {
            let key = t < 3 ? id : id + "_\(t)"
            return Milestone(id: key, text: text, now: now, target: target, done: done[key].isNull ? nil : done[key].int)
        }
        func b(_ v: Bool) -> (Double, Double) { (v ? 1 : 0, 1) }
        let a = state(s)["cnt"]
        let tt = min(2, t)
        switch (k, tt) {
        case ("titan", 0): return [m("t1a", "Own a production or building company", b(F.prodOwn).0, 1), m("t1b", "Two of your companies supply each other", F.links, 2), m("t1c", "Group sales of \(ms(30e6)) a year", F.rev, K(30e6)), m("t1d", "50 people work for you", F.jobs, 50)]
        case ("titan", 1): return [m("t2a", "Four supply links inside the group", F.links, 4), m("t2b", "Companies in three different kinds of business", F.fams, 3), m("t2c", "Group sales of \(ms(200e6)) a year", F.rev, K(200e6)), m("t2d", "300 people work for you", F.jobs, 300)]
        case ("titan", _): return [m("t3a", "\(Int(8 * f)) supply links inside the group", F.links, 8 * f), m("t3b", "Group sales of \(ms(1e9 * f)) a year", F.rev, K(1e9 * f)), m("t3c", "\(Int(1500 * f)) people work for you", F.jobs, 1500 * f), m("t3d", f > 1 ? "Top 3 by sales in your country" : "Top 10 by sales in your country", F.rank("cc") <= (f > 1 ? 3 : 10) ? 1 : 0, 1)]
        case ("dynasty", 0): return [m("d1a", "Own all of two profitable companies", F.full, 2), m("d1b", "Pay yourself \(ms(2e6)) in dividends", s.stats.dividendsReceived, K(2e6)), m("d1c", "Three years without a bankruptcy", min(3, (Double(s.week) - max(0, s.stats.raw["bustW"]?.double ?? -999)) / 52), 3), m("d1d", "Keep at least two thirds of every company", b(F.control && !F.live.isEmpty).0, 1)]
        case ("dynasty", 1): return [m("d2a", "Own all of four profitable companies", F.full, 4), m("d2b", "Pay yourself \(ms(20e6)) in dividends", s.stats.dividendsReceived, K(20e6)), m("d2c", "Ten years in business", F.years, 10), m("d2d", "Net worth of \(ms(100e6))", F.nw, K(100e6))]
        case ("dynasty", _): let yrs = 25 + 10 * lg; return [m("d3a", "Pay yourself \(ms(150e6 * f)) in dividends", s.stats.dividendsReceived, K(150e6 * f)), m("d3b", "Net worth of \(ms(1e9 * f))", F.nw, K(1e9 * f)), m("d3c", "\(Int(yrs)) years in business", F.years, yrs), m("d3d", "Still two thirds of every company (four or more)", b(F.control && F.live.count >= 4).0, 1)]
        case ("dominator", 0): return [m("m1a", "15% of one market", F.marketShare.best * 100, 15), m("m1b", "No. 1 in one market", F.marketShare.no1, 1), m("m1c", "Buy a rival", a["buy"].double, 1)]
        case ("dominator", 1): return [m("m2a", "No. 1 in three markets", F.marketShare.no1, 3), m("m2b", "30% of one market", F.marketShare.best * 100, 30), m("m2c", "Win a price war", a["pw"].double, 1), m("m2d", "Buy three rivals", a["buy"].double, 3)]
        case ("dominator", _): return [m("m3a", "No. 1 in \(Int(6 * f)) markets", F.marketShare.no1, 6 * f), m("m3b", "45% of one market", F.marketShare.best * 100, 45), m("m3c", f > 1 ? "No. 1 among groups in your industries" : "Top 3 among groups in your industries", F.rank("ind") <= (f > 1 ? 1 : 3) ? 1 : 0, 1)]
        case ("champion", 0): return [m("h1a", "A company rated 4.3 or better (50+ reviews)", F.rating(4.3, 50), 1), m("h1b", "A 20% profit margin over a year", F.marginBest(K(1e6)) * 100, 20), m("h1c", "Profit of \(ms(300000)) per person working for you", F.profitPerPerson, K(300000))]
        case ("champion", 1): return [m("h2a", "A company rated 4.6 or better (200+ reviews)", F.rating(4.6, 200), 1), m("h2b", "A 30% margin with sales over \(ms(10e6))", F.marginBest(K(10e6)) * 100, 30), m("h2c", "A company abroad", b(F.abroad).0, 1), m("h2d", "Profit of \(ms(700000)) per person", F.profitPerPerson, K(700000))]
        case ("champion", _): return [m("h3a", "\(Int(3 * f)) companies rated 4.5 or better", F.rating(4.5, 200), 3 * f), m("h3b", "A 35% margin with sales over \(ms(50e6 * f))", F.marginBest(K(50e6 * f)) * 100, 35), m("h3c", "Profit of \(ms(1.5e6 * f)) per person", F.profitPerPerson, K(1.5e6 * f))]
        case ("financier", 0): return [m("f1a", "Own a holding company", b(F.has("hold")).0, 1), m("f1b", "Investments worth \(ms(5e6))", F.portfolio, K(5e6)), m("f1c", "Own a bank, insurer or fund", b(F.has("bank") || F.has("insco") || F.has("fund")).0, 1)]
        case ("financier", 1): return [m("f2a", "Own a bank", b(F.has("bank")).0, 1), m("f2b", "Finance a purchase through your own bank", a["bankfin"].double, 1), m("f2c", "A listed holding company", b(F.listedHold).0, 1), m("f2d", "Investments worth \(ms(100e6))", F.portfolio, K(100e6))]
        case ("financier", _): return [m("f3a", "\(f > 1 ? Int(3 * f) : 1)% of all bank deposits in your country", 0, f > 1 ? 3 * f : 1), m("f3b", "Net worth of \(ms(2e9 * f))", F.nw, K(2e9 * f)), m("f3c", "Stakes in \(Int(5 * f)) startups", F.stakes, 5 * f)]
        case ("global", 0): return [m("g1a", "Companies in two countries", F.countries, 2), m("g1b", "A franchise or branch abroad", b(F.franchAbroad).0, 1), m("g1c", "Group sales of \(ms(20e6)) a year", F.rev, K(20e6))]
        case ("global", 1): return [m("g2a", "Companies in four countries", F.countries, 4), m("g2b", "30% of sales from abroad", F.abroadShare * 100, 30), m("g2c", "Top 10 by sales in your country", F.rank("cc") <= 10 ? 1 : 0, 1)]
        case ("global", _): let n = min(15, 8 + 3 * lg); return [m("g3a", "Companies in \(Int(n)) countries", F.countries, n), m("g3b", f > 1 ? "Top 10 by sales worldwide" : "Top 25 by sales worldwide", F.rank("world") <= (f > 1 ? 10 : 25) ? 1 : 0, 1), m("g3c", "Group sales of \(ms(2e9 * f)) a year", F.rev, K(2e9 * f))]
        default: return []
        }
    }

    public static func perkText(_ k: String, level t: Int) -> String {
        let l = min(2, max(0, t))
        switch k {
        case "titan": return "Group trade: your suppliers work \([5, 8, 12][l])% cheaper for your own companies."
        case "dynasty": return "Loyalty: rivals find it harder to poach your managers, and lenders trust you (\([0.2, 0.35, 0.5][l]) points lower interest)."
        case "dominator": return "Deal maker: rivals sell to you about \([5, 8, 12][l])% cheaper."
        case "champion": return "Craft: quality settles \([2, 3, 4][l]) points higher in all your companies."
        case "financier": return "Credit: you borrow \([0.3, 0.5, 0.8][l]) points cheaper."
        default: return "Global reach: setting up abroad costs \([20, 35, 50][l])% less."
        }
    }

    /// The perk level of a path you follow, after you have settled in; -1 when it does not apply. Original: `R27.perk`.
    public static func perk(_ s: GameState, _ data: GameData, _ k: String) -> Int {
        let a = state(s)
        guard a["path"].string == k, s.week >= a["settle"].int else { return -1 }
        let t = tier(s, k)
        guard t > 0 else { return 0 }
        // `check` keeps this answer in `pkAll`, so the many callers (every company's weekly quality) do not rebuild the milestones.
        let doneAll = a["pkAll"].isNull ? milestones(s, data, path: k, tier: t).allSatisfy { $0.done != nil } : a["pkAll"].bool
        return min(2, t - 1 + (doneAll ? 1 : 0))
    }
    /// Perk effects other systems read. Original: the `window.*` steps at the end of the perks section.
    public static func loanMarginCut(_ s: GameState, _ data: GameData) -> Double {
        let f = perk(s, data, "financier"), d = perk(s, data, "dynasty")
        return f >= 0 ? [0.003, 0.005, 0.008][f] : d >= 0 ? [0.002, 0.0035, 0.005][d] : 0
    }
    public static func abroadFeeFactor(_ s: GameState, _ data: GameData) -> Double { let p = perk(s, data, "global"); return p >= 0 ? 1 - [0.2, 0.35, 0.5][p] : 1 }
    /// A fee for starting abroad after the global group perk, rounded to 5000 as the original does.
    public static func abroadFee(_ v: Double, _ s: GameState, _ data: GameData) -> Double {
        let f = abroadFeeFactor(s, data)
        return f < 1 ? roundTo(v * f, step: 5000) : v
    }
    public static func qualityBonus(_ s: GameState, _ data: GameData) -> Double { let p = perk(s, data, "champion"); return p >= 0 ? [2, 3, 4][p] : 0 }
    public static func supplyCostCut(_ s: GameState, _ data: GameData) -> Double { let p = perk(s, data, "titan"); return p >= 0 ? [0.05, 0.08, 0.12][p] : 0 }
    public static func buyPriceFactor(_ s: GameState, _ data: GameData) -> Double { let p = perk(s, data, "dominator"); return p >= 0 ? [1.05, 1.08, 1.12][p] : 1 }

    // MARK: Choosing and checking

    /// Choose (or switch to) a path. Switching starts the new perk after half a year. Original: `ACT.amb27pick`.
    @discardableResult
    public static func choose(_ s: inout GameState, path k: String, data: GameData) -> Bool {
        guard path(k) != nil else { return false }
        var a = state(s)
        let switching = a["path"].isNull == false
        let had = a["hist"].array.contains { !$0["path"].string.isEmpty && $0["path"].string != "give" } || a["was"].bool
        a["path"] = .string(k); a["since"] = .number(Double(s.week))
        a["settle"] = .number(had ? Double(s.week + 26) : 0)
        _ = switching
        a["was"] = true
        var t = a["tier"]; if t[k].isNull { t[k] = 0 }; a["tier"] = t
        s.rest["amb27"] = a
        check(&s, data: data)
        return true
    }

    /// Reach milestones and complete tiers. Original: `check()`.
    public static func check(_ s: inout GameState, data: GameData) {
        var a = state(s)
        guard a["path"].isNull == false else { return }
        let k = a["path"].string, t = a["tier"][k].int
        let L = milestones(s, data, path: k, tier: t)
        let ptsBase = [10.0, 25, 60][min(2, t)] * (t > 2 ? Double(t - 1) : 1)
        for m in L where m.done == nil && m.target > 0 && m.now >= m.target {
            a = state(s)
            var d = a["done"]; d[m.id] = .number(Double(s.week)); a["done"] = d
            a["score"] = .number(a["score"].double + ptsBase)
            var h = a["hist"].array
            h.insert(.object(["w": .number(Double(s.week)), "t": .string(m.text), "path": .string(k), "pts": .number(ptsBase)]), at: 0)
            if h.count > 40 { h.removeLast(h.count - 40) }
            a["hist"] = .array(h); s.rest["amb27"] = a
            s.addMessage(kind: "info", from: "Ambition", title: "Milestone: \(m.text)", body: "\(path(k)?.name ?? k) \(roman[min(9, t)]). +\(Int(ptsBase)) legacy points.", tone: "good")
        }
        let fresh = milestones(s, data, path: k, tier: t)
        if fresh.allSatisfy({ $0.done != nil }) {
            a = state(s)
            let bonus = [50.0, 150, 400][min(2, t)] * (t > 2 ? Double(t - 1) : 1)
            a["score"] = .number(a["score"].double + bonus)
            var tr = a["tier"]; tr[k] = .number(Double(t + 1)); a["tier"] = tr
            var h = a["hist"].array
            h.insert(.object(["w": .number(Double(s.week)), "t": .string("\(path(k)?.name ?? k) \(roman[min(9, t)]) complete"), "path": .string(k), "pts": .number(bonus)]), at: 0)
            a["hist"] = .array(h); s.rest["amb27"] = a
            s.news("\(s.player.name) reaches \((path(k)?.name ?? k).lowercased()) level \(roman[min(9, t)]).", tone: "good")
            let next = milestones(s, data, path: k, tier: t + 1).map { $0.text }.joined(separator: "; ")
            s.addMessage(kind: "info", from: "Ambition", title: "\(path(k)?.name ?? k) \(roman[min(9, t)]) complete",
                         body: "+\(Int(bonus)) legacy points. \(t < 2 ? "Your perk grows: " + perkText(k, level: t + 1) : "The next level asks for three times as much.") Next: \(next).", tone: "good")
        }
        a = state(s)
        a["pkAll"] = .bool(milestones(s, data, path: k, tier: a["tier"][k].int).allSatisfy { $0.done != nil })
        s.rest["amb27"] = a
    }

    public static func weekly(_ s: inout GameState, data: GameData) {
        if s.week % 4 == 0 { check(&s, data: data) }
        let a = state(s)
        if a["path"].isNull && a["ask"].int == 0 && s.companies.contains(where: { $0.status == .open }) && s.week > 4 {
            var n = a; n["ask"] = .number(Double(s.week)); s.rest["amb27"] = n
            s.addMessage(kind: "info", from: "Ambition", title: "What do you want to build?",
                         body: "Pick an ambition: an industrial group, a family dynasty, the market leader, a hidden champion, a financier or a global group. Each rewards a different way to play and gives a perk.", tone: "n")
        }
    }
}
