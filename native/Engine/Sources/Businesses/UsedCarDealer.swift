import Foundation
import GameCore
import Countries
import Finance

extension JSONValue {
    mutating func removeKey(_ k: String) {
        guard case .object(var o) = self else { return }
        o.removeValue(forKey: k)
        self = .object(o)
    }
}

/// One car or van in a used car dealer's yard, as the player sees it. The hidden condition is not here: the mechanic finds it in the
/// first week (`inspected`), and the repair bill is added to `repairs`.
public struct UsedCarStockItem: Sendable, Identifiable, Equatable {
    public var id: Int
    public var kind: String          // always "usedcar"
    public var title: String
    public var family: String
    public var purchasePrice: Double
    public var repairs: Double
    public var askingPrice: Double
    public var weeksInStock: Int
    public var inspected: Bool
}

/// The used car dealer (trade `usedcar`). Nothing arrives on its own: the player (or a manager) buys cars on the Marketplace (`Marketplace.buy`
/// puts them here), the mechanic inspects each one and repairs what is worn, and customers buy from the yard.
///
/// Stock sits on the balance sheet as inventory at cost (purchase price plus repairs); a sale books the price as revenue and that cost as cost
/// of sales. Weekly shoppers come from the ordinary demand model (reputation, marketing, season, rivals, economy); each looks at up to three
/// cars and buys the best value with a probability that falls as the asking price rises above the car's fair market value. The asking price
/// is cost plus the dealer's markup percentage (`setUsedCarMarkup`).
///
/// The dealer's stock is `stk` on the company; the markup is `ucm` (percent).
public enum UsedCarDealer {
    public static let tradeID = "usedcar"
    public static let defaultMarkup = 12.0
    /// Weekly cost of holding stock (storage, insurance, cleaning), share of its value.
    static let holding = 0.0008
    /// Weekly fall in a car's market value.
    static let depreciation = 0.003

    public static func markup(_ co: Company) -> Double { co.value("ucm").isNull ? defaultMarkup : co.value("ucm").double }

    public static func stock(_ co: Company) -> [UsedCarStockItem] {
        let m = markup(co)
        return co.value("stk").array.map { c in
            let cost = c["cost"].double + c["rep"].double
            return UsedCarStockItem(id: c["id"].int, kind: "usedcar", title: c["name"].string, family: c["fam"].string, purchasePrice: c["cost"].double, repairs: c["rep"].double,
                                    askingPrice: cost * (1 + m / 100), weeksInStock: 0, inspected: c["done"].bool)
        }
    }

    public static func stockItems(_ co: Company, week: Int) -> [UsedCarStockItem] {
        var out = stock(co)
        let list = co.value("stk").array
        for k in out.indices { out[k].weeksInStock = max(0, week - list[k]["wk"].int) }
        return out
    }

    /// Put a car bought on the Marketplace into the yard. The money leaves cash and becomes stock at cost.
    static func addStock(_ s: inout GameState, companyIndex i: Int, listing: MarketListing, hidden h: Marketplace.Hidden, price: Double) -> Bool {
        guard s.companies[i].cash >= price else { return false }
        let id = s.makeID()
        AccountingLedger.note(category: "cogs", label: "Used car bought: \(listing.title)")
        Ledger.moveRaw(&s, .company(s.companies[i].id), -price)
        s.companies[i].inventory += price
        var list = s.companies[i].value("stk").array
        list.append(.object(["id": .number(Double(id)), "name": .string(listing.title), "fam": .string(listing.family), "cost": .number(price), "rep": 0,
                             "fair": .number(h.fair), "wear": .number(h.wear), "vis": .number(h.visWear), "wk": .number(Double(s.week)), "done": .bool(false), "km": .number(Double(h.km))]))
        s.companies[i].set("stk", .array(list))
        return true
    }

    // MARK: Week

    /// How likely a shopper is to buy a car at this ratio of asking price to fair value.
    static func accept(_ ratio: Double) -> Double { 1 / (1 + exp((ratio - 1.08) / 0.07)) }

