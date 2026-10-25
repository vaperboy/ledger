import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Selling day by day. Original: features/sales/daily_sales.js ("Round 10").
///
/// Each day every open company gets its customers for that day (busier on the days that business is busy),
/// serves them as far as its capacity for the day allows, and is paid for each full sale that same day.
/// The week-end close (`closeWeek`) books exactly the sales that happened on the days.
public enum DailyTrade {
    /// Share of a week's customers on each day, Monday first. Original: `SH`.
    static let shops: [Double] = [0.12, 0.12, 0.13, 0.14, 0.16, 0.19, 0.14]
    static let leisure: [Double] = [0.07, 0.08, 0.11, 0.13, 0.21, 0.25, 0.15]
    static let care: [Double] = [0.15, 0.16, 0.16, 0.17, 0.17, 0.14, 0.05]
    static let work: [Double] = [0.205, 0.205, 0.205, 0.205, 0.18, 0, 0]
    static let sixDays: [Double] = [0.18, 0.18, 0.18, 0.18, 0.17, 0.11, 0]
    static let flat: [Double] = Array(repeating: 1.0 / 7, count: 7)

    /// Units sold by weight or volume are not counted in whole sales.
    static let divisibleUnits: Set<String> = ["tonne", "litre", "barrel", "MWh", "m2-week", "member-week", "unit-week", "space-week", "kbbl"]
    static let tradingFamilies: Set<String> = ["svc", "retail", "venue", "logi", "prod"]
    /// Seats and cargo space cannot be sold twice. Original: `ROOMS`.
    static let roomTrades: Set<String> = ["hotel", "fun", "casino", "airline", "shipping"]
    static let servedFamilies: Set<String> = ["venue", "retail", "prod"]

    enum Kind { case rooms, service, goods }
    static func kind(_ bd: Trade) -> Kind {
        roomTrades.contains(bd.id) ? .rooms : (bd.family == "svc" || bd.family == "logi") ? .service : .goods
    }

    static func shape(_ bd: Trade) -> [Double] {
        switch bd.family {
        case "venue": return bd.ticket < 150 ? shops : leisure
        case "retail": return bd.hasTrait("ecom") ? flat : bd.ticket >= 100000 ? care : shops
        case "svc": return bd.id == "carclean" ? shops : bd.audience >= 0.6 ? work : care
        case "prod": return (bd.ticket < 100 && bd.audience < 0.5) ? shops : work
        case "logi": return bd.id == "taxi" ? leisure : bd.id == "courier" ? sixDays : bd.id == "airline" ? flat : work
        default: return flat
        }
    }

    /// How many of today's unserved customers come back tomorrow: nobody waits for a coffee, everybody waits for a house.
    static func keepShare(_ bd: Trade, _ sh: [Double]) -> Double {
        let t = bd.ticket
        var k: Double = t >= 20000 ? 0.99 : t >= 1500 ? 0.95 : t >= 400 ? 0.6 : 0
        if sh == work { k = max(k, 0.8) }
        return k
    }

    /// Does this company trade day by day? Original: `dailyOk`.
    public static func tradesDaily(_ co: Company, _ bd: Trade) -> Bool {
        co.status == .open && tradingFamilies.contains(bd.family) && bd.id != "salmon" && !bd.hasTrait("sub") && !divisibleUnits.contains(bd.unit)
    }

    static func weekday(week: Int, day: Int) -> Int { GameCalendar.date(week: week, dayOffset: day).weekday }

    static func binomial(_ n: Double, _ p: Double, _ r: inout DeterministicRandom) -> Double {
        if n <= 0 || p <= 0 { return 0 }
        if p >= 1 { return n }
        if n > 40 { return clamp(jsRound(n * p + r.gauss() * (n * p * (1 - p)).squareRoot()), 0, n) }
        var k = 0.0
        for _ in 0..<Int(n) where r.next() < p { k += 1 }
        return k
    }

    // MARK: The daily log (stored in the company as `dl`)

    struct Log {
        var week: Int
        var days: [String: JSONValue] = [:]
        var units: Double = 0
        var revenue: Double = 0
        var paid: Double = 0
        var queue: Double = 0           // waiting customers (carried over)
        var carry: Double = 0           // unused capacity carried over
        var capacity: Double?
        var cumulativeRoom: Double?
        var lost: Double = 0
        var soldOutDays: Double = 0
        var tradingDays: Double = 7

