import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Achievements: the trophy wall of firsts and milestones. Original: features/player/moments_and_trophies.js (round 28a and 56).
/// Each trophy is a test on the game state; the first week it holds, it is kept with the date and an inbox message tells you.
/// Records live in `state.rest["ach28"]` as `{ id: { w: week, t: text, old: 1 if reached before the wall existed } }`.
///
/// Not ported (they need systems the native game does not have yet): acquisitions, No. 1 in a market, country rank, gifts,
/// luxury assets, startups, private equity, franchises, chains, R&D, review counts, listed holdings, manager tenure.
public enum Trophies {
    public struct Trophy: Identifiable {
        public let id: String
        public let name: String
        public let group: String
        let test: (Facts) -> String?
    }
    public struct Entry: Identifiable, Equatable {
        public var id: String
        public var name: String
        public var group: String
        public var reachedWeek: Int?
        public var text: String
        public var before: Bool
    }
    public static let groups: [(id: String, name: String)] = [
        ("first", "Firsts"), ("money", "Money"), ("people", "People"), ("trades", "Companies and trades"), ("world", "The world"), ("legacy", "Legacy")]

    /// The numbers a trophy test can ask for, worked out once per check.
    struct Facts {
        let s: GameState
        let data: GameData
        let cur: Currency
        let netWorth: NetWorth
        let live: [Company]
        let ever: [Company]
        var nw: Double { netWorth.total }
        var jobs: Int { live.reduce(0) { $0 + $1.staff.count + ($1.managerID != nil ? 1 : 0) } }
        var managers: Int { live.filter { $0.managerID != nil }.count }
        var open: Int { live.filter { $0.type != "hold" }.count }
        var types: Int { Set(ever.map { $0.type }).count }
        var families: Int { Set(ever.compactMap { data.catalog[$0.type]?.family }).count }
        var countries: Int { Set(live.map { $0.countryCode }).count }
        var years: Double { s.companies.isEmpty ? 0 : Double(s.week - (s.companies.map { $0.foundedWeek }.min() ?? s.week)) / 52 }
        var portfolio: Double { netWorth.stocks + netWorth.crypto + netWorth.funds }
        func money(_ v: Double) -> Double { cur.scaledPrice(v) }
        func words(_ v: Double) -> String { v >= 1e9 ? "\(Int(v / 1e9)) billion" : "\(Int(v / 1e6)) million" }
    }

    static func ladder(_ pre: String, _ group: String, _ rungs: [(String, String, Double)], test: @escaping (Facts, Double) -> Bool, text: @escaping (Facts, Double) -> String) -> [Trophy] {
        rungs.map { r in Trophy(id: pre + r.0, name: r.1, group: group, test: { f in test(f, r.2) ? text(f, r.2) : nil }) }
    }

