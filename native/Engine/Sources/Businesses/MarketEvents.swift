import Foundation
import GameCore
import Countries

/// What happened out in the market, kept as a small log for the app's animations (no inbox messages): `rest["mev"]`.
/// Everything here only reads existing facts; it draws no random numbers and changes no money.
public struct MarketEvent: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case competitorLaunch, supplierPriceChange, majorContract, acquisitionOpportunity, competitorLostShare, newCountry, recognition
    }
    public var id: Int
    public var day: Int            // week * 7 + day
    public var kind: Kind
    public var title: String
    public var detail: String
    public var companyID: Int?
    public var amount: Double?
    public var tone: String        // "good", "bad" or "n"
}

public struct MarketTrend: Equatable, Sendable {
    /// Change of the trade's market price index over the last 28 days, as a fraction (0.02 = up 2 percent).
    public var priceIndexChangeThisMonth: Double
    /// Up to 30 daily values of the index, oldest first.
    public var points: [Double]
}

public enum MarketEvents {
    static let cap = 60

    static func dayKey(_ s: GameState) -> Int { s.week * 7 + s.day }

    /// Append one entry (oldest dropped beyond the cap).
    public static func log(_ s: inout GameState, _ kind: MarketEvent.Kind, title: String, detail: String, companyID: Int? = nil, amount: Double? = nil, tone: String = "n") {
        var m = s.rest["mev"] ?? .object([:])
        let id = m["next"].int + 1
        var list = m["log"].array
        var e: [String: JSONValue] = ["i": .number(Double(id)), "d": .number(Double(dayKey(s))), "k": .string(kind.rawValue), "t": .string(title), "x": .string(detail), "tone": .string(tone)]
        if let c = companyID { e["c"] = .number(Double(c)) }
        if let a = amount { e["a"] = .number(a) }
        list.append(.object(e))
        if list.count > cap { list.removeFirst(list.count - cap) }
        m["log"] = .array(list)
        m["next"] = .number(Double(id))
        s.rest["mev"] = m
    }

    /// Newest first.
    public static func events(_ s: GameState, limit: Int) -> [MarketEvent] {
        let list = s.rest["mev"]?["log"].array ?? []
        return list.suffix(max(0, limit)).reversed().compactMap { e in
            guard let k = MarketEvent.Kind(rawValue: e["k"].string) else { return nil }
            return MarketEvent(id: e["i"].int, day: e["d"].int, kind: k, title: e["t"].string, detail: e["x"].string,
                               companyID: e["c"].isNull ? nil : e["c"].int, amount: e["a"].isNull ? nil : e["a"].double, tone: e["tone"].string)
        }
    }

    /// A contract offer worth at least 5 percent of the company's yearly sales is a major contract.
    public static func noteContractOffer(_ s: inout GameState, company co: Company, customer: String, worth: Double) {
        let yearly = MarketMap.annualRevenue(co)
        guard yearly > 0, worth >= yearly * 0.05 else { return }
        log(&s, .majorContract, title: "\(customer) offers a contract", detail: "Worth \(Int((worth / yearly * 100).rounded()))% of a year's sales at \(co.name).", companyID: co.id, amount: worth, tone: "good")
    }

    // MARK: Largest payment of the day

    /// Called where customers pay a company. Keeps the largest one of the current day per company; a new day starts again.
    public static func notePayment(_ s: inout GameState, companyID: Int, amount: Double, from: String) {
        guard amount > 0 else { return }
        var m = s.rest["mev"] ?? .object([:])
        var pay = m["pay"]
        let today = dayKey(s)
        if pay["d"].isNull || pay["d"].int != today { pay = .object(["d": .number(Double(today)), "m": .object([:])]) }
        var byCo = pay["m"]
        let key = String(companyID)
        if !byCo[key].isNull, byCo[key]["a"].double >= amount { return }
        byCo[key] = .object(["a": .number(amount), "f": .string(from)])
        pay["m"] = byCo
        m["pay"] = pay
        s.rest["mev"] = m
    }

    public static func largestPayment(_ s: GameState, companyID: Int?) -> (amount: Double, from: String, companyID: Int)? {
        guard let pay = s.rest["mev"]?["pay"], !pay["d"].isNull, pay["d"].int == dayKey(s) else { return nil }
        var best: (amount: Double, from: String, companyID: Int)?
        for key in pay["m"].object.keys.sorted() {
            guard let cid = Int(key), companyID == nil || companyID == cid else { continue }
            let v = pay["m"][key]
            if best == nil || v["a"].double > best!.amount { best = (v["a"].double, v["f"].string, cid) }
        }
        return best
    }

    // MARK: Market price index trend

    /// Weekly samples of each market's price index are kept (six of them); the daily points are read off between them.
    static func record(_ s: inout GameState) {
        guard let mk = s.rest["mk"], !mk.object.isEmpty else { return }
        var m = s.rest["mev"] ?? .object([:])
        var pi = m["pi"]
        for key in mk.object.keys.sorted() where !mk[key]["pi"].isNull {
            var L = pi[key].array
            L.append(.array([.number(Double(s.week * 7)), .number(mk[key]["pi"].double)]))
            if L.count > 6 { L.removeFirst(L.count - 6) }
            pi[key] = .array(L)
        }
        m["pi"] = pi
        s.rest["mev"] = m
    }

