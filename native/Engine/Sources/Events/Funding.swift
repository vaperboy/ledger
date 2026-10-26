import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Raising money for a company you own and selling shares of it: investors who buy new shares (the money goes into the company),
/// private share sales at fixed percentages, and a holding company's own listing on the exchange and share issues.
/// Originals: features/player/selling_startups_and_crisis.js (`fundPart`, `makeOffers`, `ACT.pitch`, `fundacc`, `fundctr`),
/// engine/world/deals.js (`shareOffers`, `sellShares`) and features/world/rivals_holdings_software.js (`raisePlan`, `hlist`, `hraise`).
/// Selling part of YOUR shares through the market (quiet sale or broker) is `CompanySale` with a percentage.
///
/// State: `rest["founder"]` = { exits, fails, raised } (your record as a founder), `rest["fundOffers"][companyID]` = the offers on the table,
/// `rest["fundTried"][companyID]` = the week you last pitched. A company's outside owners are `holders` = [{ name, pct, in, ... }]
/// (pct = percent of the whole company), and `flags.boardSeat` counts board seats given away; a holding has `listed` = 1 once on the exchange.
///
/// Not faithful: investors you hosted (perks) do not come sooner. Converting a sole trader to a limited company
/// to be able to sell shares is not an action here (new companies can be founded as limited).
public enum Funding {
    // MARK: Founder record

    public struct Record: Equatable { public var exits = 0, fails = 0, raised = 0.0 }
    public static func record(_ s: GameState) -> Record {
        let f = s.rest["founder"] ?? .null
        return Record(exits: f["exits"].int, fails: f["fails"].int, raised: f["raised"].double)
    }
    /// Count an exit ("exits"), a failure ("fails") or money raised ("raised", by `amount`).
    static func bump(_ s: inout GameState, _ key: String, _ amount: Double = 1) {
        var f = s.rest["founder"] ?? .object(["exits": 0, "fails": 0, "raised": 0])
        f[key] = .number(f[key].double + amount)
        s.rest["founder"] = f
    }

    // MARK: Names and small helpers

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
    /// The percent of a company that outsiders own.
    public static func outsidePercent(_ co: Company) -> Double { 100 - co.ownership }

    // MARK: How investors see you

    /// Capital hunger of a trade, 1...5. Original: `capK`.
    public static func capitalNeed(_ co: Company, data: GameData) -> Int {
        ["energy": 5, "fin": 4, "club": 4, "rent": 3, "prod": 3, "logi": 3, "project": 2, "venue": 2, "retail": 2, "svc": 1][data.catalog[co.type]?.family ?? ""] ?? 2
    }
    /// 0...1: how keen investors are. Your record as a founder, how much capital the business eats, and how it is doing. Original: `interest`.
    public static func interest(_ s: GameState, capitalNeed ck: Int, traction tr: Double) -> Double {
        let f = record(s)
        let track = min(0.36, Double(f.exits) * 0.12) - min(0.3, Double(f.fails) * 0.06)
        let pen = Double(ck - 1) * 0.13 * (f.exits > 0 ? 0.4 : 1)
        return clamp(0.3 + track + tr * 0.45 - pen + (s.economy.demand - 1), 0.02, 0.97)
    }
    /// ("Strong" | "Some interest" | "Weak" | "Almost none", tone "pos" | "amb" | "neg")
    public static func interestWord(_ x: Double) -> (word: String, tone: String) {
        x >= 0.7 ? ("Strong", "pos") : x >= 0.45 ? ("Some interest", "amb") : x >= 0.25 ? ("Weak", "amb") : ("Almost none", "neg")
    }
    public static func companyInterest(_ s: GameState, companyID: Int, data: GameData) -> Double {
        guard let co = s.company(companyID) else { return 0 }
        return interest(s, capitalNeed: capitalNeed(co, data: data), traction: CompanySale.traction(co, s))
    }

    // MARK: Raise funding: investors buy new shares, the money goes into the company

