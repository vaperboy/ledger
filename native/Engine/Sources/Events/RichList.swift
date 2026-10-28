import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The rich list of the home country and the yearly business awards.
/// Original: features/world/rich_list.js (round 57) and the awards in features/player/goals_and_awards.js (round 56).
public enum RichList {
    public struct Person: Equatable, Identifiable {
        public var rank: Int
        public var name: String
        public var wealth: Double
        public var source: String
        public var isYou: Bool
        public var id: Int { rank }
    }
    public struct Standing: Equatable {
        public var rank: Int?
        public var previous: Int?
        public var best: Int?
        public var netWorth: Double
        /// Top ten, or the rows around you, or the way in.
        public var top: [Person]
        public var around: [Person]
        public var hundredth: Double
    }

    static let exponent = 0.75
    static let sources = ["shipping", "property", "retail", "oil and gas", "software", "banking", "fish farming", "hotels", "food", "media", "industry", "inheritance", "investments", "telecoms", "construction"]

    /// Wealth of number one: it grows with the size of the economy. Original: `top1`.
    static func topFortune(_ country: Country, _ currency: Currency) -> Double {
        currency.scaledPrice(120e9) * pow(max(0.5, country.populationMillions / 5.5), 0.8) * max(0.4, country.wageLevel)
    }

    /// The top 100 of a country: the same people every time for this game. Original: `people`.
    public static func people(_ s: GameState, country: Country, currency: Currency) -> [Person] {
        let w1 = topFortune(country, currency)
        var list: [Person] = []
        let first = country.firstNames.isEmpty ? ["Alex"] : country.firstNames, last = country.lastNames.isEmpty ? ["Smith"] : country.lastNames
        for i in 1...100 {
            var r = HashedRandom("\(s.seed):rich57:\(country.code):\(i)")
            let name = first[Int(r.next() * Double(first.count))] + " " + last[Int(r.next() * Double(last.count))]
            let w = w1 * pow(Double(i), -exponent) * (0.9 + r.next() * 0.2)
            let src = sources[Int(r.next() * Double(sources.count))]
            list.append(Person(rank: i, name: name, wealth: w, source: src, isYou: false))
        }
        return list
    }

    /// Your place: in the top 100, or estimated from the curve below it. Original: `rankOf`.
    public static func rank(of wealth: Double, in list: [Person], topFortune w1: Double) -> Int? {
        if let i = list.firstIndex(where: { wealth >= $0.wealth }) { return i + 1 }
        if wealth <= 0 { return nil }
        let est = pow(w1 / wealth, 1 / exponent).rounded()
        return max(101, est.isFinite ? Int(min(est, Double(1 << 40))) : 1 << 40)   // a net worth of a few cents would overflow Int
    }

    public static func standing(_ s: GameState, data: GameData, context fc: FinanceContext) -> Standing {
        let country = fc.homeCountry(s), cur = fc.homeCurrency(s)
        let nw = Valuation.netWorth(s, trades: data.catalog).total
        let list = people(s, country: country, currency: cur)
        let w1 = topFortune(country, cur)
        let r = rank(of: nw, in: list, topFortune: w1)
        let me = Person(rank: r ?? 0, name: s.player.name, wealth: nw, source: "You", isYou: true)
        var all = list
        if let r = r, r <= 100 { all.insert(me, at: r - 1) }
        all = all.enumerated().map { var p = $0.element; p.rank = $0.offset + 1; return p }
        var around: [Person] = []
        if let r = r, r > 10, r <= 100 {
            let a = max(10, r - 5)
            around = Array(all[a..<min(all.count, r + 3)])
        } else if r == nil || r! > 100 {
            around = Array(all[97..<100]) + [me]
        }
        let st = s.rest["rich57"] ?? .null
        return Standing(rank: r, previous: st["prev"].isNull ? nil : st["prev"].int, best: st["best"].isNull ? nil : st["best"].int, netWorth: nw,
                        top: Array(all.prefix(10)), around: around, hundredth: list[99].wealth)
    }

