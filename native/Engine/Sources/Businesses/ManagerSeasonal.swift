import Foundation
import GameCore
import Countries
import Employees

/// A manager brings in seasonal help a few weeks before a busy season, when people are what holds the business back.
/// Original: `mgrSeason`, `hireSeasonal`, `helpRole`, `monthF`, `busyMonths` (features/people/seasons_and_hours.js).
///
/// The help is hired the way the owner would hire it (`Hiring.hire` with seasonal terms: part time, the busy months, off and unpaid
/// outside them), so the wages go through the ordinary payroll and the books balance. What the original leaves out is the
/// owner's say: a manager with authority (level 1 or more, the "hire" duty, and the monthly cost within the budget the owner set)
/// hires alone and tells the owner afterwards, with the cost; any other manager asks first, and the owner approves or declines
/// (the ordinary "prop" message, kind "seas"). Once a season is dealt with (hired, asked or declined) it is not raised again that year.
extension ManagerModel {
    public struct SeasonalPlan: Equatable, Sendable {
        public var role: String
        public var months: [Int]
        public var count: Int
        /// What the whole crew costs a month while it works.
        public var monthlyCost: Double
    }

    /// Demand in a month (1-12) against an average month: the trade's seasons and its own peak. Original: `monthF`.
    static func monthFactor(_ co: Company, _ bd: Trade, month m: Int, data: GameData) -> Double {
        var f = 1.0
        if let t = data.catalog.tables.seasons[bd.seasonKey], t.count == 12 { f = t[m - 1] }
        if let pk = data.balance.salesWays[co.type]?.first(where: { $0.kind == "peak" }), pk.peakMonths.contains(m) { f *= 1 + (pk.options["b"] ?? 0.3) }
        return f
    }

    /// The busy months (1-12) of a trade, its own peak included: the ones a seasonal worker is for. Original: `busyMonths`.
    public static func seasonalBusyMonths(_ co: Company, data: GameData) -> [Int] {
        guard let bd = data.catalog[co.type] else { return [] }
        return (1...12).filter { monthFactor(co, bd, month: $0, data: data) >= 1.08 }
    }

    /// The job seasonal help does: the people job that holds the business back, else the first job of the trade. Original: `helpRole`.
    static func seasonalRole(_ s: GameState, _ co: Company, _ bd: Trade, data: GameData) -> String? {
        let roles = data.catalog.tables.roles
        if let bot = CapacityModel.compute(co, bd, World(state: s, data: data)).bottleneck, bot.kind == .staff {
            let key = bot.key.split(separator: ":").last.map(String.init) ?? ""
            if roles[key] != nil { return key }
        }
        guard let first = CompanySetup.standardStaff(bd, size: co.size).first, roles[first.role] != nil else { return nil }
        return first.role
    }

    /// Who a manager would hire three weeks before a busy season starts, if anyone. Original: the first half of `mgrSeason`.
    public static func seasonalPlan(_ s: GameState, companyID: Int, capacity cap: Double, data: GameData) -> SeasonalPlan? {
        guard let co = s.company(companyID), co.status == .open, co.managerID != nil, cap > 0, let bd = data.catalog[co.type] else { return nil }
        let ms = seasonalBusyMonths(co, data: data)
        let now = StaffTalks.month1(s.week), ahead = StaffTalks.month1(s.week + 3)
        guard ms.contains(ahead), !ms.contains(now) else { return nil }
        if co.staff.contains(where: { $0.value("seas").array.contains { $0.int == ahead } }) { return nil }
        guard let role = seasonalRole(s, co, bd, data: data) else { return nil }
        let lift = monthFactor(co, bd, month: ahead, data: data) / max(0.2, monthFactor(co, bd, month: now, data: data)) - 1
        let permanent = co.staff.filter { $0.value("seas").isNull }.count
        let need = Int(jsRound(Double(permanent) * max(0, lift)))
        guard need >= 1 else { return nil }
        let n = min(4, need)
        return SeasonalPlan(role: role, months: ms, count: n, monthlyCost: marketWage(s, co, role: role, data: data) * 0.67 * Double(n))
    }