    public struct FundOffer: Identifiable, Equatable {
        public var id: Int
        public var kind: String        // angel, fund, ff (friends and family)
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
    /// Weeks until you may pitch again (0 = now).
    public static func weeksUntilPitch(_ s: GameState, companyID: Int) -> Int {
        guard let t = s.rest["fundTried"]?[String(companyID)], !t.isNull else { return 0 }
        return max(0, 4 - (s.week - t.int))
    }
    public static func canRaise(_ s: GameState, companyID: Int) -> Bool {
        guard let co = s.company(companyID) else { return false }
        return co.status.isLive && co.form == .limited && co.type != "hold"
    }
    /// The amount the original suggests asking for.
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

    /// Shared by a company and a startup you founded. Original: `makeOffers`.
    static func makeOffers(_ s: inout GameState, countryCode: String, data: GameData, interest it: Double, amount amt: Double, preMoney pre0: Double) -> [JSONValue] {
        let k = it > 0.72 ? 3 : it > 0.48 ? 2 : it > 0.26 ? 1 : (s.random.chance(it * 2) ? 1 : 0)
        let kinds = ["angel", "fund", "ff"]
        var out: [(pct: Double, o: JSONValue)] = []
        for n in 0..<k {
            let kd = kinds[n]
            let a = ((kd == "ff" ? amt * 0.5 : amt * s.random.range(0.8, 1.15)) / 1000).rounded() * 1000
            let pre = pre0 * s.random.range(0.7, 1.25) * (0.7 + it * 0.6) * (kd == "ff" ? 1.1 : 1)
            let name = kd == "fund" ? fundName(&s, countryCode: countryCode, data: data) : kd == "ff" ? "Friends and family" : personName(&s, countryCode: countryCode, data: data) + ", angel investor"
            let says = kd == "fund" ? "Contacts, advice, strict targets and a board seat" : kd == "ff" ? "Friendly, but it can get awkward if things go badly"
                : s.random.pick(["Will stay quiet", "Interferes with managers", "Wants monthly numbers"])
            let pct = a / (pre + a) * 100
            out.append((pct, .object(["k": .string(kd), "name": .string(name), "amt": .number(a), "pre": .number(pre), "pct": .number(pct), "says": .string(says)])))
        }
        return out.sorted { $0.pct < $1.pct }.map { $0.o }
    }

    public enum PitchResult: Equatable { case offers(Int), none, tooSoon(weeksLeft: Int), notLimited }

    /// Pitch to investors for `amount`. Original: `ACT.pitch`.
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
        guard list.indices.contains(index), let i = s.companyIndex(companyID), s.companies[i].status.isLive else { return false }
        let o = list[index], co = s.companies[i]
        let amt = o["amt"].double, pct = o["pct"].double
        Payments.companyReceives(&s, companyID: companyID, amount: amt, category: nil, label: "New shares sold to \(o["name"].string)")
        addHolder(&s, i, name: o["name"].string, pct: pct * co.ownership / 100, paid: amt)
        s.companies[i].ownership = jsRound(co.ownership * (1 - pct / 100) * 100) / 100
        if o["k"].string == "fund" { addBoardSeats(&s, i, 1) }
        bump(&s, "raised", amt)
        writeOffers(&s, companyID, [])
        s.note("\(co.name) raised \(Int(amt)) from \(o["name"].string) for \(Int(pct.rounded()))% in new shares.", tone: "good", companyID: companyID)
        return true
    }

