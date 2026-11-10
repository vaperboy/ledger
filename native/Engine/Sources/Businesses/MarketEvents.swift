import Foundation
import GameCore
import Countries

public struct MarketEvent: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case competitorLaunch, supplierPriceChange, majorContract, acquisitionOpportunity, competitorLostShare, newCountry, recognition
        case priceResponse
    }
    public var id: Int
    public var day: Int
    public var kind: Kind
    public var title: String
    public var detail: String
    public var companyID: Int?
    public var amount: Double?
    public var tone: String
    public var employeeID: Int? = nil
    public var consequence: String = ""
    public var acknowledged: Bool = false
}

public struct MarketTrend: Equatable, Sendable {
    public var priceIndexChangeThisMonth: Double
    public var points: [Double]
}

public enum MarketEvents {
    static let cap = 60
    static let perWeek = 3
    static let marketWide: Set<MarketEvent.Kind> = [.supplierPriceChange, .competitorLaunch, .priceResponse, .newCountry, .acquisitionOpportunity, .competitorLostShare]
    static let dedupeWeeks = 4

    static func dayKey(_ s: GameState) -> Int { s.week * 7 + s.day }

    @discardableResult
    public static func log(_ s: inout GameState, _ kind: MarketEvent.Kind, title: String, detail: String, companyID: Int? = nil, amount: Double? = nil, tone: String = "n", employeeID: Int? = nil, consequence: String = "") -> Bool {
        var m = s.rest["mev"] ?? .object([:])
        let existing = m["log"].array
        let today = dayKey(s)
        let thisWeek = existing.filter { $0["d"].int / 7 == s.week }
        if thisWeek.count >= perWeek { return false }
        if marketWide.contains(kind), thisWeek.contains(where: { MarketEvent.Kind(rawValue: $0["k"].string).map(marketWide.contains) ?? false }) { return false }
        if existing.contains(where: { today - $0["d"].int < dedupeWeeks * 7 && $0["k"].string == kind.rawValue && $0["t"].string == title && ($0["c"].isNull ? nil : $0["c"].int) == companyID && ($0["w"].isNull ? nil : $0["w"].int) == employeeID }) { return false }
        let id = m["next"].int + 1
        var list = m["log"].array
        var e: [String: JSONValue] = ["i": .number(Double(id)), "d": .number(Double(dayKey(s))), "k": .string(kind.rawValue), "t": .string(title), "x": .string(detail), "tone": .string(tone)]
        if let c = companyID { e["c"] = .number(Double(c)) }
        if let a = amount { e["a"] = .number(a) }
        if let w = employeeID { e["w"] = .number(Double(w)) }
        let cq = consequence.isEmpty && kind == .recognition && employeeID != nil ? "Thank them for a lift in mood and loyalty." : consequence
        if !cq.isEmpty { e["cq"] = .string(cq) }
        list.append(.object(e))
        if list.count > cap { list.removeFirst(list.count - cap) }
        m["log"] = .array(list)
        m["next"] = .number(Double(id))
        s.rest["mev"] = m
        return true
    }

    public static func events(_ s: GameState, limit: Int) -> [MarketEvent] {
        let list = s.rest["mev"]?["log"].array ?? []
        return list.suffix(max(0, limit)).reversed().compactMap { e in
            guard let k = MarketEvent.Kind(rawValue: e["k"].string) else { return nil }
            return MarketEvent(id: e["i"].int, day: e["d"].int, kind: k, title: e["t"].string, detail: e["x"].string,
                               companyID: e["c"].isNull ? nil : e["c"].int, amount: e["a"].isNull ? nil : e["a"].double, tone: e["tone"].string,
                               employeeID: e["w"].isNull ? nil : e["w"].int, consequence: e["cq"].string, acknowledged: e["ack"].bool)
        }
    }

