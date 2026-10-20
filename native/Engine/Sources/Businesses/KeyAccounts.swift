import Foundation
import GameCore
import Countries
import Finance

/// Business customers (key accounts): a few bigger buyers who place regular orders, get to know you, expect better terms and
/// leave if you let them down. Originals: `acctOk`, `acctMax`, `acctVol`, `acctRev`, `acctWeek`, `acctOffer`, `ACTS.acct`,
/// `acctMeet`, `acctDrop` (engine/company/key_accounts.js) and `acctPm`, the discount a key account gets and the weekly warming
/// (features/company/small_team_and_rewards.js).
///
/// A full shop is shared: the accounts' orders are added to the walk-ins' demand and everyone gets the same share of what the
/// capacity allows (`orders`), as in the original. The day-by-day trade has no account volume: accounts are added to the week's
/// total. Each account has a trade profile (what it sells; once you know them you can buy from them: `profile`, `Profile.canBuy`).
public enum KeyAccounts {
    static let families: Set<String> = ["svc", "venue", "retail", "prod"]
    public static let discounts = [0, 5, 10, 15, 20, 30, 40]

    /// Can this company have business customers? Original: `acctOk`.
    public static func allowed(_ co: Company, _ bd: Trade) -> Bool {
        families.contains(bd.family) && bd.businessShare <= 0.8 && co.status == .open
    }

    /// How many accounts the company's name can support. Original: `acctMax`.
    public static func maximum(_ co: Company) -> Int { 1 + Int((min(4, (co.reputation - 25) / 18)).rounded(.down)) }

    public struct Account: Identifiable, Equatable {
        public var id: Int
        public var name: String
        public var share: Double       // of the private demand the account buys
        public var relationship: Double
        public var sinceWeek: Int
        public var discount: Int
        public var lastMeeting: Int?
        public var lastUnits: Double
        public var totalUnits: Double
        public var totalPaid: Double
        /// The trade it runs (a cleaner, a bakery, a web agency ...). Original: `acc39`, `a.t`.
        public var tradeID: String
    }

    /// What the account sells, and whether you know them well enough to buy from them in your supply chain.
    public struct Profile: Equatable {
        public var tradeID: String
        public var tradeName: String
        /// The supply-chain input their trade provides (`IntercompanySupply.kinds`), if any.
        public var inputName: String?
        public var canBuy: Bool
    }

    static let supplierTrades = ["cleaning", "hardware", "trucking", "courier", "bakery", "brewery", "farm", "furniture", "webdev", "mktg", "staffing"]
    static let otherTrades = ["law", "acctfirm", "engcons", "hotel", "factory", "construction", "realdev", "gym", "insco", "shipping"]

    /// The same trade for the same account every time: six in ten run a trade that supplies others, the rest anything. Original: `acc39`.
    static func tradeFor(id: Int, known: (String) -> Bool) -> String {
        var h = 7
        for u in "\(id):t".unicodeScalars { h = (h &* 31 &+ Int(u.value)) & 0x7fffffff }
        let list = (h % 10 < 6 ? supplierTrades : otherTrades).filter(known)
        return list.isEmpty ? "cleaning" : list[h % list.count]
    }

    /// Original: `relIdx(rel) >= 2` (Familiar and better).
    public static func profile(_ a: Account, data: GameData) -> Profile {
        let kind = IntercompanySupply.kinds.first { $0.suppliers.contains(a.tradeID) }
        return Profile(tradeID: a.tradeID, tradeName: data.catalog[a.tradeID]?.name ?? "Business", inputName: kind?.name, canBuy: a.relationship >= 22)
    }

    public static func accounts(_ co: Company) -> [Account] {
        co.value("accts").array.map {
            Account(id: $0["id"].int, name: $0["name"].string, share: $0["f"].double, relationship: $0["rel"].double, sinceWeek: $0["w0"].int,
                    discount: $0["disc"].int, lastMeeting: $0["meet"].isNull ? nil : $0["meet"].int, lastUnits: $0["lastU"].double,
                    totalUnits: $0["tu"].double, totalPaid: $0["tr"].double,
                    tradeID: $0["t"].isNull ? tradeFor(id: $0["id"].int, known: { _ in true }) : $0["t"].string)
        }
    }

