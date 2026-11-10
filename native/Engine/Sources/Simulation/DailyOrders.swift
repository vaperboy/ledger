import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum DailyOrders {
    public static let action = "dord"
    static let key = "dord"
    static let firstWeek = 8
    static let chance = 0.3

    public struct Offer: Equatable, Sendable {
        public var companyID: Int
        public var customer: String
        public var base: Double
        public var target: Double
        public var bonus: Double
    }

    public static func offer(_ s: GameState, data: GameData) -> Offer? {
        guard s.week >= firstWeek else { return nil }
        let ready = s.companies.filter { $0.status == .open && $0.lastWeekUnits >= 4 && $0.lastWeekRevenue > 0 }
        guard !ready.isEmpty else { return nil }
        var r = HashedRandom("\(s.seed):dord:\(s.week):\(s.day)")
        guard r.next() < chance else { return nil }
        let co = ready[Int(r.next() * Double(ready.count)) % ready.count]
        let base = co.lastWeekUnits
        let extra = max(1, (base * (0.12 + 0.1 * r.next())).rounded())
        let unit = co.lastWeekRevenue / base
        let country = data.countries[co.countryCode]
        let firsts: [String] = (country?.firstNames ?? []).isEmpty ? ["Alex"] : (country?.firstNames ?? [])
        let lasts: [String] = (country?.lastNames ?? []).isEmpty ? ["Smith"] : (country?.lastNames ?? [])
        let name = firsts[Int(r.next() * Double(firsts.count)) % firsts.count] + " " + lasts[Int(r.next() * Double(lasts.count)) % lasts.count]
        return Offer(companyID: co.id, customer: name, base: base, target: (base + extra).rounded(), bonus: (extra * unit * 0.5).rounded())
    }

    public static func hasOpenOffer(_ s: GameState) -> Bool {
        s.inbox.contains { $0.status == "open" && $0.actionID == action }
    }

    public static func active(_ s: GameState) -> JSONValue? {
        guard let a = s.rest[key]?["act"], !a.isNull else { return nil }
        return a
    }

    public static func runDay(_ s: inout GameState, data: GameData) {
        settle(&s, data: data)
        guard active(s) == nil, !hasOpenOffer(s), let o = offer(s, data: data), let co = s.company(o.companyID) else { return }
        let cur = World(state: s, data: data).currency(co)
        let title = "\(o.customer) wants a special order from \(co.name)"
        let body = "Reach \(Int(saturating: o.target)) units sold by the end of next week (a normal week is about \(Int(saturating: o.base.rounded()))) and \(o.customer) adds a bonus of \(cur.display(o.bonus)). Ignore it and nothing happens."
        let detail = "Bonus \(cur.display(o.bonus)) if you reach \(Int(saturating: o.target)) units."
        let info: JSONValue = .object(["kind": .string("dorder"), "co": .number(Double(co.id)), "who": .string(o.customer),
                                       "target": .number(o.target), "bonus": .number(o.bonus)])
        s.addMessage(kind: "ask", from: o.customer, title: title, body: body, companyID: co.id, tone: "n", status: "open",
                     options: [.option("Accept", detail), .option("Not now", "No cost.")],
                     action: action, data: info, expiresWeek: s.week + 1)
    }

    public static func answer(_ s: inout GameState, message m: Message, option idx: Int) {
        guard idx == 0, active(s) == nil else { return }
        let d = m.value("data")
        guard let co = s.company(d["co"].int), co.status == .open else { return }
        var st = s.rest[key] ?? .object([:])
        st["act"] = .object(["co": d["co"], "who": d["who"], "target": d["target"], "bonus": d["bonus"], "week": .number(Double(s.week + 1))])
        s.rest[key] = st
        s.note("You took \(d["who"].string)'s order at \(co.name). Reach \(Int(saturating: d["target"].double)) units next week.", tone: "good", companyID: co.id)
    }

    static func settle(_ s: inout GameState, data: GameData) {
        guard let a = active(s) else { return }
        let due = a["week"].int
        guard s.week > due || (s.week == due && s.day == 6) else { return }
        var st = s.rest[key] ?? .object([:])
        st["act"] = .null
        s.rest[key] = st
        let id = a["co"].int
        guard let co = s.company(id), co.status == .open else { return }
        let who = a["who"].string
        if s.week == due, co.lastWeekUnits >= a["target"].double {
            Payments.companyReceives(&s, companyID: id, amount: a["bonus"].double, category: "rev", label: "Special order: \(who)")
            let cur = World(state: s, data: data).currency(co)
            s.note("\(who) paid a bonus of \(cur.display(a["bonus"].double)) for the special order at \(co.name).", tone: "good", companyID: id)
        } else {
            s.note("The special order from \(who) was not filled. No harm done.", tone: "n", companyID: id)
        }
    }
}