    public static func trend(_ s: GameState, companyID: Int) -> MarketTrend {
        guard let co = s.company(companyID) else { return MarketTrend(priceIndexChangeThisMonth: 0, points: []) }
        let key = Rivals.key(co)
        let samples = (s.rest["mev"]?["pi"][key].array ?? []).map { (day: $0[0].int, v: $0[1].double) }
        let current: Double = {
            let v = s.rest["mk"]?[key]["pi"] ?? .null
            return v.isNull ? 1 : v.double
        }()
        let now = dayKey(s)
        func value(_ t: Int) -> Double {
            guard let first = samples.first, let last = samples.last else { return current }
            if t >= last.day { return last.v }
            if t <= first.day { return first.v }
            for k in 1..<samples.count where t <= samples[k].day {
                let a = samples[k - 1], b = samples[k]
                return a.v + (b.v - a.v) * Double(t - a.day) / Double(max(1, b.day - a.day))
            }
            return last.v
        }
        let pts = (0..<30).map { value(now - 29 + $0) }
        let past = value(now - 28)
        return MarketTrend(priceIndexChangeThisMonth: past > 0 ? pts[29] / past - 1 : 0, points: pts)
    }

    // MARK: Weekly sweep (facts that are easiest to see by comparing with last week)

    /// Called once at the end of the week. A first sighting is only remembered, never announced.
    public static func weekly(_ s: inout GameState, data: GameData) {
        record(&s)
        guard s.companies.contains(where: { $0.status.isLive }) else { return }
        var seen = s.rest["mev"]?["seen"] ?? .object([:])
        sweepEconomy(&s, &seen)
        sweepCountries(&s, &seen, data: data)
        sweepAnniversaries(&s)
        sweepRivals(&s, &seen, data: data)
        var m = s.rest["mev"] ?? .object([:])
        m["seen"] = seen
        s.rest["mev"] = m
    }

    static func sweepEconomy(_ s: inout GameState, _ seen: inout JSONValue) {
        let E = s.economy
        let idx: [(String, String, Double)] = [("materials", "Materials", E.materials), ("fuel", "Fuel", E.fuel), ("power", "Power", E.power), ("freight", "Freight", E.freight)]
        var eco = seen["eco"].isNull ? JSONValue.object([:]) : seen["eco"]
        for (k, label, v) in idx {
            let last = eco[k].double
            if eco[k].isNull || last <= 0 { eco[k] = .number(v); continue }
            let change = v / last - 1
            guard abs(change) >= 0.03 else { continue }
            eco[k] = .number(v)
            log(&s, .supplierPriceChange, title: "\(label) prices \(change > 0 ? "up" : "down") \(Int((abs(change) * 100).rounded()))%",
                detail: "Suppliers' \(label.lowercased()) prices moved \(change > 0 ? "up" : "down") since they were last checked.", amount: change, tone: change > 0 ? "bad" : "good")
        }
        seen["eco"] = eco
    }

    static func sweepCountries(_ s: inout GameState, _ seen: inout JSONValue, data: GameData) {
        let now = Set(s.companies.filter { $0.status.isLive }.map { $0.countryCode })
        let known: Set<String>? = seen["ctry"].isNull ? nil : Set(seen["ctry"].array.map { $0.string })
        if let known = known {
            for code in now.subtracting(known).sorted() {
                let name = data.countries[code]?.name ?? code
                let cid = s.companies.first { $0.status.isLive && $0.countryCode == code }?.id
                log(&s, .newCountry, title: "Now operating in \(name)", detail: "One of your companies has started in \(name).", companyID: cid, tone: "good")
            }
        }
        seen["ctry"] = .array(now.union(known ?? []).sorted().map { .string($0) })
    }

    /// Yearly anniversary of a hire.
    static func sweepAnniversaries(_ s: inout GameState) {
        for co in s.companies where co.status.isLive {
            for p in co.staff where p.hiredWeek > 0 && s.week > p.hiredWeek && (s.week - p.hiredWeek) % 52 == 0 {
                let years = (s.week - p.hiredWeek) / 52
                let name = s.people[p.id]?.name ?? "A team member"
                log(&s, .recognition, title: "\(name): \(years) year\(years == 1 ? "" : "s") with \(co.name)", detail: "A work anniversary worth a thank-you.", companyID: co.id, tone: "good")
            }
        }
    }

    /// Rivals newly for sale, and rivals losing a point of market share week over week (the shares the app's rival rows use).
    static func sweepRivals(_ s: inout GameState, _ seen: inout JSONValue, data: GameData) {
        var listedNow: [JSONValue] = []
        let hadSale = !seen["sale"].isNull
        for key in (s.rest["mk"]?.object.keys.sorted() ?? []) {
            guard let co = s.companies.first(where: { $0.status.isLive && Rivals.key($0) == key }) else { continue }
            for r in Rivals.rivals(s, key: key) where r.forSale {
                listedNow.append(.number(Double(r.id)))
                if hadSale, !seen["sale"].array.contains(where: { $0.int == r.id }) {
                    log(&s, .acquisitionOpportunity, title: "\(r.name) is for sale", detail: "A \((data.catalog[co.type]?.name ?? "local").lowercased()) rival has been put up for sale.", companyID: co.id, tone: "n")
                }
            }
        }
        seen["sale"] = .array(listedNow)
        var shares: [String: JSONValue] = [:]
        for m in MarketMap.markets(s, data: data) where m.kind == .local {
            guard let cid = m.companyIDs.first else { continue }
            for p in MarketMap.truth(s, m, data: data).players {
                guard let rid = p.rivalID else { continue }
                shares[String(rid)] = .number(p.share)
                let before = seen["share"][String(rid)]
                if !before.isNull, before.double - p.share >= 0.01 {
                    log(&s, .competitorLostShare, title: "\(p.name) is losing share", detail: "Down \(String(format: "%.1f", (before.double - p.share) * 100)) points of the local market in a week.", companyID: cid, amount: p.share - before.double, tone: "good")
                }
            }
        }
        seen["share"] = .object(shares)
    }
}
