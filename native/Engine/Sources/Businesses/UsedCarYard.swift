import Foundation
import GameCore
import Countries
import Finance
import Employees

public struct UsedCarRepairOffer: Sendable, Equatable {
    public var supplierID: Int
    public var supplierName: String
    public var isOwn: Bool
    public var price: Double
    public var weeks: Int
    public var marketPrice: Double
}

public struct UsedCarQuote: Sendable, Equatable {
    public var price: Double
    public var buyPrice: Double
    public var repairs: Double
    public var repairsKnown: Bool
    public var holdingSoFar: Double
    public var holdingAhead: Double
    public var fairValue: Double
    public var priceVsFair: Double
    public var weeklyOdds: Double
    public var expectedWeeks: Double
    public var profit: Double
    public var isProfit: Bool { profit >= 0 }
    public var verdict: String { profit >= 0 ? "Profit" : "Loss" }
}

public struct UsedCarLot: Sendable, Equatable {
    public var spaces: Int
    public var used: Int
    public var free: Int { max(0, spaces - used) }
}

public struct UsedCarBuyerRecord: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var role: String
    public var deals: Int
    public var averageDiscount: Double
    public var rating: Double
}

public struct UsedCarSale: Sendable, Equatable {
    public var title: String
    public var price: Double
    public var buyPrice: Double
    public var repairs: Double
    public var holding: Double
    public var week: Int
    public var forced: String
    public var profit: Double { price - buyPrice - repairs - holding }
}

extension UsedCarDealer {
    public static let offerAction = "ucoffer"
    public static let profitShareMultiple = 4.0
    static let buyerPerWeek = 2, managerPerWeek = 1
    static let staleDepreciation = 0.005
    static let staleOddsWeeks = 12.0
    static let bayShare = 0.25
    static let repairedWear = 0.15
    static let ownRepairFactor = 0.8
    static let partsShare = 0.35
    static let offerShare = 0.7, offerSpread = 0.1
    static let auctionShare = 0.78, auctionSpread = 0.1

    static let lotLayout: [String: (share: Double, perCar: Double)] = [
        "yard": (0.85, 22), "industrial": (0.6, 28), "warehouse": (0.7, 26), "shop": (0.5, 30), "office": (0.25, 30), "home": (0, 30),
    ]

    public static func lotSpaces(_ co: Company) -> Int {
        let prem = co.value("prem")
        let m2 = prem["m2"].double
        guard m2 > 0 else { return 0 }
        let l = lotLayout[prem["kind"].string] ?? (0.3, 30)
        return Int(saturating: (m2 * l.share / l.perCar).rounded(.down))
    }

    public static func lot(_ co: Company) -> UsedCarLot { UsedCarLot(spaces: lotSpaces(co), used: co.value("stk").array.count) }

    static func repairNeed(fair: Double, wear: Double) -> Double { fair * 0.3 * max(0, wear - 0.15) }
    static func prep(fair: Double) -> Double { fair * 0.008 }

    public static func autoRepair(_ co: Company) -> Bool { co.value("ucAuto").isNull ? true : co.value("ucAuto").bool }

    static func repairOffer(_ s: GameState, company co: Company, need: Double, data: GameData) -> UsedCarRepairOffer {
        let w = World(state: s, data: data)
        let cur = w.currency(co)
        let typical = cur.scaledPrice(4200)
        var best = UsedCarRepairOffer(supplierID: 0, supplierName: "An independent garage", isOwn: false, price: need, weeks: 1 + Int(saturating: ceil(need / (3 * typical))), marketPrice: need)
        for sup in s.companies where sup.type == "carrepair" && sup.status == .open && sup.id != co.id {
            guard let sbd = data.catalog[sup.type] else { continue }
            let jobsPerWeek = CapacityModel.compute(sup, sbd, w).capacity * bayShare
            let ticket = Pricing.ticket(sup, sbd, w)
            guard jobsPerWeek > 0, ticket > 0 else { continue }
            var queued = 0.0
            for other in s.companies {
                for c in other.value("stk").array where c["job"]["sup"].int == sup.id { queued += c["job"]["price"].double / ticket }
            }
            let price = need * ownRepairFactor
            let weeks = max(1, Int(saturating: ceil((queued + price / ticket) / jobsPerWeek)))
            if best.supplierID == 0 || weeks < best.weeks { best = UsedCarRepairOffer(supplierID: sup.id, supplierName: sup.name, isOwn: true, price: price, weeks: weeks, marketPrice: need) }
        }
        return best
    }

