import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum StaffExpenses {
    public struct Item: Identifiable, Equatable, Sendable {
        public var id: String, name: String, detail: String
        public var monthlyCost: Double
        public var roles: Set<String>
        public var learnBoost: Double
    }

    static let items: [Item] = {
        guard let url = Bundle.module.url(forResource: "staff_expenses", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return [] }
        return j["items"].array.map {
            let roles = Set($0["roles"].array.map { $0.string })
            return Item(id: $0["id"].string, name: $0["name"].string, detail: $0["detail"].string, monthlyCost: $0["monthlyCost"].double,
                        roles: roles.contains("*") ? [] : roles, learnBoost: $0["learnBoost"].double)
        }
    }()

    public static var all: [Item] { items }
    public static func item(_ id: String) -> Item? { items.first { $0.id == id } }
    public static func items(forRole role: String) -> [Item] { items.filter { $0.roles.isEmpty || $0.roles.contains(role) } }

    public static func isOn(_ m: StaffMember, _ id: String) -> Bool { m.value("ex")[id].double != 0 }
    public static func on(_ m: StaffMember) -> [Item] { items.filter { isOn(m, $0.id) && ($0.roles.isEmpty || $0.roles.contains(m.role)) } }

    @discardableResult
    public static func set(_ s: inout GameState, companyID: Int, staffID: Int, item id: String, on: Bool) -> Bool {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }), let it = item(id),
              it.roles.isEmpty || it.roles.contains(s.companies[ci].staff[k].role) else { return false }
        var st = s.companies[ci].staff
        var ex = st[k].value("ex"); if ex.isNull { ex = .object([:]) }
        if on { ex[id] = .number(1) } else if case .object(var o) = ex { o.removeValue(forKey: id); ex = .object(o) }
        if case .object(let o) = ex, o.isEmpty { st[k].raw.removeValue(forKey: "ex") } else { st[k].set("ex", ex) }
        s.companies[ci].staff = st
        return true
    }

    public static func monthlyCost(_ m: StaffMember, currency cur: Currency) -> Double { on(m).reduce(0) { $0 + cur.scaledPrice($1.monthlyCost) } }
    public static func monthlyCost(_ co: Company, currency cur: Currency) -> Double { co.staff.reduce(0) { $0 + monthlyCost($1, currency: cur) } }

    public static func carriesEmployerCharge(_ country: Country, item id: String) -> Bool { country.pack["staffExpenses"][id]["employerCharge"].bool }

    public static func learnFactor(_ m: StaffMember) -> Double {
        guard !m.value("ex").isNull else { return 1 }
        return 1 + on(m).reduce(0) { $0 + $1.learnBoost }
    }

    public static func weekly(_ s: inout GameState, data: GameData) {
        let w = World(state: s, data: data)
        for i in s.companies.indices where s.companies[i].status == .open && s.companies[i].staff.contains(where: { !$0.value("ex").isNull }) {
            let co = s.companies[i]
            let cur = w.currency(co), country = w.country(co)
            var byItem: [String: Double] = [:]
            for m in co.staff where !m.isOffSeason { for it in on(m) { byItem[it.id, default: 0] += cur.scaledPrice(it.monthlyCost) * 12 / 52 } }
            for it in items {
                guard let amount = byItem[it.id], amount > 0 else { continue }
                Payments.companyPays(&s, companyID: co.id, amount: amount, category: "oth", label: "Staff expenses: \(it.name.lowercased())")
                if carriesEmployerCharge(country, item: it.id) {
                    Payments.companyPays(&s, companyID: co.id, amount: amount * (country.employerCostFactor - 1), category: "wages", label: "Employer charges on \(it.name.lowercased())")
                }
            }
        }
    }
}
