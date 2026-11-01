import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Expense reimbursement for staff: a phone allowance, uniforms and work clothes, a training allowance and travel expenses. Defined per role in
/// `Resources/staff_expenses.json`, chosen per person in the contract discussion (benefits topic) and kept on the person as `ex`
/// (`{id: 1}`, written only once something is chosen). The company pays them every week as an expense (category `oth`, not wages). Where a country's data
/// marks a reimbursement as a taxable benefit (`staffExpenses.<id>.employerCharge`) the employer's social charge is booked on it as wages; with no
/// country entry the treatment is neutral. A training allowance speeds up learning on the job through the existing skill growth (`StaffRoutine.growSkills`).
public enum StaffExpenses {
    public struct Item: Identifiable, Equatable, Sendable {
        public var id: String, name: String, detail: String
        /// Per person a month at the reference price level.
        public var monthlyCost: Double
        /// The jobs it applies to; empty means every job.
        public var roles: Set<String>
        /// Speed-up of learning on the job while it is on (0 = none).
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
    /// The reimbursements that exist for a job.
    public static func items(forRole role: String) -> [Item] { items.filter { $0.roles.isEmpty || $0.roles.contains(role) } }

    public static func isOn(_ m: StaffMember, _ id: String) -> Bool { m.value("ex")[id].double != 0 }
    public static func on(_ m: StaffMember) -> [Item] { items.filter { isOn(m, $0.id) && ($0.roles.isEmpty || $0.roles.contains(m.role)) } }

    /// Switch one reimbursement on or off for a person. False for an unknown person, or an item that does not exist for their job.
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

    /// What a person's reimbursements cost the company a month.
    public static func monthlyCost(_ m: StaffMember, currency cur: Currency) -> Double { on(m).reduce(0) { $0 + cur.scaledPrice($1.monthlyCost) } }
    public static func monthlyCost(_ co: Company, currency cur: Currency) -> Double { co.staff.reduce(0) { $0 + monthlyCost($1, currency: cur) } }

    /// Does this country treat the reimbursement as a taxable benefit with the employer's social charge? No entry: neutral.
    public static func carriesEmployerCharge(_ country: Country, item id: String) -> Bool { country.pack["staffExpenses"][id]["employerCharge"].bool }

    /// How much faster this person learns on the job (1 = as usual).
    public static func learnFactor(_ m: StaffMember) -> Double {
        guard !m.value("ex").isNull else { return 1 }
        return 1 + on(m).reduce(0) { $0 + $1.learnBoost }
    }

    /// Every week: the reimbursements are paid as an expense; the employer's charge goes to wages where the country says so.
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
