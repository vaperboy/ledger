import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum Funding {

    public struct Record: Equatable { public var exits = 0, fails = 0, raised = 0.0 }
    public static func record(_ s: GameState) -> Record {
        let f = s.rest["founder"] ?? .null
        return Record(exits: f["exits"].int, fails: f["fails"].int, raised: f["raised"].double)
    }
    static func bump(_ s: inout GameState, _ key: String, _ amount: Double = 1) {
        var f = s.rest["founder"] ?? .object(["exits": 0, "fails": 0, "raised": 0])
        f[key] = .number(f[key].double + amount)
        s.rest["founder"] = f
    }

    static func personName(_ s: inout GameState, countryCode: String, data: GameData) -> String {
        let c = data.countries.resolve(countryCode, orHome: s.homeCountryCode)
        let f = c.firstNames.isEmpty ? ["Alex"] : c.firstNames, l = c.lastNames.isEmpty ? ["Berg"] : c.lastNames
        return s.random.pick(f) + " " + s.random.pick(l)
    }
    static func fundName(_ s: inout GameState, countryCode: String, data: GameData, suffix: String? = nil) -> String {
        let c = data.countries.resolve(countryCode, orHome: s.homeCountryCode)
        let l = c.lastNames.isEmpty ? ["Berg"] : c.lastNames
        return s.random.pick(l) + " " + (suffix ?? s.random.pick(["Capital", "Partners", "Equity", "Investments", "Ventures"]))
    }

    static func addHolder(_ s: inout GameState, _ i: Int, name: String, pct: Double, paid: Double, extra: [String: JSONValue] = [:]) {
        var list = s.companies[i].value("holders").array
        var h: [String: JSONValue] = ["name": .string(name), "pct": .number(pct), "in": .number(paid), "sat": 60, "w0": .number(Double(s.week))]
        for (k, v) in extra { h[k] = v }
        list.append(.object(h))
        s.companies[i].set("holders", .array(list))
    }
    static func addBoardSeats(_ s: inout GameState, _ i: Int, _ n: Int) {
        var f = s.companies[i].value("flags")
        f["boardSeat"] = .number(f["boardSeat"].double + Double(n))
        s.companies[i].set("flags", f)
    }
    public static func capitalNeed(_ co: Company, data: GameData) -> Int {
        ["energy": 5, "fin": 4, "club": 4, "rent": 3, "prod": 3, "logi": 3, "project": 2, "venue": 2, "retail": 2, "svc": 1][data.catalog[co.type]?.family ?? ""] ?? 2
    }
    public static func interest(_ s: GameState, capitalNeed ck: Int, traction tr: Double) -> Double {
        let f = record(s)
        let track = min(0.36, Double(f.exits) * 0.12) - min(0.3, Double(f.fails) * 0.06)
        let pen = Double(ck - 1) * 0.13 * (f.exits > 0 ? 0.4 : 1)
        return clamp(0.3 + track + tr * 0.45 - pen + (s.economy.demand - 1), 0.02, 0.97)
    }
    public static func interestWord(_ x: Double) -> (word: String, tone: String) {
        x >= 0.7 ? ("Strong", "pos") : x >= 0.45 ? ("Some interest", "amb") : x >= 0.25 ? ("Weak", "amb") : ("Almost none", "neg")
    }
    public static func companyInterest(_ s: GameState, companyID: Int, data: GameData) -> Double {
        guard let co = s.company(companyID) else { return 0 }
        return interest(s, capitalNeed: capitalNeed(co, data: data), traction: CompanySale.traction(co, s))
    }

    public struct FundOffer: Identifiable, Equatable {
        public var id: Int
        public var kind: String
        public var name: String
        public var amount: Double
        public var preMoney: Double
        public var pct: Double
        public var says: String
        public var countered: Bool
        public var postMoney: Double { preMoney + amount }
    }

    public static func offers(_ s: GameState, companyID: Int) -> [FundOffer] {
        (s.rest["fundOffers"]?[String(companyID)].array ?? []).enumerated().map { n, o in
            FundOffer(id: n, kind: o["k"].string, name: o["name"].string, amount: o["amt"].double, preMoney: o["pre"].double, pct: o["pct"].double, says: o["says"].string, countered: o["ctr"].bool)
        }
    }
    public static func weeksUntilPitch(_ s: GameState, companyID: Int) -> Int {
        guard let t = s.rest["fundTried"]?[String(companyID)], !t.isNull else { return 0 }
        return max(0, 4 - (s.week - t.int))
    }
    public static func canRaise(_ s: GameState, companyID: Int) -> Bool {
        guard let co = s.company(companyID) else { return false }
        return co.status.isLive && co.type == StartupModel.tradeID
    }
    public static func suggestedAmount(_ s: GameState, companyID: Int, data: GameData, context fc: FinanceContext) -> Double {
        guard let co = s.company(companyID) else { return 0 }
        let v = CompanySale.estimatedValue(s, companyID: companyID, data: data)
        return (max(fc.currency(co.countryCode, s).scaledPrice(100000), v * 0.2) / 10000).rounded() * 10000
    }

    static func writeOffers(_ s: inout GameState, _ id: Int, _ list: [JSONValue]) {
        var o = s.rest["fundOffers"] ?? .object([:])
        o[String(id)] = .array(list)
        s.rest["fundOffers"] = o
    }
    static func rawOffers(_ s: GameState, _ id: Int) -> [JSONValue] { s.rest["fundOffers"]?[String(id)].array ?? [] }

    static func makeOffers(_ s: inout GameState, countryCode: String, data: GameData, interest it: Double, amount amt: Double, preMoney pre0: Double) -> [JSONValue] {
        let k = it > 0.72 ? 3 : it > 0.48 ? 2 : it > 0.26 ? 1 : (s.random.chance(it * 2) ? 1 : 0)
        let kinds = ["angel", "fund", "ff"]
        var out: [(pct: Double, o: JSONValue)] = []
        for n in 0..<k {
            let kd = kinds[n]
            let asked = ((kd == "ff" ? amt * 0.5 : amt * s.random.range(0.8, 1.15)) / 1000).rounded() * 1000
            let pre = min(pre0, pre0 * s.random.range(0.7, 1.25) * (0.7 + it * 0.6) * (kd == "ff" ? 1.1 : 1))
            let share = kd == "fund" ? 0.4 : 0.3
            let a = min(asked, (pre * share / (1 - share) / 1000).rounded(.down) * 1000)
            if a <= 0 { continue }
            let name = kd == "fund" ? fundName(&s, countryCode: countryCode, data: data) : kd == "ff" ? "Friends and family" : personName(&s, countryCode: countryCode, data: data) + ", angel investor"
            let says = kd == "fund" ? "Contacts, advice, strict targets and a board seat" : kd == "ff" ? "Friendly, but it can get awkward if things go badly"
                : s.random.pick(["Will stay quiet", "Interferes with managers", "Wants monthly numbers"])
            let pct = a / (pre + a) * 100
            out.append((pct, .object(["k": .string(kd), "name": .string(name), "amt": .number(a), "pre": .number(pre), "cap": .number(pre0), "pct": .number(pct), "says": .string(says)])))
        }
        return out.sorted { $0.pct < $1.pct }.map { $0.o }
    }

    public enum PitchResult: Equatable { case offers(Int), none, tooSoon(weeksLeft: Int), notLimited }

    @discardableResult
    public static func pitch(_ s: inout GameState, companyID: Int, amount: Double, data: GameData, context fc: FinanceContext) -> PitchResult {
        guard canRaise(s, companyID: companyID), let i = s.companyIndex(companyID) else { return .notLimited }
        let wait = weeksUntilPitch(s, companyID: companyID)
        if wait > 0 { return .tooSoon(weeksLeft: wait) }
        var tried = s.rest["fundTried"] ?? .object([:])
        tried[String(companyID)] = .number(Double(s.week))
        s.rest["fundTried"] = tried
        let co = s.companies[i]
        let cur = fc.currency(co.countryCode, s)
        let amt = max(cur.scaledPrice(50000), jsRound(amount))
        let v = Valuation.companyValue(co, state: s, trades: data.catalog)
        let list = makeOffers(&s, countryCode: co.countryCode, data: data, interest: companyInterest(s, companyID: companyID, data: data), amount: amt, preMoney: max(amt, v))
        writeOffers(&s, companyID, list)
        return list.isEmpty ? .none : .offers(list.count)
    }

    @discardableResult
    public static func acceptOffer(_ s: inout GameState, companyID: Int, index: Int) -> Bool {
        let list = rawOffers(s, companyID)
        guard list.indices.contains(index), let i = s.companyIndex(companyID), s.companies[i].status.isLive, !s.isBranch(s.companies[i]) else { return false }
        let o = list[index], co = s.companies[i]
        let amt = o["amt"].double, pct = o["pct"].double
        let shares = CapTable.sharesForPercent(pct, total: CapTable.table(co).total)
        Payments.companyReceives(&s, companyID: companyID, amount: amt, category: nil, label: "New shares sold to \(o["name"].string)")
        CapTable.issue(&s, i, newShares: shares, to: o["name"].string, paid: amt)
        if o["k"].string == "fund" { addBoardSeats(&s, i, 1) }
        bump(&s, "raised", amt)
        writeOffers(&s, companyID, [])
        s.note("\(co.name) raised \(Int(amt)) from \(o["name"].string) for \(Int(saturating: pct.rounded()))% in new shares.", tone: "good", companyID: companyID)
        return true
    }

    public static func counterOffer(_ s: inout GameState, companyID: Int, index: Int, data: GameData) {
        var list = rawOffers(s, companyID)
        guard list.indices.contains(index), !list[index]["ctr"].bool, let co = s.company(companyID) else { return }
        list[index]["ctr"] = .number(1)
        let it = interest(s, capitalNeed: capitalNeed(co, data: data), traction: CompanySale.traction(co, s))
        if s.random.chance(0.25 + it * 0.5) {
            let pre = list[index]["cap"].isNull ? list[index]["pre"].double * 1.2 : min(list[index]["pre"].double * 1.2, list[index]["cap"].double)
            list[index]["pre"] = .number(pre)
            list[index]["pct"] = .number(list[index]["amt"].double / (pre + list[index]["amt"].double) * 100)
        } else {
            s.note("\(list[index]["name"].string) walked away.", tone: "n", companyID: companyID)
            list.remove(at: index)
        }
        writeOffers(&s, companyID, list)
    }

    public static func declineOffer(_ s: inout GameState, companyID: Int, index: Int) {
        var list = rawOffers(s, companyID)
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        writeOffers(&s, companyID, list)
    }
}