    public static func repairOffer(_ s: GameState, companyID: Int, carID: Int, data: GameData) -> UsedCarRepairOffer? {
        guard let co = s.company(companyID), let c = co.value("stk").array.first(where: { $0["id"].int == carID }), c["done"].bool, !c["fx"].bool, c["job"].isNull else { return nil }
        return repairOffer(s, company: co, need: c["rq"].double, data: data)
    }

    static func startJob(_ s: GameState, _ co: Company, _ c: inout JSONValue, data: GameData) {
        let o = repairOffer(s, company: co, need: c["rq"].double, data: data)
        c["job"] = .object(["due": .number(Double(s.week + o.weeks)), "sup": .number(Double(o.supplierID)), "sn": .string(o.supplierName),
                            "price": .number(o.price), "from": .number(Double(s.week))])
    }

    static func finishJob(_ s: inout GameState, _ i: Int, _ c: inout JSONValue, data: GameData) -> Bool {
        let job = c["job"], price = job["price"].double
        guard s.companies[i].cash >= price else { return false }
        let id = s.companies[i].id, dealer = s.companies[i].name
        AccountingLedger.note(category: "cogs", label: "Repairs: \(c["name"].string)")
        Ledger.moveRaw(&s, .company(id), -price)
        s.companies[i].inventory += price
        let sup = job["sup"].int
        if sup != 0, let si = s.companyIndex(sup), s.companies[si].status.isLive {
            Payments.companyReceives(&s, companyID: sup, amount: price, category: "rev", label: "Repairs for \(dealer)")
            Payments.companyPays(&s, companyID: sup, amount: price * partsShare, category: "cogs", label: "Parts for repairs")
            if s.companies[si].countryCode == s.companies[i].countryCode {
                IntercompanySupply.transferVat(&s, supplier: s.companies[si], buyerIndex: i, net: price, data: data, World(state: s, data: data), cashNow: true)
            }
        }
        c["rep"] = .number(c["rep"].double + price)
        c["fx"] = .bool(true)
        c.removeKey("job")
        let worn = c["wear"].double, fixedWear = min(worn, repairedWear)
        if worn > fixedWear {
            c["fair"] = .number(c["fair"].double * (1 + 0.3 * (worn - fixedWear) / max(0.3, 1.15 - 0.3 * worn)))
            c["wear"] = .number(fixedWear)
            c["vis"] = .number(min(c["vis"].isNull ? fixedWear : c["vis"].double, fixedWear))
        }
        return true
    }

    static func addStock(_ s: inout GameState, companyIndex i: Int, listing: MarketListing, hidden h: Marketplace.Hidden, price: Double, by: String = "me") -> Bool {
        guard s.companies[i].cash >= price, lot(s.companies[i]).free > 0 else { return false }
        let id = s.makeID()
        AccountingLedger.note(category: "cogs", label: "Used car bought: \(listing.title)")
        Ledger.moveRaw(&s, .company(s.companies[i].id), -price)
        s.companies[i].inventory += price
        var list = s.companies[i].value("stk").array
        list.append(.object(["id": .number(Double(id)), "name": .string(listing.title), "fam": .string(listing.family), "cost": .number(price), "rep": 0,
                             "fair": .number(h.fair), "wear": .number(h.wear), "vis": .number(h.visWear), "wk": .number(Double(s.week)), "done": .bool(false), "km": .number(Double(h.km))]))
        s.companies[i].set("stk", .array(list))
        recordDeal(&s.companies[i], who: by, fair: h.fair, paid: price)
        return true
    }

    static func recordDeal(_ co: inout Company, who: String, fair: Double, paid: Double) {
        var b = co.value("ucb")
        if b.isNull { b = .object([:]) }
        var r = b[who]
        if r.isNull { r = .object(["n": 0, "f": 0, "p": 0]) }
        r["n"] = .number(r["n"].double + 1); r["f"] = .number(r["f"].double + fair); r["p"] = .number(r["p"].double + paid)
        b[who] = r
        co.set("ucb", b)
    }