        init(week: Int) { self.week = week }
        init(json j: JSONValue) {
            week = j["w"].int
            days = j["days"].object
            units = j["u"].double; revenue = j["r"].double; paid = j["paid"].double
            queue = j["q"].double; carry = j["ca"].double
            capacity = j["cap"].isNull ? nil : j["cap"].double
            cumulativeRoom = j["cr"].isNull ? nil : j["cr"].double
            lost = j["lost"].double; soldOutDays = j["so"].double
            tradingDays = j["wd"].isNull ? 7 : j["wd"].double
        }
        var json: JSONValue {
            var o: [String: JSONValue] = ["w": .number(Double(week)), "days": .object(days), "u": .number(units), "r": .number(revenue),
                                          "paid": .number(paid), "q": .number(queue), "ca": .number(carry), "wd": .number(tradingDays)]
            if let c = capacity { o["cap"] = .number(c) }
            if let c = cumulativeRoom { o["cr"] = .number(c) }
            if lost != 0 { o["lost"] = .number(lost) }
            if soldOutDays != 0 { o["so"] = .number(soldOutDays) }
            return .object(o)
        }
    }

    /// A fresh log for the week, carrying over unsold capacity and waiting customers. Original: `newLog`.
    static func newLog(for co: Company, week: Int) -> Log {
        let o = co.value("dl")
        var l = Log(week: week)
        l.queue = o["q"].double
        if !o["cap"].isNull {
            l.carry = clamp(o["cap"].double + o["ca"].double - o["u"].double, 0, max(1, o["cap"].double * 0.5))
        } else {
            l.carry = o["ca"].double
        }
        return l
    }

    // MARK: A day of trade

    /// Every open company trades the day. Original: `R10DAY(d)` / `dayCore`.
    public static func runDay(_ s: inout GameState, day d: Int, data: GameData) {
        s.dayMode = true
        for i in s.companies.indices {
            let co0 = s.companies[i]
            guard let bd = data.catalog[co0.type], tradesDaily(co0, bd) else { continue }
            var log = (!co0.value("dl")["w"].isNull && co0.value("dl")["w"].int == s.week) ? Log(json: co0.value("dl")) : newLog(for: co0, week: s.week)
            if log.days[String(d)] != nil { continue }
            // Read-only view for the calculations; it is dropped before the state changes.
            let (dm, cp, price, vat, stockF, salesRoles, week, people): (DemandResult, CapacityResult, Double, Double, Double, Set<String>, Int, [Int: Person]) = {
                let w = World(state: s, data: data)
                let dm = DemandModel.compute(co0, bd, w)
                let cp = CapacityModel.compute(co0, bd, w)
                var price = Pricing.ticket(co0, bd, w)
                if bd.hasTrait("rateIdx") { price *= w.economy.freight }
                return (dm, cp, price, Vat.rate(co0, bd, w), DailyTrade.stockFactor(co0, bd, demand: dm.customers, capacity: cp.capacity, w: w),
                        w.catalog.tables.salesRoles, w.week, s.people)
            }()
            var co = co0
            let result = tradeDay(&co, bd, &log, week: week, day: d, demand: dm.customers, capacity: cp.capacity, price: price, vat: vat,
                                  stockFactor: stockF, salesRoles: salesRoles, people: people, random: &s.random)
            co.set("dl", log.json)
            s.companies[i] = co
            if result.cash != 0 { Payments.companyReceives(&s, companyID: co.id, amount: result.cash, category: nil, label: nil) }
            if result.writeOff > 0 { Payments.companyPays(&s, companyID: co.id, amount: result.writeOff, category: "loss", label: nil) }
        }
    }

    static func stockFactor(_ co: Company, _ bd: Trade, demand D: Double, capacity cap: Double, w: World) -> Double {
        guard bd.hasTrait("stock") else { return 1 }
        let base = min(D, cap)
        if base <= 0 { return 1 }
        return clamp(StockHandling.unitsAvailable(co, bd, demand: D, capacity: cap, units: base, w: w) / base, 0, 1)
    }