    /// Ask for a higher valuation, once. They accept or walk away. Original: `ACT.fundctr`.
    public static func counterOffer(_ s: inout GameState, companyID: Int, index: Int, data: GameData) {
        var list = rawOffers(s, companyID)
        guard list.indices.contains(index), !list[index]["ctr"].bool, let co = s.company(companyID) else { return }
        list[index]["ctr"] = .number(1)
        let it = interest(s, capitalNeed: capitalNeed(co, data: data), traction: CompanySale.traction(co, s))
        if s.random.chance(0.25 + it * 0.5) {
            let pre = list[index]["pre"].double * 1.2
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

    // MARK: Private shares at a fixed percentage (the original's "Shares: company / you")

    public struct ShareOffer: Equatable { public var pct: Int; public var primary: Double; public var secondary: Double }
    public static let sharePercents = [5, 10, 20, 30, 49]
    public static func shareOffers(_ s: GameState, companyID: Int, data: GameData) -> [ShareOffer] {
        let v = max(0, CompanySale.estimatedValue(s, companyID: companyID, data: data))
        let own = s.company(companyID)?.ownership ?? 100
        return sharePercents.map { p in ShareOffer(pct: p, primary: jsRound(v * Double(p) / Double(100 - p) * 0.9), secondary: jsRound(v * Double(p) / 100 * 0.85 * own / 100)) }
    }
    public enum ShareResult: Equatable { case ok(Double), notLimited, tooMuch, blocked }

    /// mode "primary": new shares, the money goes into the company. mode "secondary": you sell part of your own shares and the cash is yours.
    /// Original: `sellShares`.
    @discardableResult
    public static func sellShares(_ s: inout GameState, companyID: Int, pct: Double, mode: String, data: GameData, context fc: FinanceContext) -> ShareResult {
        guard let i = s.companyIndex(companyID), s.companies[i].status.isLive else { return .notLimited }
        let co = s.companies[i]
        guard co.form == .limited else { return .notLimited }
        if co.ownership - pct < 1 { return .tooMuch }
        if mode == "primary" && Shareholders.isBlocked(s, companyID: companyID) { return .blocked }
        let v = max(1, Valuation.companyValue(co, state: s, trades: data.catalog))
        let inv = personName(&s, countryCode: co.countryCode, data: data)
        let cur = fc.currency(co.countryCode, s)
        if mode == "primary" {
            let amt = jsRound(v * pct / (100 - pct) * 0.9)
            Payments.companyReceives(&s, companyID: companyID, amount: amt, category: nil, label: "New shares sold to \(inv)")
            addHolder(&s, i, name: inv, pct: pct * co.ownership / 100, paid: amt)
            s.companies[i].ownership = co.ownership * (1 - pct / 100)
            s.note("Sold \(Int(pct))% of \(co.name) to \(inv) for \(cur.display(amt)) (new shares).", tone: "good", companyID: companyID)
            return .ok(amt)
        }
        let amt = jsRound(v * pct / 100 * 0.85 * co.ownership / 100)
        Payments.ownerReceivesSale(&s, from: co, amount: amt, gain: amt * 0.7, label: "Sold \(Int(pct))% of \(co.name)")
        addHolder(&s, i, name: inv, pct: pct, paid: amt)
        s.companies[i].ownership = co.ownership - pct * co.ownership / 100
        if pct >= 20 { addBoardSeats(&s, i, 1) }
        s.note("Sold \(Int(pct))% of \(co.name) to \(inv) for \(cur.display(amt)).", tone: "good", companyID: companyID)
        return .ok(amt)
    }

    // MARK: Holding companies: list on the exchange, issue shares

    public static let listingMinimumValue = 30_000_000.0
    public static let listingFee = 1_500_000.0
    /// What a holding is worth: its companies by your share, its cash and its index fund. Original: `holdValue`.
    public static func holdingValue(_ s: GameState, holdingID: Int, data: GameData) -> Double {
        guard let h = s.company(holdingID) else { return 0 }
        let kids = HoldingModel.subsidiaries(of: holdingID, in: s).reduce(0) { $0 + max(0, Valuation.companyValue($1, state: s, trades: data.catalog)) * $1.ownership / 100 }
        return kids + h.cash + HoldingModel.indexValue(h, s)
    }
    public static func isListed(_ co: Company) -> Bool { co.type == "hold" && co.flag("listed") }
    public static func listingMinimum(_ s: GameState, _ fc: FinanceContext) -> Double { fc.homeCurrency(s).scaledPrice(listingMinimumValue) }

    public enum ListResult: Equatable { case ok, alreadyListed, tooSmall(needed: Double), notEnoughMoney(Double), notAHolding }

    /// Go public: a bank takes the holding to the exchange for a fee. Original: `ACT.hlist`.
    @discardableResult
    public static func listHolding(_ s: inout GameState, holdingID: Int, data: GameData, context fc: FinanceContext) -> ListResult {
        guard let i = s.companyIndex(holdingID), s.companies[i].type == "hold", s.companies[i].status.isLive else { return .notAHolding }
        if s.companies[i].flag("listed") { return .alreadyListed }
        let need = listingMinimum(s, fc), fee = fc.homeCurrency(s).scaledPrice(listingFee)
        if holdingValue(s, holdingID: holdingID, data: data) < need { return .tooSmall(needed: need) }
        if Payments.liquid(s) < fee { return .notEnoughMoney(fee) }
        Payments.transferFromSavings(&s, need: fee)
        Payments.playerPays(&s, fee, label: "Stock exchange listing")
        s.companies[i].set("listed", 1)
        s.note("\(s.companies[i].name) is listed on the stock exchange.", tone: "good", companyID: holdingID)
        return .ok
    }

    public struct RaisePlan: Equatable {
        public var value: Double
        /// The share needed for the goal, the share you will likely give (49 at most), the money that brings, and the bank fee on the exchange.
        public var needed: Double, given: Double, amount: Double, fee: Double
        /// The office finance manager who negotiates a private raise (nil: you do) and how experienced he is (0.2...0.98).
        public var manager: String? = nil, managerSkill: Double? = nil
    }
    /// What raising `goal` for a holding would cost in shares. mode "public" (on the exchange) or "private". Original: `raisePlan`.
    public static func raisePlan(_ s: GameState, holdingID: Int, goal: Double, mode: String, data: GameData, context fc: FinanceContext) -> RaisePlan {
        let v0 = max(fc.homeCurrency(s).scaledPrice(100000), holdingValue(s, holdingID: holdingID, data: data))
        let mg = FinanceManager.negotiator(s, holdingID: holdingID)   // the finance manager who runs this holding, if any
        let f = mode == "public" ? 0.97 : mg.map { 0.78 + 0.3 * $0.skill } ?? 0.9
        let over = mode == "public" ? 0 : mg.map { (1 - $0.skill) * 0.7 } ?? 0.1
        let q = 100 * goal / (v0 * f + goal)
        let qa = min(49, q * (1 + over))
        let amt = jsRound(qa * v0 * f / (100 - qa))
        return RaisePlan(value: v0, needed: q, given: qa, amount: amt, fee: mode == "public" ? jsRound(amt * 0.03) : 0,
                         manager: mg?.name, managerSkill: mg?.skill)
    }

    /// Issue new shares in a holding; the money goes into the holding and your share shrinks. Original: `ACT.hraise`.
    @discardableResult
    public static func raiseForHolding(_ s: inout GameState, holdingID: Int, goal: Double, mode: String, data: GameData, context fc: FinanceContext) -> Double? {
        guard goal > 0, let i = s.companyIndex(holdingID), s.companies[i].type == "hold", s.companies[i].status.isLive else { return nil }
        let m = (mode == "public" && s.companies[i].flag("listed")) ? "public" : "private"
        let r = raisePlan(s, holdingID: holdingID, goal: goal, mode: m, data: data, context: fc)
        let buyer = m == "public" ? "Shareholders on the exchange" : fundName(&s, countryCode: s.companies[i].countryCode, data: data)
        Payments.companyReceives(&s, companyID: holdingID, amount: r.amount - r.fee, category: nil, label: "New shares sold to \(buyer)")
        var list = s.companies[i].value("holders").array
        for k in list.indices { list[k]["pct"] = .number(list[k]["pct"].double * (1 - r.given / 100)) }
        list.append(.object(["name": .string(buyer), "pct": .number(r.given), "in": .number(r.amount), "w0": .number(Double(s.week))]))
        s.companies[i].set("holders", .array(list))
        s.companies[i].ownership = jsRound(s.companies[i].ownership * (1 - r.given / 100) * 100) / 100
        bump(&s, "raised", r.amount)
        s.note("\(s.companies[i].name) raised \(fc.currency(s.companies[i].countryCode, s).display(r.amount)) from \(buyer).", tone: "good", companyID: holdingID)
        if let who = r.manager, m == "private" {   // the finance manager reports back
            s.addMessage(kind: "info", from: who, title: "Money raised for \(s.companies[i].name)",
                         body: "I raised \(fc.currency(s.companies[i].countryCode, s).display(r.amount)) from \(buyer) for \(String(format: "%g", (r.given * 10).rounded() / 10))% of the holding." + (r.given > r.needed * 1.15 ? " I had to give a bit more than I hoped." : ""),
                         companyID: holdingID, tone: "good")
        }
        return r.amount
    }
}
