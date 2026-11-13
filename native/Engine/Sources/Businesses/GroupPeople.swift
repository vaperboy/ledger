import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum GroupPeople {
    struct Loc {
        var read: (GameState) -> JSONValue
        var write: (inout GameState, (inout JSONValue) -> Void) -> Void
    }

    static func locate(_ s: GameState, _ id: Int) -> Loc? {
        if let o = s.rest["office"], let k = o["staff"].array.firstIndex(where: { $0["id"].int == id }) {
            return Loc(read: { $0.rest["office"]?["staff"][k] ?? .null },
                       write: { s, f in var o = s.rest["office"] ?? .null; var l = o["staff"].array; f(&l[k]); o["staff"] = .array(l); s.rest["office"] = o })
        }
        if s.rest["org56"]?["md"]["npc"].int == id {
            return Loc(read: { $0.rest["org56"]?["md"] ?? .null }, write: { s, f in var o = s.rest["org56"] ?? .null; f(&o["md"]); s.rest["org56"] = o })
        }
        let chains = s.rest["chains"]?.array ?? []
        if let k = chains.firstIndex(where: { $0["ceo56"]["npc"].int == id }) {
            return Loc(read: { $0.rest["chains"]?[k]["ceo56"] ?? .null },
                       write: { s, f in var l = s.rest["chains"]?.array ?? []; f(&l[k]["ceo56"]); s.rest["chains"] = .array(l) })
        }
        let regional = s.rest["group"]?["regional"].array ?? []
        if let k = regional.firstIndex(where: { $0["npc"].int == id }) {
            return Loc(read: { $0.rest["group"]?["regional"][k] ?? .null },
                       write: { s, f in var g = s.rest["group"] ?? .null; var l = g["regional"].array; f(&l[k]); g["regional"] = .array(l); s.rest["group"] = g })
        }
        for (ci, co) in s.companies.enumerated() {
            let team = co.value("team")
            if team["ceo"]["npc"].int == id {
                return Loc(read: { $0.companies[ci].value("team")["ceo"] }, write: { s, f in var t = s.companies[ci].value("team"); f(&t["ceo"]); s.companies[ci].set("team", t) })
            }
            if let key = team["heads"].object.first(where: { $0.value["npc"].int == id })?.key {
                return Loc(read: { $0.companies[ci].value("team")["heads"][key] }, write: { s, f in var t = s.companies[ci].value("team"); var h = t["heads"]; f(&h[key]); t["heads"] = h; s.companies[ci].set("team", t) })
            }
        }
        return nil
    }

    public static func isGroupPerson(_ s: GameState, _ id: Int) -> Bool { locate(s, id) != nil }

    public static func wage(_ s: GameState, personID: Int) -> Double? { locate(s, personID).map { $0.read(s)["wage"].double } }
    public static func level(_ s: GameState, personID: Int) -> Int { locate(s, personID).map { Budget.of($0.read(s)).rawValue } ?? 0 }
    public static func percent(_ s: GameState, personID: Int) -> Double { s.people[personID].map { $0.value("gp").isNull ? 100 : $0.num("gp") } ?? 100 }
    public static func expenseItems(_ s: GameState, personID: Int) -> [String] {
        (s.people[personID]?.value("gx").object ?? [:]).filter { $0.value.double != 0 }.map { $0.key }.sorted()
    }

    static func currency(_ s: GameState, _ data: GameData) -> Currency { ManagerModel.playerCurrency(s, data) }

    @discardableResult
    public static func raise(_ s: inout GameState, personID: Int, percent: Double, data: GameData) -> Bool {
        guard percent > 0, let loc = locate(s, personID) else { return false }
        let cur = currency(s, data)
        loc.write(&s) { $0["wage"] = .number(cur.roundedStep($0["wage"].double * (1 + percent), about: 100)) }
        StaffPromises.noticeChange(&s, companyID: 0)
        return true
    }

    @discardableResult
    public static func promote(_ s: inout GameState, personID: Int, data: GameData) -> Bool {
        guard let loc = locate(s, personID), var n = s.people[personID] else { return false }
        let cur = currency(s, data)
        loc.write(&s) { Budget.write(Budget(rawValue: min(2, Budget.of($0).rawValue + 1)) ?? .free, into: &$0); $0["wage"] = .number(cur.roundedStep($0["wage"].double * 1.05, about: 100)) }
        n.set("gpro", n.int("gpro") + 1)
        s.people[personID] = n
        StaffPromises.noticeChange(&s, companyID: 0)
        return true
    }

    @discardableResult
    public static func setLevel(_ s: inout GameState, personID: Int, level: Int) -> Bool {
        guard let loc = locate(s, personID) else { return false }
        loc.write(&s) { Budget.write(Budget(rawValue: min(2, max(0, level))) ?? .normal, into: &$0) }
        StaffPromises.noticeChange(&s, companyID: 0)
        return true
    }

    @discardableResult
    public static func train(_ s: inout GameState, personID: Int, data: GameData) -> Bool {
        guard locate(s, personID) != nil, var n = s.people[personID] else { return false }
        let cost = currency(s, data).scaledPrice(6000)
        guard Payments.liquid(s) >= cost else { return false }
        Payments.playerPays(&s, cost, label: "Course for \(n.name)")
        n.set("crsN", n.int("crsN") + 1)
        s.people[personID] = n
        MarketEvents.log(&s, .recognition, title: "\(n.name) finished a course", detail: "Training paid for by you.", tone: "good", employeeID: personID)
        StaffPromises.noticeChange(&s, companyID: 0)
        return true
    }

    @discardableResult
    public static func setExpense(_ s: inout GameState, personID: Int, item: String, on: Bool) -> Bool {
        guard locate(s, personID) != nil, StaffExpenses.item(item) != nil, var n = s.people[personID] else { return false }
        var gx = n.value("gx"); if gx.isNull { gx = .object([:]) }
        gx[item] = .number(on ? 1 : 0)
        n.set("gx", gx)
        s.people[personID] = n
        StaffPromises.noticeChange(&s, companyID: 0)
        return true
    }

    @discardableResult
    public static func setPercent(_ s: inout GameState, personID: Int, percent: Double) -> Bool {
        guard Hiring.workingPercentRange.contains(percent), let loc = locate(s, personID), var n = s.people[personID] else { return false }
        let old = percentage(n)
        loc.write(&s) { $0["wage"] = .number($0["wage"].double * percent / old) }
        n.set("gp", percent)
        s.people[personID] = n
        StaffPromises.noticeChange(&s, companyID: 0)
        return true
    }
    static func percentage(_ n: Person) -> Double { n.value("gp").isNull ? 100 : n.num("gp") }

    static func weekly(_ s: inout GameState, data: GameData) {
        let cur = currency(s, data)
        for n in s.people.values.sorted(by: { $0.id < $1.id }) where !n.value("gx").isNull && n.employerID != 0 && n.employerID != Hiring.goneElsewhere {
            var cost = 0.0
            for (k, v) in n.value("gx").object.sorted(by: { $0.key < $1.key }) where v.double != 0 { cost += StaffExpenses.item(k).map { cur.scaledPrice($0.monthlyCost) } ?? 0 }
            if cost > 0 { Payments.playerPays(&s, cost * 12 / 52, label: "Expenses: \(n.name)") }
        }
    }
}
