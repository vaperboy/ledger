import Foundation
import GameCore
import Countries
import Finance

/// The used car dealer's week: buying (a hired buyer or the manager), inspection and repair orders, forced sales, shoppers, reservations and the
/// yard's costs. Nothing is clamped: a stuck car just loses value and sells slowly, and a sale books what it really brought in against what the car cost.
extension UsedCarDealer {
    /// How likely a shopper is to buy a car at this ratio of asking price to what it looks worth.
    static func accept(_ ratio: Double) -> Double { 1 / (1 + exp((ratio - 1.08) / 0.07)) }

    /// A car customers can see is worn: not looked at yet, or its repair has not been done.
    static func looksWorn(_ c: JSONValue) -> Bool { !c["done"].bool || (!c["fx"].bool && c["rq"].double > 0) }

    static func week(_ s: inout GameState, _ i: Int, _ bd: Trade, _ data: GameData) -> CompanyWeek.WeekContext {
        let w = World(state: s, data: data)
        var co = s.companies[i]
        let id = co.id, week = s.week
        let D = DemandModel.compute(co, bd, w).customers
        let cap = CapacityModel.compute(co, bd, w).capacity
        var rnd = HashedRandom("ucar:\(s.seed):\(week):\(id)")
        if co.status == .open { autoBuy(&s, i, bd, demand: D, data: data) }
        co = s.companies[i]
        var list = co.value("stk").array
        var units = 0.0, rev = 0.0, cogs = 0.0, gross = 0.0
        var told: [(title: String, body: String)] = []
        let cur = w.currency(co)

        func sell(_ k: Int, at price: Double, forced: String) {
            let c = list.remove(at: k)
            let cost = c["cost"].double + c["rep"].double
            rev += price; cogs += cost; units += 1; gross += max(0, price - cost)
            logSale(&co, car: c, price: price, week: week, forced: forced)
        }
        func oldest() -> Int? {
            list.indices.filter { list[$0]["job"].isNull && list[$0]["res"].isNull }.max { week - list[$0]["wk"].int < week - list[$1]["wk"].int }
        }

        // Cars that arrived last week are looked at: the yard cleans and prepares them, and the faults (hidden until now) come out as a repair quote.
        var spent = 0.0
        for k in list.indices where !list[k]["done"].bool && week - list[k]["wk"].int >= 1 {
            let fair = list[k]["fair"].double
            let cost = prep(fair: fair)
            guard co.cash - spent >= cost else { continue }
            spent += cost
            list[k]["rep"] = .number(list[k]["rep"].double + cost)
            list[k]["done"] = .bool(true)
            let need = repairNeed(fair: fair, wear: list[k]["wear"].double)
            if need > 0 {
                list[k]["rq"] = .number(need)
                if autoRepair(co) { startJob(s, co, &list[k], data: data) }
            } else {
                list[k]["fx"] = .bool(true)
            }
        }
        if spent > 0 {
            AccountingLedger.note(category: "cogs", label: "Cleaning and preparation of cars")
            Ledger.moveRaw(&s, .company(id), -spent)
            co = s.companies[i]
            co.inventory += spent
        }

        // Repairs that are due: the garage is paid (the money must be there) and the car is fixed. A reservation is sold now, at the reserved price.
        var reservedDone: [Int] = []
        for k in list.indices where !list[k]["job"].isNull && week >= list[k]["job"]["due"].int {
            s.companies[i] = co
            var c = list[k]
            let ok = finishJob(&s, i, &c)
            co = s.companies[i]
            if ok {
                list[k] = c
                if !c["res"].isNull { reservedDone.append(c["id"].int) }
            }
        }
        for carID in reservedDone {
            if let k = list.firstIndex(where: { $0["id"].int == carID }) { sell(k, at: list[k]["res"].double, forced: "") }
        }

        // Forced sales, from real causes: the lot holds more cars than the premises have spaces for, or the account is overdrawn.
        let spaces = lotSpaces(co)
        while list.count > spaces, let k = oldest() {
            let price = jsRound(list[k]["fair"].double * (auctionShare + auctionSpread * rnd.next()))
            told.append(("\(list[k]["name"].string) sent to auction", "The lot has \(spaces) spaces and held \(list.count) cars. It went for \(cur.short(price)), under what it was worth."))
            sell(k, at: price, forced: "lot full")
        }
        if co.cash < 0, let k = oldest() {
            let price = jsRound(list[k]["fair"].double * (auctionShare + auctionSpread * rnd.next()))
            told.append(("\(list[k]["name"].string) sold to cover the overdraft", "The account was overdrawn, so the oldest car went to auction for \(cur.short(price))."))
            sell(k, at: price, forced: "overdrawn")
        }

        // Shoppers: each looks at up to three cars and takes the best value, buying with a chance that falls as the price rises over what it looks
        // worth and as the car gets old. A car at the garage cannot be driven away: the customer reserves it for when it is fixed.
        let m = markup(co)
        var shoppers = Int(D)
        if rnd.next() < D - Double(Int(D)) { shoppers += 1 }
        let room = Int(cap.rounded(.down)) + (rnd.next() < cap - cap.rounded(.down) ? 1 : 0)
        for _ in 0..<shoppers where Int(units) < room {
            let open = list.indices.filter { list[$0]["res"].isNull }
            guard !open.isEmpty else { break }
            var best = -1, bestRatio = Double.infinity
            for _ in 0..<min(3, open.count) {
                let k = open[min(open.count - 1, Int(rnd.next() * Double(open.count)))]
                let c = list[k]
                let seen = c["fair"].double * (1 - (looksWorn(c) ? 0.5 * c["wear"].double : 0))
                let ratio = ask(c, markup: m) / max(1, seen)
                if ratio < bestRatio { bestRatio = ratio; best = k }
            }
            guard best >= 0, rnd.next() < accept(bestRatio) * freshness(weeks: week - list[best]["wk"].int) else { continue }
            let price = ask(list[best], markup: m)
            if list[best]["job"].isNull { sell(best, at: price, forced: "") } else { list[best]["res"] = .number(price) }
        }

        // Every car loses value, a stuck one faster, and costs its holding (storage, insurance, cleaning).
        var hold = 0.0
        for k in list.indices {
            let age = week - list[k]["wk"].int
            list[k]["fair"] = .number(list[k]["fair"].double * (1 - depreciation - (age >= staleAfter ? staleDepreciation : 0)))
            let h = (list[k]["cost"].double + list[k]["rep"].double) * holding
            list[k]["hold"] = .number(list[k]["hold"].double + h)
            hold += h
        }
        co.inventory = max(0, co.inventory - cogs)
        co.set("stk", .array(list))
        var books = co.books
        books.add("cogs", hold)
        co.books = books
        co.addPayable("other", hold)
        co.set("ucg", .number(gross))
        s.companies[i] = co
        for t in told { s.addMessage(from: co.name, title: t.title, body: t.body, companyID: id, tone: "bad") }
        maybeOffer(&s, i, rnd: &rnd, data: data)
        let util = cap > 0 ? units / cap : 0
        var ctx = CompanyWeek.WeekContext(units: units, rev: rev, cogs: cogs, D: D, cap: cap, util: util, price: units > 0 ? rev / units : 0, paidDuringWeek: 0)
        ctx.cogsIsAccounting = true
        return ctx
    }
}