    static func week(_ s: inout GameState, _ i: Int, _ bd: Trade, _ data: GameData) -> CompanyWeek.WeekContext {
        let w = World(state: s, data: data)
        var co = s.companies[i]
        let id = co.id
        let D = DemandModel.compute(co, bd, w).customers
        let cap = CapacityModel.compute(co, bd, w).capacity
        let mech = co.value("staff").array.contains { $0["role"].string == "mech" }
        var rnd = HashedRandom("ucar:\(s.seed):\(s.week):\(id)")
        // A manager looks for cars to buy when the yard runs low.
        if co.managerID != nil, co.status == .open { managerBuys(&s, i, bd, demand: D, data: data) }
        co = s.companies[i]
        var list = co.value("stk").array
        // Inspection and repair of cars a week or more in the yard: the hidden wear shows up as a bill, which becomes part of the car's cost.
        var spent = 0.0
        for k in list.indices where !list[k]["done"].bool && s.week - list[k]["wk"].int >= 1 {
            let cost = (list[k]["fair"].double * 0.3 * max(0, list[k]["wear"].double - 0.15) + list[k]["fair"].double * 0.008) * (mech ? 0.75 : 1)
            let paid = co.cash - spent >= cost
            if paid { spent += cost; list[k]["rep"] = .number(list[k]["rep"].double + cost); list[k]["done"] = .bool(true) }
        }
        if spent > 0 {
            AccountingLedger.note(category: "cogs", label: "Repairs and preparation of cars")
            Ledger.moveRaw(&s, .company(id), -spent)
            co = s.companies[i]
            co.inventory += spent
        }
        // Shoppers.
        let m = markup(co)
        var shoppers = Int(D)
        if rnd.next() < D - Double(Int(D)) { shoppers += 1 }
        var units = 0.0, rev = 0.0, cogs = 0.0
        let room = Int(cap.rounded(.down)) + (rnd.next() < cap - cap.rounded(.down) ? 1 : 0)
        for _ in 0..<shoppers where !list.isEmpty && Int(units) < room {
            var best = -1, bestRatio = Double.infinity
            for _ in 0..<min(3, list.count) {
                let k = min(list.count - 1, Int(rnd.next() * Double(list.count)))
                let c = list[k]
                let ask = (c["cost"].double + c["rep"].double) * (1 + m / 100)
                let seen = c["fair"].double * (1 - (c["done"].bool ? 0 : 0.5 * c["wear"].double))
                let ratio = ask / max(1, seen)
                if ratio < bestRatio { bestRatio = ratio; best = k }
            }
            guard best >= 0, rnd.next() < accept(bestRatio) else { continue }
            let c = list.remove(at: best)
            let cost = c["cost"].double + c["rep"].double
            rev += cost * (1 + m / 100); cogs += cost; units += 1
        }
        // Market value of the cars still in the yard slips a little each week.
        for k in list.indices { list[k]["fair"] = .number(list[k]["fair"].double * (1 - depreciation)) }
        co.inventory = max(0, co.inventory - cogs)
        co.set("stk", .array(list))
        // Holding cost, paid with the monthly bills like other stock costs.
        let hold = co.inventory * holding
        var books = co.books
        books.add("cogs", hold)
        co.books = books
        co.addPayable("other", hold)
        s.companies[i] = co
        let util = cap > 0 ? units / cap : 0
        var ctx = CompanyWeek.WeekContext(units: units, rev: rev, cogs: cogs, D: D, cap: cap, util: util, price: units > 0 ? rev / units : 0, paidDuringWeek: 0)
        ctx.cogsIsAccounting = true
        return ctx
    }

    /// With a manager the company buys one car a week when the yard is thin: the best value in the ads (asking price against fair value),
    /// at the asking price. A manager cannot see the hidden wear and does not haggle.
    static func managerBuys(_ s: inout GameState, _ i: Int, _ bd: Trade, demand D: Double, data: GameData) {
        let co = s.companies[i]
        guard co.value("stk").array.count < max(3, Int(D * 3)) else { return }
        let cars = Marketplace.pool(s, companyID: co.id, data: data).filter { $0.h.vehicle && $0.h.equipmentID.isEmpty }
        guard let pick = cars.min(by: { $0.l.askingPrice / $0.h.fair < $1.l.askingPrice / $1.h.fair }),
              pick.l.askingPrice / pick.h.fair <= 0.98, co.cash > pick.l.askingPrice * 1.4 else { return }
        _ = Marketplace.buy(&s, listingID: pick.l.id, companyID: co.id, price: pick.l.askingPrice, data: data)
    }

    /// Set the markup on cost, in percent (the dealer's own price for used cars).
    public static func setMarkup(_ s: inout GameState, companyID: Int, percent: Double) -> Bool {
        guard let i = s.companyIndex(companyID), s.companies[i].type == tradeID, percent.isFinite, percent >= -50, percent <= 300 else { return false }
        s.companies[i].set("ucm", percent)
        return true
    }
}