    public static func noteContractOffer(_ s: inout GameState, company co: Company, customer: String, worth: Double, outcome: String? = nil) {
        let yearly = MarketMap.annualRevenue(co)
        guard yearly > 0, worth >= yearly * 0.05 else { return }
        log(&s, .majorContract, title: "\(customer) offers a contract", detail: "Worth \(Int(saturating: (worth / yearly * 100).rounded()))% of a year's sales at \(co.name).", companyID: co.id, amount: worth, tone: "good",
            consequence: outcome ?? "The offer is in your inbox: accept or decline it there.")
    }

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

    static let thanksWeeks = 13

    public static func acknowledgeRecognition(_ s: inout GameState, eventID: Int) -> String? {
        var m = s.rest["mev"] ?? .object([:])
        var list = m["log"].array
        guard let k = list.firstIndex(where: { $0["i"].int == eventID }), list[k]["k"].string == MarketEvent.Kind.recognition.rawValue, !list[k]["w"].isNull else { return "That is not a recognition event." }
        if list[k]["ack"].bool { return "You have already thanked them." }
        let pid = list[k]["w"].int
        guard let ci = s.companies.firstIndex(where: { $0.status.isLive && $0.staff.contains { $0.id == pid } }),
              let si = s.companies[ci].staff.firstIndex(where: { $0.id == pid }) else { return "They no longer work for you." }
        var st = s.companies[ci].staff
        st[si].happyUntilWeek = max(st[si].happyUntilWeek, s.week + thanksWeeks)
        s.companies[ci].staff = st
        list[k]["ack"] = .bool(true)
        m["log"] = .array(list)
        s.rest["mev"] = m
        s.note("You thanked \(s.people[pid]?.name ?? "a team member") at \(s.companies[ci].name).", tone: "good", companyID: s.companies[ci].id)
        return nil
    }

    public static func weekly(_ s: inout GameState, data: GameData) {
        record(&s)
        MarketPressure.prune(&s)
        guard s.companies.contains(where: { $0.status.isLive }) else { return }
        var seen = s.rest["mev"]?["seen"] ?? .object([:])
        sweepEconomy(&s, &seen, data: data)
        sweepCountries(&s, &seen, data: data)
        sweepAnniversaries(&s)
        sweepRivals(&s, &seen, data: data)
        var m = s.rest["mev"] ?? .object([:])
        m["seen"] = seen
        s.rest["mev"] = m
    }

    static func costChange(_ s: GameState, key: String, from old: Double, to new: Double, data: GameData) -> (company: Company, weekly: Double)? {
        guard key == "materials" || key == "fuel" else { return nil }
        var best: (company: Company, weekly: Double)?
        for co in s.companies where co.status == .open {
            guard let bd = data.catalog[co.type], co.lastWeekRevenue > 0 else { continue }
            var rate = 0.0
            if key == "materials", bd.family != "prod", bd.family != "project" { rate = bd.costOfSales * 0.3 * (new - old) / (0.7 + 0.3 * old) }
            if key == "fuel", let f = bd.trait("fuel") { rate = f * (new - old) }
            let weekly = rate * co.lastWeekRevenue
            if weekly != 0, best == nil || abs(weekly) > abs(best!.weekly) { best = (co, weekly) }
        }
        return best
    }

    static let supplierCooldown = 4

