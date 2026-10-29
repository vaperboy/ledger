import Foundation
import GameCore
import Employees

/// Which jobs can be paid on commission, and the plans (`Resources/pay_plans.json`). The general selling jobs are `tables.salesRoles`; the data lists
/// further jobs per trade. A person in such a job who is put on a plan is marked `ppx` so that everything that treats sellers (attribution of sales,
/// commission, the skill lift, the pay talks) includes them, and nobody else in that job.
public enum PayPlans {
    public struct Mode: Equatable, Sendable { public var baseShare: Double, defaultRate: Double }

    struct Tables {
        var mix = Mode(baseShare: 0.6, defaultRate: 0.03)
        var com = Mode(baseShare: 0, defaultRate: 0.06)
        var steps: [Double] = [0.02, 0.03, 0.05, 0.08, 0.12]
        var extra: [String: Set<String>] = [:]
    }

    static let tables: Tables = {
        var t = Tables()
        guard let url = Bundle.module.url(forResource: "pay_plans", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return t }
        t.mix = Mode(baseShare: j["modes"]["mix"]["baseShare"].double, defaultRate: j["modes"]["mix"]["defaultRate"].double)
        t.com = Mode(baseShare: j["modes"]["com"]["baseShare"].double, defaultRate: j["modes"]["com"]["defaultRate"].double)
        let steps = j["rateSteps"].array.map { $0.double }
        if !steps.isEmpty { t.steps = steps }
        for (trade, roles) in j["extraRoles"].object { t.extra[trade] = Set(roles.array.map { $0.string }) }
        return t
    }()

    public static var rateSteps: [Double] { tables.steps }
    public static func mode(_ id: String) -> Mode? { id == "mix" ? tables.mix : id == "com" ? tables.com : nil }
    /// The plan modes that exist for a job in a trade: "fix", "mix", "com". Empty when the job has no commission plan there.
    public static func modes(role: String, trade: String, salesRoles: Set<String>) -> [String] { eligible(role: role, trade: trade, salesRoles: salesRoles) ? ["fix", "mix", "com"] : [] }

    /// May this job be paid on commission in this trade?
    public static func eligible(role: String, trade: String, salesRoles: Set<String>) -> Bool {
        salesRoles.contains(role) || (tables.extra[trade]?.contains(role) ?? false)
    }
    /// Is the job one of the extra, trade-specific ones (not a general selling job)?
    public static func isExtra(role: String, trade: String, salesRoles: Set<String>) -> Bool {
        !salesRoles.contains(role) && (tables.extra[trade]?.contains(role) ?? false)
    }
    /// The jobs the data adds for a trade.
    public static func extraRoles(trade: String) -> Set<String> { tables.extra[trade] ?? [] }

    /// Does this person sell, for everything that treats sellers? A general selling job, or an extra job with a plan.
    public static func sells(_ m: StaffMember, salesRoles: Set<String>) -> Bool { salesRoles.contains(m.role) || m.flag("ppx") }
}