    /// Month end: remember the place, and tell the big moments. Original: 'the rich list' step.
    static func monthly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        guard GameCalendar.isMonthEnd(week: s.week) else { return }
        let st = standing(s, data: data, context: fc)
        var o = s.rest["rich57"] ?? .object([:])
        o["prev"] = o["r"].isNull ? .null : o["r"]
        o["r"] = st.rank.map { .number(Double($0)) } ?? .null
        if let r = st.rank { o["best"] = .number(Double(o["best"].isNull ? r : min(o["best"].int, r))) }
        let cur = fc.homeCurrency(s)
        if let r = st.rank, r <= 100, o["top100"].double == 0 {
            o["top100"] = .number(Double(max(1, s.week)))
            s.addMessage(from: "News", title: "You are on the rich list", body: "You are number \(r) among the richest people in \(fc.homeCountry(s).name), with \(cur.display(st.netWorth)).", tone: "good")
        }
        if let r = st.rank, r <= 10, o["top10"].double == 0 {
            o["top10"] = .number(Double(max(1, s.week)))
            s.addMessage(from: "News", title: "Top ten in \(fc.homeCountry(s).name)", body: "You are now number \(r) on the rich list.", tone: "good")
        }
        s.rest["rich57"] = o
    }
}

/// The business awards, held at every year end once you have been in business for half a year.
public enum Awards {
    public static let categories: [(id: String, name: String)] = [
        ("boty", "Business of the year"), ("emp", "Employer of the year"), ("rated", "Best rated business"),
        ("new", "Newcomer of the year"), ("grow", "Fastest growing"), ("ent", "Entrepreneur of the year")]

    public struct Result: Equatable { public var kind: String; public var won: Bool; public var company: String; public var why: String; public var other: String }
    public struct Year: Equatable { public var year: Int; public var results: [Result]; public var rank: Int?; public var netWorth: Double }

    public static func name(_ kind: String) -> String { categories.first { $0.id == kind }?.name ?? kind }

    public static func years(_ s: GameState) -> [Year] {
        (s.rest["aw56"]?["years"].array ?? []).map { y in
            Year(year: y["y"].int, results: y["res"].array.map { Result(kind: $0["k"].string, won: $0["me"].bool, company: $0["co"].string, why: $0["why"].string, other: $0["other"].string) },
                 rank: y["rank"].isNull ? nil : y["rank"].int, netWorth: y["nw"].double)
        }
    }
    public static func wonCount(_ s: GameState, kind: String? = nil) -> Int {
        (s.rest["aw56"]?["won"].array ?? []).filter { kind == nil || $0["k"].string == kind }.count
    }

    static func monthlyRevenue(_ co: Company) -> Double { co.lastWeekRevenue }

