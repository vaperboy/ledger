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
    public static func outsidePercent(_ co: Company) -> Double { 100 - co.ownership - HoldingStakes.heldByHoldings(co) }

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
        return co.status.isLive && co.type != "hold" && !s.isBranch(co)
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

    public struct ShareOffer: Equatable { public var pct: Int; public var primary: Double; public var secondary: Double }
    public static let sharePercents = [5, 10, 20, 30, 49]
    public static func shareOffers(_ s: GameState, companyID: Int, data: GameData) -> [ShareOffer] {
        let v = max(0, CompanySale.estimatedValue(s, companyID: companyID, data: data))
        let own = s.company(companyID)?.ownership ?? 100
        return sharePercents.map { p in ShareOffer(pct: p, primary: jsRound(v * Double(p) / Double(100 - p) * 0.9), secondary: jsRound(v * Double(p) / 100 * 0.85 * own / 100)) }
    }
    public enum ShareResult: Equatable { case ok(Double), notLimited, tooMuch, blocked }

    @discardableResult
    public static func sellShares(_ s: inout GameState, companyID: Int, pct: Double, mode: String, data: GameData, context fc: FinanceContext) -> ShareResult {
        guard let i = s.companyIndex(companyID), s.companies[i].status.isLive else { return .notLimited }
        let co = s.companies[i]
        if s.isBranch(co) { return .blocked }
        let t = CapTable.table(co)
        let newPct = mode == "primary" ? t.youPct * (100 - pct) / 100 : t.youPct * (1 - pct / 100)
        if newPct < 1 { return .tooMuch }
        if mode == "primary" && Shareholders.isBlocked(s, companyID: companyID) { return .blocked }
        let v = max(1, Valuation.companyValue(co, state: s, trades: data.catalog))
        let inv = personName(&s, countryCode: co.countryCode, data: data)
        let cur = fc.currency(co.countryCode, s)
        if mode == "primary" {
            let amt = jsRound(v * pct / (100 - pct) * 0.9)
            let shares = CapTable.sharesForPercent(pct, total: t.total)
            Payments.companyReceives(&s, companyID: companyID, amount: amt, category: nil, label: "New shares sold to \(inv)")
            CapTable.issue(&s, i, newShares: shares, to: inv, paid: amt)
            s.note("Sold \(Int(pct))% of \(co.name) to \(inv) for \(cur.display(amt)) (\(shares) new shares).", tone: "good", companyID: companyID)
            return .ok(amt)
        }
        let shares = Int(saturating: (Double(t.you) * pct / 100).rounded())
        let amt = jsRound(v * Double(shares) / Double(t.total) * 0.85)
        let moved = CapTable.sellFromYou(&s, i, shares: shares, to: inv, paid: amt)
        Payments.ownerReceivesSale(&s, from: co, amount: amt, gain: amt * 0.7, label: "Sold \(Int(pct))% of your stake in \(co.name)")
        if Double(moved) / Double(t.total) * 100 >= 20 { addBoardSeats(&s, i, 1) }
        s.note("Sold \(moved) shares of \(co.name) to \(inv) for \(cur.display(amt)).", tone: "good", companyID: companyID)
        return .ok(amt)
    }

    public static let listingMinimumValue = 30_000_000.0
    public static let listingFee = 1_500_000.0
    public static func holdingValue(_ s: GameState, holdingID: Int, data: GameData) -> Double {
        guard let h = s.company(holdingID) else { return 0 }
        let kids = HoldingStakes.stakeCompanies(of: holdingID, in: s).reduce(0) { $0 + max(0, Valuation.companyValue($1, state: s, trades: data.catalog)) * HoldingStakes.sharePercent(of: $1, holdingID: holdingID) / 100 }
        return kids + HoldingStakes.rivalStakesValue(h) + HoldingStartups.value(s, holdingID: holdingID) + h.cash + HoldingModel.treasuryValue(h, s)
    }
    public static func isListed(_ co: Company) -> Bool { co.type == "hold" && co.flag("listed") }
    public static func listingMinimum(_ s: GameState, _ fc: FinanceContext) -> Double { fc.homeCurrency(s).scaledPrice(listingMinimumValue) }

    public enum ListResult: Equatable { case ok, alreadyListed, tooSmall(needed: Double), notEnoughMoney(Double), notAHolding }

    @discardableResult
    public static func listHolding(_ s: inout GameState, holdingID: Int, data: GameData, context fc: FinanceContext) -> ListResult {
        guard let i = s.companyIndex(holdingID), s.companies[i].type == "hold", s.companies[i].status.isLive else { return .notAHolding }
        if s.companies[i].flag("listed") { return .alreadyListed }
        let need = listingMinimum(s, fc), fee = fc.homeCurrency(s).scaledPrice(listingFee)
        if holdingValue(s, holdingID: holdingID, data: data) < need { return .tooSmall(needed: need) }
        if Payments.liquid(s) < fee { return .notEnoughMoney(fee) }
        Payments.playerPays(&s, fee, label: "Stock exchange listing")
        s.companies[i].set("listed", 1)
        s.note("\(s.companies[i].name) is listed on the stock exchange.", tone: "good", companyID: holdingID)
        return .ok
    }

    public struct RaisePlan: Equatable {
        public var value: Double
        public var needed: Double, given: Double, amount: Double, fee: Double
        public var manager: String? = nil, managerSkill: Double? = nil
    }
    public static func raisePlan(_ s: GameState, holdingID: Int, goal: Double, mode: String, data: GameData, context fc: FinanceContext) -> RaisePlan {
        let v0 = max(fc.homeCurrency(s).scaledPrice(100000), holdingValue(s, holdingID: holdingID, data: data))
        let mg = FinanceManager.negotiator(s, holdingID: holdingID)
        let f = mode == "public" ? 0.97 : mg.map { 0.78 + 0.3 * $0.skill } ?? 0.9
        let over = mode == "public" ? 0 : mg.map { (1 - $0.skill) * 0.7 } ?? 0.1
        let q = 100 * goal / (v0 * f + goal)
        let qa = min(49, q * (1 + over))
        let amt = jsRound(qa * v0 * f / (100 - qa))
        return RaisePlan(value: v0, needed: q, given: qa, amount: amt, fee: mode == "public" ? jsRound(amt * 0.03) : 0,
                         manager: mg?.name, managerSkill: mg?.skill)
    }

    @discardableResult
    public static func raiseForHolding(_ s: inout GameState, holdingID: Int, goal: Double, mode: String, data: GameData, context fc: FinanceContext) -> Double? {
        guard goal > 0, let i = s.companyIndex(holdingID), s.companies[i].type == "hold", s.companies[i].status.isLive else { return nil }
        let m = (mode == "public" && s.companies[i].flag("listed")) ? "public" : "private"
        let r = raisePlan(s, holdingID: holdingID, goal: goal, mode: m, data: data, context: fc)
        let buyer = m == "public" ? "Shareholders on the exchange" : fundName(&s, countryCode: s.companies[i].countryCode, data: data)
        Payments.companyReceives(&s, companyID: holdingID, amount: r.amount - r.fee, category: nil, label: "New shares sold to \(buyer)")
        let issued = CapTable.sharesForPercent(r.given, total: CapTable.table(s.companies[i]).total)
        CapTable.issue(&s, i, newShares: issued, to: buyer, paid: r.amount)
        bump(&s, "raised", r.amount)
        s.note("\(s.companies[i].name) raised \(fc.currency(s.companies[i].countryCode, s).display(r.amount)) from \(buyer).", tone: "good", companyID: holdingID)
        if let who = r.manager, m == "private" {
            s.addMessage(kind: "info", from: who, title: "Money raised for \(s.companies[i].name)",
                         body: "I raised \(fc.currency(s.companies[i].countryCode, s).display(r.amount)) from \(buyer) for \(String(format: "%g", (r.given * 10).rounded() / 10))% of the holding." + (r.given > r.needed * 1.15 ? " I had to give a bit more than I hoped." : ""),
                         companyID: holdingID, tone: "good")
        }
        return r.amount
    }
}