    struct SaleResult { var price: Double; var cost: Double; var gross: Double }
    static func logSale(_ co: inout Company, car c: JSONValue, price: Double, week: Int, forced: String) {
        var log = co.value("ucs").array
        log.append(.array([.string(c["name"].string), .number(price), .number(c["cost"].double), .number(c["rep"].double), .number(c["hold"].double), .number(Double(week)), .string(forced)]))
        co.set("ucs", .array(Array(log.suffix(40))))
    }

    static func freshness(weeks: Int) -> Double { 1 / (1 + Double(max(0, weeks - staleAfter)) / staleOddsWeeks) }

    static func rating(discount: Double) -> Double { min(100, max(0, 50 + discount * 500)) }

    public static func buyerRecords(_ s: GameState, _ co: Company) -> [UsedCarBuyerRecord] {
        var out: [UsedCarBuyerRecord] = []
        for (who, r) in co.value("ucb").object.sorted(by: { $0.key < $1.key }) {
            let n = r["n"].int, f = r["f"].double, p = r["p"].double
            guard n > 0, f > 0 else { continue }
            let d = 1 - p / f
            var name = "You", role = "you"
            if who == "mgr" { name = co.managerID.flatMap { s.people[$0]?.name } ?? "Manager"; role = "manager" }
            else if who != "me", let id = Int(who) { name = s.people[id]?.name ?? "Buyer"; role = "buyer" }
            out.append(UsedCarBuyerRecord(id: who, name: name, role: role, deals: n, averageDiscount: d, rating: rating(discount: d)))
        }
        return out
    }

    static func autoBuyer(_ s: GameState, _ co: Company, _ bd: Trade) -> (who: String, skill: Double, perWeek: Int)? {
        let records = buyerRecords(s, co)
        func blend(_ own: Double, _ who: String) -> Double {
            guard let r = records.first(where: { $0.id == who }) else { return own }
            return (own * 5 + r.rating * Double(r.deals)) / (5 + Double(r.deals))
        }
        if let b = co.staff.first(where: { $0.role == "buyer" }) {
            let own = StaffModel.skill(b, person: s.people[b.id], salesRoles: [])
            return ("\(b.id)", blend(own, "\(b.id)"), buyerPerWeek)
        }
        if co.managerID != nil {
            return ("mgr", blend(ManagerModel.quality(co, bd, people: s.people) * 100, "mgr"), managerPerWeek)
        }
        return nil
    }

    static func autoBuy(_ s: inout GameState, _ i: Int, _ bd: Trade, demand D: Double, data: GameData) {
        let co0 = s.companies[i]
        guard let me = autoBuyer(s, co0, bd) else { return }
        s.companies[i].raw.removeValue(forKey: "ucbb")
        var rnd = HashedRandom("ucbuy:\(s.seed):\(s.week):\(co0.id)")
        var bought = 0
        var lines: [String] = []
        defer {
            if !lines.isEmpty {
                let who: String = me.who == "mgr" ? (co0.managerID.flatMap { s.people[$0]?.name } ?? "Your manager") : (Int(me.who).flatMap { s.people[$0]?.name } ?? "Your buyer")
                s.addMessage(kind: "info", from: who, title: "\(who) bought \(lines.count) \(lines.count == 1 ? "car" : "cars") for the yard", body: lines.joined(separator: "\n"), companyID: co0.id, tone: "n")
            }
        }
        let pushes = 1 + Int(me.skill / 30)
        var skipped: Set<String> = []
        while bought < me.perWeek {
            let co = s.companies[i]
            guard co.status == .open, lot(co).free > 0, co.value("stk").array.count < max(3, Int(D * 3)) else { return }
            let cars = Marketplace.pool(s, companyID: co.id, data: data).filter { $0.h.vehicle && $0.h.equipmentID.isEmpty && !skipped.contains($0.l.id) }
            guard let pick = cars.min(by: { $0.l.askingPrice / $0.h.fair < $1.l.askingPrice / $1.h.fair }), pick.l.askingPrice / pick.h.fair <= 1.04 else { return }
            skipped.insert(pick.l.id)
            if pick.h.kind == 2 && rnd.next() < me.skill / 130 { continue }
            var price = pick.l.askingPrice
            if !pick.h.noTalk, Marketplace.begin(&s, listingID: pick.l.id, companyID: co.id, data: data) != nil {
                for _ in 0..<pushes {
                    let n = Marketplace.push(&s, listingID: pick.l.id, companyID: co.id, data: data)
                    price = n.price
                    if n.patienceLeft <= 0 || !n.canDiscuss || price / pick.h.fair <= 0.88 { break }
                }
            }
            guard price / pick.h.fair <= 0.98, s.companies[i].cash > price * 1.4 else { continue }
            if case .ok = Marketplace.buy(&s, listingID: pick.l.id, companyID: co.id, price: price, data: data, by: me.who, quiet: true) {
                bought += 1
                lines.append("\(pick.l.title): paid \(World(state: s, data: data).currency(s.companies[i]).display(price)), about \(Int(saturating: ((1 - price / pick.h.fair) * 100).rounded())) percent under what it is worth. Check it in the yard.")
                if me.who != "mgr" { s.companies[i].set("ucbb", s.companies[i].num("ucbb") + max(0, pick.h.fair - price)) }
            }
        }
    }