    /// Year end: decided by where you rank, your staff's mood, your reputation and your growth. Original: `judge`.
    static func yearly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        guard GameCalendar.isYearEnd(week: s.week) else { return }
        let live = s.companies.filter { $0.status == .open && $0.type != "hold" }
        guard live.contains(where: { s.week - $0.foundedWeek >= 26 }) else { return }
        let year = GameCalendar.year(week: s.week)
        var aw = s.rest["aw56"] ?? .object(["won": .array([]), "years": .array([])])
        if aw["years"].array.contains(where: { $0["y"].int == year }) { return }
        let st = RichList.standing(s, data: data, context: fc)
        let cur = fc.homeCurrency(s), country = fc.homeCountry(s)
        let nw = st.netWorth
        // Where the companies rank in the country by sales and by growth (the list of the biggest companies), not the rich list.
        let rk = CompanyRanking.yourRank(s, data: data, scope: .country, metric: .revenue)?.rank ?? 1_000_000
        let growRank = CompanyRanking.yourRank(s, data: data, scope: .country, metric: .growth)?.rank ?? 1_000_000
        func otherName() -> String {
            let f = country.firstNames.isEmpty ? ["A"] : country.firstNames, l = country.lastNames.isEmpty ? ["Rival"] : country.lastNames
            return s.random.pick(f) + " " + s.random.pick(l) + " & Co"
        }
        var res: [JSONValue] = []
        func add(_ k: String, _ co: String, _ why: String, _ p: Double) {
            res.append(.object(["k": .string(k), "me": .bool(s.random.chance(p)), "co": .string(co), "why": .string(why), "other": .string(otherName())]))
        }
        if let best = live.max(by: { $0.lastWeekRevenue < $1.lastWeekRevenue }) {
            add("boty", best.name, "one of the biggest in the country", rk <= 10 ? 0.6 : rk <= 50 ? 0.25 : rk <= 300 ? 0.05 : 0)
            if let big = live.filter({ $0.staff.count >= 15 }).max(by: { ($0.value("mood").isNull ? 60 : $0.num("mood")) < ($1.value("mood").isNull ? 60 : $1.num("mood")) }) {
                let m = big.value("mood").isNull ? 60 : big.num("mood")
                add("emp", big.name, "staff who stay and like their work", clamp((m - 62) / 40, 0, 0.6))
            }
            if let top = live.filter({ $0.lastWeekUnits > 0 && s.week - $0.foundedWeek >= 26 }).max(by: { $0.reputation < $1.reputation }) {
                add("rated", top.name, "known for good work", clamp((top.reputation - 70) / 40, 0, 0.7))
            }
            if let fresh = live.filter({ s.week - $0.foundedWeek < 60 }).max(by: { $0.lastWeekRevenue < $1.lastWeekRevenue }) {
                add("new", fresh.name, "\(cur.short(fresh.lastWeekRevenue * 52)) a year in its first year", clamp(fresh.lastWeekRevenue * 52 / cur.scaledPrice(20e6), 0, 0.5))
            }
        }
        if let best = live.max(by: { $0.lastWeekRevenue < $1.lastWeekRevenue }) {
            add("grow", best.name, "grew faster than almost anyone", growRank <= 20 ? 0.45 : growRank <= 100 ? 0.12 : 0)
        }
        let prev = aw["years"].array.last?["nw"].double ?? s.openingCash
        let g = prev > 0 ? nw / prev - 1 : 0
        if nw >= cur.scaledPrice(50e6) { add("ent", s.player.name, "net worth up \(Int((g * 100).rounded()))% this year", clamp((g - 0.3) * 0.8, 0, 0.6)) }
        var years = aw["years"].array
        years.append(.object(["y": .number(Double(year)), "res": .array(res), "rank": st.rank.map { .number(Double($0)) } ?? .null, "nw": .number(nw)]))
        if years.count > 30 { years.removeFirst() }
        aw["years"] = .array(years)
        var won = aw["won"].array
        for r in res where r["me"].bool {
            won.append(.object(["y": .number(Double(year)), "k": r["k"], "co": r["co"]]))
            s.news("\(r["co"].string) wins \(name(r["k"].string).lowercased()) at the \(year) business awards.", tone: "good")
        }
        aw["won"] = .array(won)
        s.rest["aw56"] = aw
        let n = res.filter { $0["me"].bool }.count
        s.addMessage(from: "Business awards", title: "Business awards \(year)", body: n > 0 ? "You took home \(n) \(n == 1 ? "award" : "awards")." : "No award this year. The room still knows your name.", tone: n > 0 ? "good" : "n")
    }

    /// Everything that happens once a week for trophies, awards, the rich list and company sales.
    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        CompanySale.weekly(&s, data: data, context: fc)
        RivalBids.weekly(&s, data: data, context: fc)
        yearly(&s, data: data, context: fc)
        RichList.monthly(&s, data: data, context: fc)
        Trophies.check(&s, data: data, context: fc)
    }
}