    /// What they pay as a share of your price: the better of a small loyalty rise and the discount you give. Original: `acctPm`.
    static func priceFactor(_ a: JSONValue, costRate cr: Double) -> Double { max(max(0.2, cr * 1.015), 1 - a["disc"].double / 100) }

    /// Units an account buys from a given private demand; a discount makes them buy more. Original: `acctVol`.
    static func volume(_ a: JSONValue, privateDemand dp: Double) -> Double {
        dp * a["f"].double * (1 + a["rel"].double / 150) * (1 + a["disc"].double / 100 * 0.8)
    }

    /// `walkInUnits` is what the walk-ins get after sharing a full shop with the accounts.
    struct Orders { var demand = 0.0, units = 0.0, revenue = 0.0, walkInUnits = 0.0, perAccount: [(id: Int, units: Double, pm: Double)] = [] }

    /// The orders for the week: what the accounts want, and what the capacity left by walk-ins lets them have. Original: `acctDemand`, `acctRev`.
    static func orders(_ co: Company, _ bd: Trade, privateDemand dp: Double, capacity cap: Double, units: Double, price: Double, costRate cr: Double) -> Orders {
        let list = co.value("accts").array
        guard !list.isEmpty, allowed(co, bd) else { return Orders() }
        var o = Orders()
        o.demand = list.reduce(0) { $0 + volume($1, privateDemand: dp) }
        // Accounts and walk-ins want more than the shop can serve: everyone gets the same share of the capacity (acctRevCore: f = units / D).
        var f = 1.0
        o.walkInUnits = units
        if units + o.demand > cap, dp + o.demand > 0 {
            f = clamp(cap / (dp + o.demand), 0, 1)
            o.walkInUnits = min(units, f * dp)
        }
        for a in list {
            let u = jsRound(f * volume(a, privateDemand: dp) * 10) / 10
            let pm = priceFactor(a, costRate: cr)
            o.perAccount.append((a["id"].int, u, pm))
            o.units += u
            o.revenue += u * price * pm
        }
        return o
    }

    /// Remember what each account bought this week.
    static func record(_ s: inout GameState, _ i: Int, _ o: Orders, price: Double) {
        guard !o.perAccount.isEmpty else { return }
        var list = s.companies[i].value("accts").array
        for p in o.perAccount {
            guard let k = list.firstIndex(where: { $0["id"].int == p.id }) else { continue }
            list[k]["lastU"] = .number(p.units); list[k]["lastPm"] = .number(p.pm)
            list[k]["tu"] = .number(list[k]["tu"].double + p.units)
            list[k]["tr"] = .number(list[k]["tr"].double + p.units * price * p.pm)
        }
        s.companies[i].set("accts", .array(list))
    }

    // MARK: Weekly

    /// Relationships warm when you serve them and cool when you do not; unhappy accounts leave; new ones ask. Original: `acctWeek`.
    static func weekly(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) {
        let co = s.companies[i]
        guard allowed(co, bd) else { return }
        let last = co.value("lastW")
        guard last["D"].double > 0 else { return }
        var h = HashedRandom("\(s.seed):acct:\(s.week):\(co.id)")
        let fr = last["units"].double / last["D"].double
        var list = co.value("accts").array
        let proc = s.hasHeadOffice("proc")
        var left: [String] = []
        list = list.compactMap { a0 in
            var a = a0
            let rel = a["rel"].double
            if fr >= 0.1 { a["rel"] = .number(min(100, rel + 0.5 * clamp(fr / 0.6, 0.35, 1) * (1 - pow(rel / 100, 1.6)) * (proc ? 1.2 : 1))) }
            else { a["rel"] = .number(max(0, rel - 0.4)) }
            // A discount warms the relationship; full price for a long time cools it a little.
            let disc = a["disc"].double, r2 = a["rel"].double
            if disc > 0 { a["rel"] = .number(min(100, r2 + 0.05 * disc * (1 - pow(r2 / 100, 1.6)))) }
            else if r2 > 40, s.week - a["w0"].int > 26 { a["rel"] = .number(max(36, r2 - 0.15)) }
            if (fr < 0.1 && a["rel"].double < 8 && h.next() < 0.04) || (co.quality < 38 && a["rel"].double < 25 && h.next() < 0.015) {
                left.append(a["name"].string)
                return nil
            }
            return a
        }
        s.companies[i].set("accts", .array(list))
        for n in left { s.note("\(n) took its business elsewhere from \(co.name).", tone: "bad", companyID: co.id) }
        if s.week % 4 == 0, list.count < maximum(co), co.awareness >= 8 || co.reputation >= 50, h.next() < 0.16 + co.awareness / 400 {
            offer(&s, i, &h, data: data)
        }
    }