    /// Original: `tradeDay`. Returns units sold, the cash taken and any spoiled stock to write off.
    static func tradeDay(_ co: inout Company, _ bd: Trade, _ L: inout Log, week wk: Int, day d: Int, demand D: Double, capacity cap: Double,
                         price: Double, vat vr: Double, stockFactor: Double, salesRoles: Set<String>, people: [Int: Person],
                         random r: inout DeterministicRandom) -> (sold: Double, cash: Double, writeOff: Double) {
        let wd = weekday(week: wk, day: d)
        let sh = shape(bd)
        let s = sh[wd]
        let keep = keepShare(bd, sh)
        let kind = DailyTrade.kind(bd)
        // Goods are delivered to the shelf before trading. Original: R12DELIV.
        let writeOff = Shelf.deliver(&co, bd, weekday: wd, demand: D, ticket: price, mgrQuality: ManagerModel.quality(co, bd, people: people), random: &r)
        let shelfOn = kind == .goods && !co.value("shelf").isNull
        let lam = max(0, D * s * max(0, 1 + r.gauss() * 0.1) * (shelfOn ? 1 : stockFactor))
        L.queue = binomial(L.queue, keep, &r) + Double(r.poisson(lam))
        L.capacity = max(0, cap)
        var room: Double
        if L.capacity! <= 0 { room = 0 }
        else if kind == .goods && !servedFamilies.contains(bd.family) { room = .infinity }
        else {
            // Overtime only when an extra job still pays after time-and-a-half.
            let wpu = co.lastWages / max(1, L.capacity!)
            let overtimeOK = kind == .service && price * (1 - bd.costOfSales) > 1.5 * wpu
            let stretch: Double = overtimeOK ? 1.2 : kind == .goods ? 1.1 : 1
            let workingDays = Double(sh.filter { $0 > 0 }.count)
            L.tradingDays = workingDays == 0 ? 7 : workingDays
            L.cumulativeRoom = (L.cumulativeRoom ?? 0) + (s > 0 ? (L.capacity! * stretch + L.carry) / L.tradingDays : 0)
            room = max(0, (min(L.capacity! * stretch + L.carry - L.units, L.cumulativeRoom!) + 1e-9).rounded(.down))
        }
        var sold = max(0, min(L.queue, room))
        if shelfOn {
            let have = max(0, (co.num("shelf") + 1e-9).rounded(.down))
            if sold > have { L.lost += sold - have; L.soldOutDays += 1; sold = have }
            co.set("shelf", max(0, co.num("shelf") - sold))
        }
        L.queue -= sold
        if let cr = L.cumulativeRoom { L.cumulativeRoom = max(0, cr - sold) }
        let cash = jsRound(sold * price * (1 + vr) * (1 - bd.businessShare))
        L.days[String(d)] = .object(["u": .number(sold), "r": .number(sold * price), "wd": .number(Double(wd))])
        L.units += sold
        L.revenue += sold * price
        L.paid += cash
        attributeSales(&co, bd, units: sold, price: price, week: wk, salesRoles: salesRoles, people: people, random: &r)
        return (sold, cash, writeOff)
    }

    // MARK: Who made the sales (for commission)

    /// Salespeople by skill, and you if you sell there yourself. Original: `sellers` / `attribute`.
    static func attributeSales(_ co: inout Company, _ bd: Trade, units n: Double, price: Double, week wk: Int, salesRoles: Set<String>,
                               people: [Int: Person], random r: inout DeterministicRandom) {
        if n <= 0 { return }
        var staff = co.staff
        var weights: [(index: Int?, weight: Double)] = []
        for (i, m) in staff.enumerated() where PayPlans.sells(m, salesRoles: salesRoles) {
            weights.append((i, StaffModel.skill(m, person: people[m.id], salesRoles: salesRoles) + 10))
        }
        let sellsHere = !weights.isEmpty || bd.standardStaff.contains { salesRoles.contains($0.role) }
        if !sellsHere { return }
        if co.managerID == nil && co.ownerHours > 0 { weights.append((nil, min(1, co.ownerHours / 40) * (co.num("oskill", 40) + 10))) }
        if weights.isEmpty { return }
        let W = weights.reduce(0) { $0 + $1.weight }
        var got = Array(repeating: 0.0, count: weights.count)
        if n <= 200 {
            for _ in 0..<Int(n) {
                var x = r.next() * W
                var j = 0
                while j < weights.count - 1 {
                    x -= weights[j].weight
                    if x > 0 { j += 1 } else { break }
                }
                got[j] += 1
            }
        } else {
            var left = n
            for j in weights.indices { got[j] = (n * weights[j].weight / W).rounded(.down); left -= got[j] }
            var j = 0
            while left > 0 { got[j] += 1; j = (j + 1) % weights.count; left -= 1 }
        }
        for (j, w) in weights.enumerated() where got[j] > 0 {
            if let idx = w.index {
                var m = staff[idx]
                var ws = m.value("ws")
                if ws.isNull || ws["w"].int != wk { ws = .object(["w": .number(Double(wk)), "u": 0, "r": 0]) }
                ws["u"] = .number(ws["u"].double + got[j])
                ws["r"] = .number(ws["r"].double + got[j] * price)
                m.set("ws", ws)
                staff[idx] = m
            } else {
                var ows = co.value("ows")
                if ows.isNull || ows["w"].int != wk { ows = .object(["w": .number(Double(wk)), "u": 0, "r": 0]) }
                ows["u"] = .number(ows["u"].double + got[j])
                ows["r"] = .number(ows["r"].double + got[j] * price)
                co.set("ows", ows)
            }
        }
        co.staff = staff
    }

