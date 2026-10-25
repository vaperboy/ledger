import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Bonus plans for ordinary staff. They reuse the machinery of the manager's target bonus (`ManagerTargets`): the same monthly judgement of the
/// three targets, the same yearly sales-and-profit budget. Figures come from `Resources/worker_bonus.json`.
///
///  - Team (shop) target bonus: every month the company meets its targets, each person on a plan gets `targetRate` of their monthly pay per target met.
///  - Year-end (and, for seasonal staff, seasonal) bonus: when the year's budget is met, `yearEndMonths` of pay, pro rata to the weeks served that year.
///  - Performance bonus: each month, people whose skill is at or above the team's average get `performanceRate` of their pay, in a month with no loss.
/// All of it is accrued into the company's payroll (`bnPend`, picked up by `CompanyCosts.wages`) so it carries the employer's charges like wages. A
/// plan is set per person in the contract discussion (bonus plan topic) and kept on the person as `bp`; nothing is written until a plan is set.
public enum WorkerBonus {
    public struct Level: Identifiable, Equatable, Sendable {
        public var id: String, name: String, detail: String
        public var targetRate: Double, yearEndMonths: Double, performanceRate: Double
        public var isNone: Bool { targetRate == 0 && yearEndMonths == 0 && performanceRate == 0 }
    }

    struct Tables {
        var levels: [Level] = []
        var expectHits = 1.5, expectPerformance = 0.5, expectYearEnd = 0.5
        var smoothing = 0.25, happyWeeks = 8
        var performanceNeedsProfit = true
    }

    static let tables: Tables = {
        var t = Tables()
        guard let url = Bundle.module.url(forResource: "worker_bonus", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return t }
        t.levels = j["levels"].array.map { Level(id: $0["id"].string, name: $0["name"].string, detail: $0["detail"].string, targetRate: $0["targetRate"].double,
                                                 yearEndMonths: $0["yearEndMonths"].double, performanceRate: $0["performanceRate"].double) }
        t.expectHits = j["expect"]["hits"].double; t.expectPerformance = j["expect"]["performance"].double; t.expectYearEnd = j["expect"]["yearEnd"].double
        t.smoothing = j["smoothing"].double; t.happyWeeks = j["happyWeeks"].int
        t.performanceNeedsProfit = j["performanceNeedsProfit"].isNull ? true : j["performanceNeedsProfit"].bool
        return t
    }()

    public static var levels: [Level] { tables.levels }
    public static func level(_ id: String) -> Level? { tables.levels.first { $0.id == id } }
    /// The plan this person is on (nil: none).
    public static func level(of m: StaffMember) -> Level? { level(m.str("bp")).flatMap { $0.isNone ? nil : $0 } }

    /// What a plan is likely to pay a month on this pay, before employer charges: the figure shown before a plan is agreed.
    public static func expectedMonthly(_ l: Level, wage: Double) -> Double {
        wage * (l.targetRate * tables.expectHits + l.performanceRate * tables.expectPerformance + l.yearEndMonths / 12 * tables.expectYearEnd)
    }

    /// Put a person on a plan (or off it with "none"). False for an unknown person or plan.
    @discardableResult
    public static func set(_ s: inout GameState, companyID: Int, staffID: Int, level id: String) -> Bool {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }), let l = level(id) else { return false }
        var st = s.companies[ci].staff
        if l.isNone { st[k].raw.removeValue(forKey: "bp") } else { st[k].set("bp", l.id) }
        s.companies[ci].staff = st
        return true
    }

    /// Does the company have what the plan is judged on: monthly targets (managed, or set by the owner)?
    public static func hasTargets(_ co: Company, week: Int) -> Bool { !(ManagerTargets.current(co, week: week)?.isNull ?? true) }

    static func accrue(_ s: inout GameState, _ ci: Int, _ k: Int, _ amount: Double, _ lines: inout [String: Double]) {
        guard amount > 0 else { return }
        var st = s.companies[ci].staff
        st[k].set("bnM", st[k].num("bnM") + amount)
        st[k].set("bnYtd", st[k].num("bnYtd") + amount)
        st[k].happyUntilWeek = max(st[k].happyUntilWeek, s.week + tables.happyWeeks)
        s.companies[ci].staff = st
        s.companies[ci].set("bnPend", s.companies[ci].num("bnPend") + amount)
        lines[st[k].str("role"), default: 0] += amount
    }

    /// The year closed with the budget met or missed: the year-end bonus of everyone on a plan. Call it before `monthEnd` in the same week.
    static func yearEnd(_ s: inout GameState, _ ci: Int, budgetMet: Bool) {
        var paid: [String: Double] = [:]
        for k in s.companies[ci].staff.indices {
            let m = s.companies[ci].staff[k]
            if budgetMet, let l = level(of: m), l.yearEndMonths > 0, !m.isOffSeason || m.flag("seas") {
                let served = min(52, Double(max(0, s.week - m.hiredWeek))) / 52
                accrue(&s, ci, k, m.monthlyWage * l.yearEndMonths * served, &paid)
            }
            var st = s.companies[ci].staff; st[k].raw.removeValue(forKey: "bnYtd"); s.companies[ci].staff = st
        }
    }

    /// The month closed: the team target bonus (`hits` of three targets met, nil when no targets were judged), the performance bonus, and the smoothed
    /// bonus each person counts as pay.
    static func monthEnd(_ s: inout GameState, _ ci: Int, hits: Int?) {
        let co = s.companies[ci]
        guard co.staff.contains(where: { level(of: $0) != nil }) else { return }
        let profitOK = !tables.performanceNeedsProfit || (co.monthlyHistory.last.map { $0.profit >= 0 } ?? false)
        var mean = 0.0
        var scores: [Int: Double] = [:]
        for m in co.staff { if let n = s.people[m.id] { scores[m.id] = n.skill + m.skillGain } }
        if !scores.isEmpty { mean = scores.values.reduce(0, +) / Double(scores.count) }
        var paid: [String: Double] = [:]
        for k in s.companies[ci].staff.indices {
            let m = s.companies[ci].staff[k]
            guard let l = level(of: m) else { continue }
            if !m.isOffSeason {
                if let hits, hits > 0, l.targetRate > 0 { accrue(&s, ci, k, m.monthlyWage * l.targetRate * Double(hits), &paid) }
                if profitOK, l.performanceRate > 0, scores.count >= 2, (scores[m.id] ?? 0) >= mean { accrue(&s, ci, k, m.monthlyWage * l.performanceRate, &paid) }
            }
            var st = s.companies[ci].staff
            let got = st[k].num("bnM")
            st[k].set("bnEma", st[k].num("bnEma") * (1 - tables.smoothing) + got * tables.smoothing)
            st[k].raw.removeValue(forKey: "bnM")
            s.companies[ci].staff = st
        }
    }
}