    public static let all: [Trophy] = {
        var L: [Trophy] = []
        func one(_ id: String, _ name: String, _ group: String, _ t: @escaping (Facts) -> String?) { L.append(Trophy(id: id, name: name, group: group, test: t)) }
        one("cust", "First customer", "first") { f in f.live.first { $0.lastWeekUnits > 0 || ($0.books.total["rev"] ?? 0) > 0 }.map { "\($0.name) served its first customer." } }
        one("emp", "First employee", "first") { f in f.live.first { !$0.staff.isEmpty }.map { c in "\(f.s.people[c.staff[0].id]?.name ?? "Someone") joined \(c.name)." } }
        one("profit", "First profitable month", "first") { f in f.live.first { $0.monthlyHistory.contains { $0.profit > 0 } }.map { "\($0.name) made money for a whole month." } }
        one("year", "One year in business", "first") { f in f.years >= 1 ? "A year since you started your first company." : nil }
        one("mgr", "First manager", "first") { f in f.live.first { $0.managerID != nil && f.s.people[$0.managerID!] != nil }.map { "\(f.s.people[$0.managerID!]!.name) now runs \($0.name)." } }
        one("branch", "First branch", "first") { f in
            var seen = Set<String>()
            for c in f.live where c.status == .open && c.type != "hold" { if !seen.insert(c.type).inserted { return "Your second \(f.data.catalog[c.type]?.name.lowercased() ?? "company") is open." } }
            return nil }
        one("div", "First dividend", "first") { f in f.s.stats.dividendsReceived > 0 ? "Your company paid you a share of its profit." : nil }
        one("abroad", "First company abroad", "first") { f in f.live.first { $0.countryCode != f.s.homeCountryCode }.map { "\($0.name) opened abroad." } }
        one("ten", "Ten people on the payroll", "people") { f in f.jobs >= 10 ? "Ten people now earn their living with you." : nil }
        one("hundred", "100 people work for you", "people") { f in f.jobs >= 100 ? "A hundred jobs. Families depend on you now." : nil }
        one("million", "First million", "money") { f in f.nw >= f.money(1e6) ? "Your net worth passed \(f.cur.display(f.money(1e6)))." : nil }
        one("tenm", "Net worth of 10 million", "money") { f in f.nw >= f.money(10e6) ? "Your net worth passed \(f.cur.display(f.money(10e6)))." : nil }
        one("hm", "Net worth of 100 million", "money") { f in f.nw >= f.money(100e6) ? "Your net worth passed \(f.cur.display(f.money(100e6)))." : nil }
        one("bn", "A billionaire", "money") { f in f.nw >= f.money(1e9) ? "Your net worth passed \(f.cur.display(f.money(1e9)))." : nil }
        one("bank", "Your own bank", "trades") { f in f.live.contains { $0.type == "bank" && $0.status == .open } ? "You run a bank." : nil }
        L += ladder("nw", "money", [("5m", "Net worth of 5 million", 5e6), ("50m", "Net worth of 50 million", 50e6), ("500m", "Net worth of 500 million", 500e6),
                                    ("5b", "Net worth of 5 billion", 5e9), ("10b", "Net worth of 10 billion", 1e10), ("50b", "Net worth of 50 billion", 5e10)],
                    test: { f, v in f.nw >= f.money(v) }, text: { f, v in "Your net worth passed \(f.cur.display(f.money(v)))." })
        L += ladder("dv", "money", [("1m", "Dividends of 1 million", 1e6), ("10m", "Dividends of 10 million", 1e7), ("100m", "Dividends of 100 million", 1e8), ("1b", "Dividends of 1 billion", 1e9)],
                    test: { f, v in f.s.stats.dividendsReceived >= f.money(v) }, text: { f, v in "Your companies have paid you \(f.cur.display(f.money(v))) in dividends." })
        L += ladder("tx", "money", [("1m", "A million in tax", 1e6), ("10m", "10 million in tax", 1e7), ("100m", "100 million in tax", 1e8)],
                    test: { f, v in f.s.stats.taxPaid >= f.money(v) }, text: { f, v in "You have paid \(f.cur.display(f.money(v))) in tax. Schools and roads, partly yours." })
        L += ladder("pf", "money", [("1m", "A portfolio of 1 million", 1e6), ("10m", "A portfolio of 10 million", 1e7), ("100m", "A portfolio of 100 million", 1e8)],
                    test: { f, v in f.portfolio >= f.money(v) }, text: { f, v in "Your shares, funds and coins are worth \(f.cur.display(f.money(v)))." })
        L += ladder("jb", "people", [("25", "25 people work for you", 25), ("50", "50 people work for you", 50), ("250", "250 people work for you", 250), ("500", "500 people work for you", 500),
                                     ("1k", "A thousand jobs", 1000), ("5k", "Five thousand jobs", 5000), ("10k", "Ten thousand jobs", 10000)],
                    test: { f, v in Double(f.jobs) >= v }, text: { _, v in "\(Int(v)) people earn their living with you." })
        L += ladder("mg", "people", [("3", "Three managers", 3), ("10", "Ten managers", 10), ("25", "Twenty-five managers", 25)],
                    test: { f, v in Double(f.managers) >= v }, text: { _, v in "\(Int(v)) companies are run by managers you hired." })
        L += ladder("co", "trades", [("3", "Three companies", 3), ("5", "Five companies", 5), ("10", "Ten companies", 10), ("25", "Twenty-five companies", 25), ("50", "Fifty companies", 50), ("100", "A hundred companies", 100)],
                    test: { f, v in Double(f.open) >= v }, text: { _, v in "\(Int(v)) companies open at the same time." })
        L += ladder("ty", "trades", [("5", "Five trades", 5), ("10", "Ten trades", 10), ("20", "Twenty trades", 20), ("35", "Thirty-five trades", 35)],
                    test: { f, v in Double(f.types) >= v }, text: { _, v in "You have run \(Int(v)) different kinds of business." })
        one("fam", "A bit of everything", "trades") { f in f.families >= 9 ? "You have owned a business in nine different kinds of trade." : nil }
        one("hold", "A holding company", "trades") { f in f.live.contains { $0.type == "hold" } ? "Your companies now sit under a holding." : nil }
        one("oil", "Black gold", "trades") { f in f.live.contains { $0.type == "oilgas" && $0.status == .open } ? "You produce oil and gas." : nil }
        one("club", "A football club", "trades") { f in f.live.contains { f.data.catalog[$0.type]?.family == "club" } ? "You own a football club." : nil }
        L += ladder("cc", "world", [("3", "Three countries", 3), ("5", "Five countries", 5), ("10", "Ten countries", 10), ("15", "Every country", 15)],
                    test: { f, v in Double(f.countries) >= v }, text: { _, v in "You do business in \(Int(v)) countries." })
        L += ladder("yr", "legacy", [("5", "Five years in business", 5), ("10", "Ten years in business", 10), ("25", "Twenty-five years", 25), ("50", "Half a century", 50)],
                    test: { f, v in f.years >= v }, text: { _, v in "\(Int(v)) years since you started your first company." })
        L += ladder("aw", "legacy", [("1", "An award", 1), ("5", "Five awards", 5), ("20", "Twenty awards", 20)],
                    test: { f, v in Double(Awards.wonCount(f.s)) >= v }, text: { _, v in "You have won \(Int(v)) business \(v == 1 ? "award" : "awards")." })
        one("boty", "Business of the year", "legacy") { f in Awards.wonCount(f.s, kind: "boty") >= 1 ? "One of your companies was named business of the year." : nil }
        return L
    }()