    public static func costRatio(_ co: Company) -> Double? {
        let list = co.value("stk").array
        let fair = list.reduce(0) { $0 + $1["fair"].double }
        guard !list.isEmpty, fair > 0 else { return nil }
        return list.reduce(0) { $0 + $1["cost"].double + $1["rep"].double } / fair
    }

    public static func weeklyShoppers(_ s: GameState, _ co: Company, data: GameData) -> Double {
        guard let bd = data.catalog[co.type] else { return 0 }
        return DemandModel.compute(co, bd, World(state: s, data: data)).customers
    }

    public static func weeklyOdds(_ co: Company, car c: JSONValue, price: Double, week: Int, shoppers: Double) -> Double {
        let n = co.value("stk").array.filter { $0["res"].isNull }.count
        guard n > 0, shoppers > 0 else { return 0 }
        let seen = c["fair"].double * (1 - (looksWorn(c) ? 0.5 * c["wear"].double : 0))
        let p = accept(price / max(1, seen)) * freshness(weeks: week - c["wk"].int)
        let perShopper = min(1, 3 / Double(n)) / Double(min(3, n)) * p
        return 1 - pow(1 - perShopper, shoppers)
    }

    public static func quote(_ s: GameState, companyID: Int, carID: Int, price: Double, data: GameData) -> UsedCarQuote? {
        guard let co = s.company(companyID), let c = co.value("stk").array.first(where: { $0["id"].int == carID }) else { return nil }
        let reserved = !c["res"].isNull
        let p = reserved ? c["res"].double : price
        let inspected = c["done"].bool
        let pending = !c["job"].isNull ? c["job"]["price"].double : (inspected && !c["fx"].bool && !c["skip"].bool ? c["rq"].double : 0)
        let repairs = c["rep"].double + pending
        let basis = c["cost"].double + c["rep"].double
        let odds = reserved ? 1 : weeklyOdds(co, car: c, price: p, week: s.week, shoppers: weeklyShoppers(s, co, data: data))
        let weeks = 1 / max(odds, 1.0 / 520)
        let ahead = basis * holding * weeks
        let sofar = c["hold"].double
        let fair = c["fair"].double
        return UsedCarQuote(price: p, buyPrice: c["cost"].double, repairs: repairs, repairsKnown: inspected, holdingSoFar: sofar, holdingAhead: ahead, fairValue: fair,
                            priceVsFair: fair > 0 ? p / fair : 0, weeklyOdds: odds, expectedWeeks: weeks, profit: p - c["cost"].double - repairs - sofar - ahead)
    }

    static func carIndex(_ co: Company, _ carID: Int) -> Int? { co.value("stk").array.firstIndex { $0["id"].int == carID } }

    public static func setPrice(_ s: inout GameState, companyID: Int, carID: Int, price: Double) -> Bool {
        guard let i = s.companyIndex(companyID), s.companies[i].type == tradeID, price.isFinite, price > 0, let k = carIndex(s.companies[i], carID) else { return false }
        var list = s.companies[i].value("stk").array
        list[k]["ask"] = .number(price)
        s.companies[i].set("stk", .array(list))
        return true
    }

    public static func sendToRepair(_ s: inout GameState, companyID: Int, carID: Int, data: GameData) -> Bool {
        guard let i = s.companyIndex(companyID), s.companies[i].type == tradeID, let k = carIndex(s.companies[i], carID) else { return false }
        var list = s.companies[i].value("stk").array
        guard list[k]["done"].bool, !list[k]["fx"].bool, list[k]["job"].isNull else { return false }
        list[k].removeKey("skip")
        startJob(s, s.companies[i], &list[k], data: data)
        s.companies[i].set("stk", .array(list))
        return true
    }