    static func sweepEconomy(_ s: inout GameState, _ seen: inout JSONValue, data: GameData) {
        let E = s.economy
        let idx: [(String, String, Double)] = [("materials", "Materials", E.materials), ("fuel", "Fuel", E.fuel), ("power", "Power", E.power), ("freight", "Freight", E.freight)]
        var eco = seen["eco"].isNull ? JSONValue.object([:]) : seen["eco"]
        var when = seen["ecoW"].isNull ? JSONValue.object([:]) : seen["ecoW"]
        var moves: [(key: String, label: String, last: Double, now: Double, change: Double)] = []
        for (k, label, v) in idx {
            let last = eco[k].double
            if eco[k].isNull || last <= 0 { eco[k] = .number(v); continue }
            let change = v / last - 1
            guard abs(change) >= 0.03, !(when[k].isNull ? false : s.week - when[k].int < supplierCooldown) else { continue }
            eco[k] = .number(v); when[k] = .number(Double(s.week))
            moves.append((k, label, last, v, change))
        }
        seen["eco"] = eco; seen["ecoW"] = when
        guard let top = moves.max(by: { abs($0.change) < abs($1.change) }) else { return }
        let pct = Int(saturating: (abs(top.change) * 100).rounded())
        var sentence = "\(top.label) prices are \(top.change > 0 ? "up" : "down") \(pct)%: your costs follow."
        if let c = costChange(s, key: top.key, from: top.last, to: top.now, data: data), let bd = data.catalog[c.company.type], bd.costOfSales > 0, c.company.lastWeekRevenue > 0 {
            let cur = World(state: s, data: data).currency(c.company)
            let share = abs(c.weekly) / (c.company.lastWeekRevenue * bd.costOfSales) * 100
            sentence = "At \(c.company.name) your cost of sales \(c.weekly > 0 ? "rises" : "falls") about \(String(format: "%.1f", share))%, \(cur.display(abs(c.weekly))) a week."
        }
        let others = moves.filter { $0.key != top.key }.map { "\($0.label.lowercased()) \($0.change > 0 ? "up" : "down") \(Int(saturating: (abs($0.change) * 100).rounded()))%" }
        log(&s, .supplierPriceChange, title: "Supplier prices: \(top.label.lowercased()) \(top.change > 0 ? "up" : "down") \(pct)%", detail: sentence,
            amount: top.change, tone: top.change > 0 ? "bad" : "good", consequence: others.isEmpty ? sentence : sentence + " Also \(others.joined(separator: ", ")).")
    }

    static func sweepCountries(_ s: inout GameState, _ seen: inout JSONValue, data: GameData) {
        let known: Set<String>? = seen["ctry"].isNull ? nil : Set(seen["ctry"].array.map { $0.string })
        let now = Set(s.companies.filter { $0.status.isLive }.map { $0.countryCode })
        seen["ctry"] = .array(now.union(known ?? []).sorted().map { .string($0) })
    }

    static func sweepAnniversaries(_ s: inout GameState) {
        for co in s.companies where co.status.isLive {
            for p in co.staff where p.hiredWeek > 0 && s.week > p.hiredWeek && (s.week - p.hiredWeek) % 52 == 0 {
                let years = (s.week - p.hiredWeek) / 52
                let name = s.people[p.id]?.name ?? "A team member"
                log(&s, .recognition, title: "\(name): \(years) year\(years == 1 ? "" : "s") with \(co.name)", detail: "A work anniversary worth a thank-you.", companyID: co.id, tone: "good", employeeID: p.id,
                    consequence: "")
            }
        }
    }

    static func sweepRivals(_ s: inout GameState, _ seen: inout JSONValue, data: GameData) {
        var listedNow: [JSONValue] = []
        let hadSale = !seen["sale"].isNull
        for key in (s.rest["mk"]?.object.keys.sorted() ?? []) {
            guard let co = s.companies.first(where: { $0.status.isLive && Rivals.key($0) == key }) else { continue }
            for r in Rivals.rivals(s, key: key) where r.forSale {
                listedNow.append(.number(Double(r.id)))
                if hadSale, !seen["sale"].array.contains(where: { $0.int == r.id }) {
                    log(&s, .acquisitionOpportunity, title: "\(r.name) is for sale", detail: "A \((data.catalog[co.type]?.name ?? "local").lowercased()) rival has been put up for sale.", companyID: co.id, tone: "n",
                        consequence: data.catalog[co.type].map { bd in let w = World(state: s, data: data); return "Worth about \(w.currency(co).display(Rivals.value(bd, r, w, co))); you can make an offer." } ?? "")
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
                    log(&s, .competitorLostShare, title: "\(p.name) is losing share", detail: "Down \(String(format: "%.1f", (before.double - p.share) * 100)) points of the local market in a week.", companyID: cid, amount: p.share - before.double, tone: "good", consequence: "A weaker rival eases the pressure on your demand here.")
                }
            }
        }
        seen["share"] = .object(shares)
    }
}