    /// Hire seasonal workers from the people the manager knows, weighed and bargained with by `AutoHire`.
    /// Returns how many said yes. Original: `hireSeasonal`.
    @discardableResult
    public static func hireSeasonalCrew(_ s: inout GameState, companyID: Int, role: String, months: [Int], count: Int, hours: Double = 25, data: GameData) -> Int {
        guard let ci = s.companyIndex(companyID) else { return 0 }
        var got = 0
        for _ in 0..<max(1, count) {
            let co = s.companies[ci]
            let cands = Hiring.search(role: role, company: co, mode: .network, faces: false, state: &s, data: data)
            guard !cands.isEmpty else { break }
            if AutoHire.hireWorker(role: role, companyID: companyID, candidates: cands, terms: Hiring.Terms(hours: hours, seasonMonths: months), state: &s, data: data) != nil { got += 1 }
        }
        return got
    }

    /// Every second week: plan the help and either hire it within the authority or ask the owner. Original: `mgrSeason`.
    static func seasonalWeek(_ s: inout GameState, _ ci: Int, _ n: Person, data: GameData, capacity cap: Double) {
        let co = s.companies[ci]
        guard s.week % 2 == 0, let plan = seasonalPlan(s, companyID: co.id, capacity: cap, data: data) else { return }
        let stamp = Double(GameCalendar.year(week: s.week + 3) * 12 + StaffTalks.month1(s.week + 3))
        var fl = co.value("flags")
        guard fl["seasAt"].isNull || fl["seasAt"].double != stamp else { return }
        // The wages of the season must be safe to carry, as for any other hire.
        let each = plan.monthlyCost / Double(plan.count)
        if hireShort(s, co, cost: each * Double(plan.months.count), data: data) > 0 { return }
        fl["seasAt"] = .number(stamp)
        s.companies[ci].set("flags", fl)
        let cur = World(state: s, data: data).currency(co)
        let roleName = (data.catalog.tables.roles[plan.role]?.name ?? plan.role).lowercased()
        let when = StaffTalks.seasonText(plan.months)
        let auth = co.value("auth")
        let lvl = dutyAllows(n, "hire") ? auth["lvl"].double : 0
        if lvl >= 1, plan.monthlyCost <= auth["buy"].double {
            execSeasonal(&s, ci, Proposal(kind: "seas", role: plan.role, cost: plan.monthlyCost, id: seasonalKey(plan)), n, data: data)
        } else {
            if s.inbox.contains(where: { $0.companyID == co.id && $0.status == "open" && $0.actionID == "prop" && $0.value("data")["t"].string == "seas" }) { return }
            s.addMessage(kind: "ask", from: n.name, title: "Seasonal help at \(co.name)",
                         body: "A busy season is coming (\(when)). I would like to hire \(plan.count) seasonal \(roleName)\(plan.count > 1 ? "s" : "") for it, part time. They are only paid in those months.",
                         companyID: co.id, tone: "n", status: "open",
                         options: [.option("Approve", "About \(cur.display(plan.monthlyCost)) a month in season"), .option("Decline")],
                         action: "prop",
                         data: .object(["t": .string("seas"), "role": .string(plan.role), "cost": .number(plan.monthlyCost), "id": .string(seasonalKey(plan))]),
                         expiresWeek: s.week + 3)
        }
    }

    /// The crew size and months of a plan, kept in the id of a proposal ("3:6,7,8").
    static func seasonalKey(_ p: SeasonalPlan) -> String { "\(p.count):" + p.months.map(String.init).joined(separator: ",") }

    /// Carry out a seasonal-help proposal and tell the owner what it costs. Original: the end of `mgrSeason`.
    static func execSeasonal(_ s: inout GameState, _ ci: Int, _ dp: Proposal, _ n: Person, data: GameData) {
        let parts = dp.id.split(separator: ":")
        let count = parts.first.flatMap { Int($0) } ?? 1
        let months = parts.count > 1 ? parts[1].split(separator: ",").compactMap { Int($0) } : []
        guard !months.isEmpty, data.catalog.tables.roles[dp.role] != nil else { return }
        let co = s.companies[ci]
        let got = hireSeasonalCrew(&s, companyID: co.id, role: dp.role, months: months, count: count, data: data)
        guard got > 0 else { return }
        let cur = World(state: s, data: data).currency(co)
        let each = dp.cost / Double(max(1, count))
        s.note("\(n.name) hired \(got) seasonal \(got > 1 ? "workers" : "worker") for the busy \(StaffTalks.seasonText(months)) months at \(co.name): about "
               + "\(cur.display(each * Double(got))) a month while they work.", tone: "n", companyID: co.id)
    }
}