    public static func sellAsIs(_ s: inout GameState, companyID: Int, carID: Int) -> Bool {
        guard let i = s.companyIndex(companyID), s.companies[i].type == tradeID, let k = carIndex(s.companies[i], carID) else { return false }
        var list = s.companies[i].value("stk").array
        guard list[k]["done"].bool, !list[k]["fx"].bool, list[k]["job"].isNull else { return false }
        list[k]["skip"] = .bool(true)
        s.companies[i].set("stk", .array(list))
        return true
    }

    public static func setAutoRepair(_ s: inout GameState, companyID: Int, on: Bool) -> Bool {
        guard let i = s.companyIndex(companyID), s.companies[i].type == tradeID else { return false }
        if on { s.companies[i].raw.removeValue(forKey: "ucAuto") } else { s.companies[i].set("ucAuto", .bool(false)) }
        return true
    }

    public static func sales(_ co: Company) -> [UsedCarSale] {
        co.value("ucs").array.map { r in
            let a = r.array
            return UsedCarSale(title: a.count > 0 ? a[0].string : "", price: a.count > 1 ? a[1].double : 0, buyPrice: a.count > 2 ? a[2].double : 0, repairs: a.count > 3 ? a[3].double : 0,
                               holding: a.count > 4 ? a[4].double : 0, week: a.count > 5 ? a[5].int : 0, forced: a.count > 6 ? a[6].string : "")
        }
    }

    static func maybeOffer(_ s: inout GameState, _ i: Int, rnd: inout HashedRandom, data: GameData) {
        let co = s.companies[i]
        guard !s.inbox.contains(where: { $0.status == "open" && $0.actionID == offerAction && $0.companyID == co.id }) else { return }
        let stuck = co.value("stk").array.filter { s.week - $0["wk"].int >= staleAfter + 2 && $0["job"].isNull && $0["res"].isNull }
        guard let c = stuck.max(by: { s.week - $0["wk"].int < s.week - $1["wk"].int }), rnd.next() < 0.2 else { return }
        let price = jsRound(c["fair"].double * (offerShare + offerSpread * rnd.next()))
        let cur = World(state: s, data: data).currency(co)
        let basis = c["cost"].double + c["rep"].double
        let note = price < basis ? "That is \(cur.short(basis - price)) under what it cost you." : "That is \(cur.short(price - basis)) over what it cost you."
        s.addMessage(kind: "ask", from: "A used car wholesaler", title: "Offer for the \(c["name"].string) at \(co.name)",
                     body: "It has sat on your lot for \(s.week - c["wk"].int) weeks. They will take it today for \(cur.short(price)). \(note) Your own price is \(cur.short(ask(c, markup: markup(co)))).",
                     companyID: co.id, tone: "n", status: "open",
                     options: [.option("Accept the offer", "Sold today for \(cur.short(price)); the lot space is free again."), .option("Keep the car", "Keep trying to sell it at your price.")],
                     action: offerAction, data: .object(["car": .number(Double(c["id"].int)), "price": .number(price)]), expiresWeek: s.week + 2)
    }

    public static func answerOffer(_ s: inout GameState, message m: Message, option idx: Int) {
        guard idx == 0, let i = s.companyIndex(m.companyID), let k = carIndex(s.companies[i], m.value("data")["car"].int) else { return }
        var list = s.companies[i].value("stk").array
        let c = list[k], price = m.value("data")["price"].double
        guard list[k]["job"].isNull, list[k]["res"].isNull, price > 0 else { return }
        list.remove(at: k)
        s.companies[i].set("stk", .array(list))
        let cost = c["cost"].double + c["rep"].double
        Payments.companyReceives(&s, companyID: m.companyID, amount: price, category: "rev", label: "Sold to a wholesaler: \(c["name"].string)")
        Payments.book(&s, companyID: m.companyID, category: "cogs", amount: cost)
        s.companies[i].inventory = max(0, s.companies[i].inventory - cost)
        logSale(&s.companies[i], car: c, price: price, week: s.week, forced: "wholesaler")
    }
}