    // MARK: The week-end close

    public struct WeekClose {
        public var units: Double
        public var averagePrice: Double
        public var cashAlreadyTaken: Double
    }

    /// The week's books use the full sales that happened on its days. Overtime is paid; a crowded shop serves worse.
    /// Original: `R10U`.
    static func closeWeek(_ s: inout GameState, companyIndex i: Int, _ bd: Trade, demand D: Double, capacity cap: Double, price: Double, data: GameData) -> WeekClose {
        var co = s.companies[i]
        let wk = s.week - 1
        var L: Log
        if !co.value("dl")["w"].isNull && co.value("dl")["w"].int == wk { L = Log(json: co.value("dl")) }
        else {
            L = newLog(for: co, week: wk)
            // Played week by week (no days were traded): trade all seven days now.
            if !s.dayMode {
                let w = World(state: s, data: data)
                let sf = stockFactor(co, bd, demand: D, capacity: cap, w: w)
                let vat = Vat.rate(co, bd, w)
                let salesRoles = w.catalog.tables.salesRoles
                let people = s.people
                for d in 0..<7 {
                    let r = tradeDay(&co, bd, &L, week: wk, day: d, demand: D, capacity: cap, price: price, vat: vat, stockFactor: sf,
                                     salesRoles: salesRoles, people: people, random: &s.random)
                    if r.cash != 0 { s.companies[i] = co; Payments.companyReceives(&s, companyID: co.id, amount: r.cash, category: nil, label: nil); co = s.companies[i] }
                }
            }
        }
        let units = L.units
        let avgPrice = L.units > 0 ? L.revenue / L.units : price
        let paid = L.paid
        var overtime = 0.0
        var overtimePay = 0.0
        if cap > 0 && L.units > cap * 1.05 {
            overtime = jsRound(L.units - cap * 1.05)
            if kind(bd) == .service {
                let wpu = co.lastWages / cap
                if wpu > 0 { overtimePay = overtime * wpu * 1.5 }
            } else if L.units > cap * 1.2 {
                // A full shop still sells, but queues grow, service slips and staff wear out.
                co.quality = max(0, co.quality - min(6, (L.units / cap - 1.2) * 12))
                var staff = co.staff
                for k in staff.indices where s.random.next() < 0.02 * (L.units / cap - 1.2) * 5 { staff[k].happyUntilWeek = 0 }
                co.staff = staff
            }
        }
        co.set("dlast", .object(["w": .number(Double(wk)), "days": .object(L.days), "u": .number(L.units), "ot": .number(overtime), "lost": .number(L.lost), "so": .number(L.soldOutDays)]))
        co.set("dl", .object(["w": -1, "days": .object([:]), "u": .number(L.units), "r": 0, "paid": 0, "q": .number(L.queue), "ca": .number(L.carry), "cap": .number(L.capacity ?? cap)]))
        // Each seller's week of sales (for commission), reset for the new week.
        let salesRoles = data.catalog.tables.salesRoles
        var staff = co.staff
        for k in staff.indices where PayPlans.sells(staff[k], salesRoles: salesRoles) {
            let ws = staff[k].value("ws")
            let mine = (!ws.isNull && ws["w"].int == wk) ? ws : .object(["u": 0, "r": 0])
            staff[k].set("lw", .object(["w": .number(Double(s.week)), "u": .number(mine["u"].double), "r": .number(mine["r"].double)]))
            staff[k].raw["ws"] = .null
        }
        co.staff = staff
        let ow = co.value("ows")
        co.set("olw", (!ow.isNull && ow["w"].int == wk) ? .object(["u": .number(ow["u"].double), "r": .number(ow["r"].double)]) : .null)
        co.raw["ows"] = .null
        s.companies[i] = co
        if overtimePay > 0 { Payments.companyPays(&s, companyID: co.id, amount: overtimePay, category: "wages") }
        return WeekClose(units: units, averagePrice: avgPrice, cashAlreadyTaken: paid)
    }
}