    static func record(_ s: GameState) -> JSONValue { s.rest["ach28"] ?? .object([:]) }

    /// Every trophy with whether and when you got it.
    public static func entries(_ s: GameState) -> [Entry] {
        let rec = record(s)
        return all.map { t in
            let r = rec[t.id]
            return Entry(id: t.id, name: t.name, group: t.group, reachedWeek: r.isNull ? nil : r["w"].int, text: r["t"].string, before: r["old"].bool)
        }
    }

    /// Check all trophies. What an older game already reached goes up quietly; new ones tell you in the inbox. Original: `checkAch`.
    @discardableResult
    public static func check(_ s: inout GameState, data: GameData, context fc: FinanceContext) -> [String] {
        var rec = record(s)
        let first = s.rest["ach28i"] == nil && s.week > 8
        if s.rest["ach28i"] == nil { s.rest["ach28i"] = .number(1) }
        let f = Facts(s: s, data: data, cur: fc.homeCurrency(s), netWorth: Valuation.netWorth(s, trades: data.catalog),
                      live: s.companies.filter { $0.status == .open || $0.status == .closed }, ever: s.companies.filter { $0.type != "hold" })
        var got: [String] = []
        for t in all where rec[t.id].isNull {
            guard let text = t.test(f) else { continue }
            rec[t.id] = .object(["w": .number(Double(s.week)), "t": .string(text), "old": .bool(first)])
            got.append(t.id)
        }
        if got.isEmpty { return [] }
        s.rest["ach28"] = rec
        if !first {
            for id in got {
                if let t = all.first(where: { $0.id == id }) {
                    s.addMessage(from: "Trophy wall", title: t.name, body: rec[id]["t"].string, tone: "good")
                    s.note("Trophy: \(t.name)", tone: "good")
                }
            }
        }
        return got
    }
}