    /// A bigger business asks to buy regularly. A manager signs it; otherwise it waits in the inbox. Original: `acctOffer`.
    static func offer(_ s: inout GameState, _ i: Int, _ h: inout HashedRandom, data: GameData) {
        let co = s.companies[i]
        let share = jsRound((0.08 + 0.2 * h.next()) * 100) / 100
        let country = data.countries[co.countryCode] ?? data.countries.countries[0]
        var r = DeterministicRandom(seed: Int(h.next() * 1_000_000_000))
        let name = CompanySetup.generateName(country: country, family: "svc", &r)
        let id = s.makeID()
        let acct: JSONValue = .object(["id": .number(Double(id)), "name": .string(name), "f": .number(share), "rel": 0, "w0": .number(Double(s.week)), "disc": 0,
                                       "t": .string(tradeFor(id: id, known: { data.catalog[$0] != nil && data.countries[co.countryCode].map { _ in true } ?? true }))])
        if let mid = co.managerID, let mgr = s.people[mid] {
            var list = co.value("accts").array; list.append(acct); s.companies[i].set("accts", .array(list))
            s.note("\(mgr.name) signed \(name) as a business customer for \(co.name).", tone: "good", companyID: co.id)
            return
        }
        s.addMessage(kind: "ask", from: co.name, title: "\(name) wants to buy in bulk from \(co.name)",
                     body: "A larger business customer asks to place regular orders. They pay the normal price at first and expect better terms as you get to know each other.",
                     companyID: co.id, tone: "n", status: "open",
                     options: [.option("Take them on", "Extra orders every week"), .option("Decline")], action: "acct", data: .object(["a": acct]), expiresWeek: s.week + 3)
    }

    /// The owner answers the offer. Original: `ACTS.acct`.
    public static func answer(_ s: inout GameState, message m: Message, option: Int) {
        guard option == 0, let i = s.companyIndex(m.companyID) else { return }
        var list = s.companies[i].value("accts").array
        if list.count < maximum(s.companies[i]) + 1 { list.append(m.value("data")["a"]); s.companies[i].set("accts", .array(list)) }
    }

    // MARK: Player actions

    public enum MeetResult: Equatable { case ok, wait, cash, missing }

    /// Dinner with an account. Original: `acctMeet`.
    public static func meet(_ s: inout GameState, companyID: Int, accountID: Int, data: GameData) -> MeetResult {
        guard let i = s.companyIndex(companyID) else { return .missing }
        var list = s.companies[i].value("accts").array
        guard let k = list.firstIndex(where: { $0["id"].int == accountID }) else { return .missing }
        if !list[k]["meet"].isNull, s.week - list[k]["meet"].int < 4 { return .wait }
        let co = s.companies[i]
        let cost = World(state: s, data: data).currency(co).scaledPrice(6000)
        if s.cash < cost { return .cash }
        Payments.playerPays(&s, cost, label: "Dinner with \(list[k]["name"].string)", companyID: companyID)
        var h = HashedRandom("\(s.seed):meet:\(s.week):\(accountID)")
        let rel = list[k]["rel"].double
        list[k]["meet"] = .number(Double(s.week))
        list[k]["rel"] = .number(min(100, rel + (4 + (h.next() * 4).rounded(.down)) * (1 - pow(rel / 100, 1.6))))
        s.companies[i].set("accts", .array(list))
        return .ok
    }

    public static func drop(_ s: inout GameState, companyID: Int, accountID: Int) {
        guard let i = s.companyIndex(companyID) else { return }
        s.companies[i].set("accts", .array(s.companies[i].value("accts").array.filter { $0["id"].int != accountID }))
    }

    public static func setDiscount(_ s: inout GameState, companyID: Int, accountID: Int, percent: Int) {
        guard let i = s.companyIndex(companyID) else { return }
        var list = s.companies[i].value("accts").array
        if let k = list.firstIndex(where: { $0["id"].int == accountID }) { list[k]["disc"] = .number(Double(percent)); s.companies[i].set("accts", .array(list)) }
    }
}
