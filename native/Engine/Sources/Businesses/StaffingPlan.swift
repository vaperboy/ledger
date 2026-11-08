import Foundation
import GameCore
import Countries
import Finance

/// The one staffing plan of a company: a target headcount per role, filled by the person responsible for hiring (the store manager; the boss above
/// a store that has none). Replacements for leavers, growth and seasonal crews all go through this loop, in place of the separate automatic hirers.
///
/// Targets: by default what the trade's standard team calls for at the company's size (plus the team a manager inherited), and one more of the
/// role that holds the business back while demand is above capacity, but only if the hirer has the authority and the cash for it. The owner (or the
/// chain's head office, `setChainTarget`) can set any target; that is the instruction, so the hirer needs no further approval for it.
/// Realism: a vacancy opens when someone hands in notice or their fixed term is about to end; the search takes `searchWeeks` before anyone is
/// offered the job, one hire a week per company, and every hire costs a recruiting fee. A store with no manager gets one from `HierarchyHiring`,
/// which keeps the same timing. Saved on the company as `stfPlan`: `t` {role: target set by the owner, "seas" = seasonal crew size}, `o` {role: week
/// the vacancy opened}, `h` week of the last hire, `w` week of the last "cannot afford it" note. Written only when used.
public enum StaffingPlan {
    /// Weeks a vacancy is open before the search ends in an offer.
    public static let searchWeeks = 2
    /// Recruiting fee in months of the going wage, for a permanent hire and for a seasonal one.
    static let recruitingFeeMonths = 0.4
    static let seasonalFeeMonths = 0.2
    static let maxTarget = 30
    /// The role id of the store-manager row (a post, not a headcount the owner can set).
    public static let managerRole = "manager"
    static let seasonalKey = "seas"

    /// One line of the plan.
    public struct Row: Equatable, Sendable, Identifiable {
        public var id: String { seasonal ? "seasonal" : role }
        public var role: String
        public var roleName: String
        public var target: Int
        /// People in the role who stay (not on notice, no fixed term ending soon).
        public var filled: Int
        /// People in the role who are on their way out.
        public var leaving: Int
        public var vacancies: Int { max(0, target - filled) }
        /// Weeks the vacancy has been open (0 when there is none).
        public var weeksOpen: Int
        /// The target was set by the owner or head office, not derived.
        public var ownerSet: Bool
        public var seasonal: Bool
        /// Who fills it: the manager or boss, empty when it is the owner's own job.
        public var hirerName: String
    }

    /// Who hires for a company and what they may decide alone.
    struct Hirer {
        var name: String
        var level: Double
        var buy: Double
        var isBoss: Bool
        /// May the hirer add a monthly cost of `monthly` on their own (growth, not a replacement)?
        func mayGrow(monthly: Double) -> Bool { isBoss ? (level >= 2 || (level >= 1 && monthly <= buy)) : (level >= 1 && monthly <= buy) }
    }

    static func hirer(_ s: GameState, _ co: Company, data: GameData) -> Hirer? {
        if let mid = co.managerID {
            let n = s.people[mid]
            let auth = co.value("auth")
            let mayHire = n.map { ManagerModel.dutyAllows($0, "hire") } ?? true
            return Hirer(name: n?.name ?? "The manager", level: mayHire ? auth["lvl"].double : 0, buy: auth["buy"].double * (n.map { ManagerVoice.budgetUse($0) } ?? 0.75), isBoss: false)
        }
        if let b = HierarchyHiring.staffBoss(s, co, data: data) { return Hirer(name: b.name, level: Double(b.level), buy: b.buy, isBoss: true) }
        return nil
    }

    // MARK: Targets

    static func ownerTargets(_ co: Company) -> [String: JSONValue] { co.value("stfPlan")["t"].object }

    static func isStaffRole(_ role: String, data: GameData) -> Bool { data.catalog.tables.roles[role] != nil && Appointments.classify(role) != .assistant }

    /// The headcount per role: derived from the trade and the work, then the owner's own settings on top.
    static func targets(_ s: GameState, _ co: Company, _ bd: Trade, _ h: Hirer?, data: GameData) -> [String: Int] {
        var out: [String: Int] = [:]
        for (idx, st) in CompanySetup.standardStaff(bd, size: co.size).enumerated() where isStaffRole(st.role, data: data) {
            var n = st.count
            // an owner who works in the business themselves covers the first post
            if idx == 0 && bd.ownerFTE >= 1 && co.managerID == nil && co.ownerHours >= 20 { n = max(0, n - 1) }
            out[st.role] = max(out[st.role] ?? 0, n)
        }
        for (role, want) in co.value("mgrBase")["roles"].object where isStaffRole(role, data: data) { out[role] = max(out[role] ?? 0, want.int) }
        let owner = ownerTargets(co)
        // growth: one more of the role that limits the business, if the hirer may and the company can carry the pay
        if let h = h, ManagerHiring.demandLimited(co), let role = ManagerModel.bottleneckRole(s, co, bd, data: data),
           isStaffRole(role, data: data), owner[role] == nil, ManagerHiring.heads(co, role: role).count >= (out[role] ?? 0) {
            let wage = ManagerModel.marketWage(s, co, role: role, data: data)
            if h.mayGrow(monthly: wage), ManagerModel.hireShort(s, co, cost: wage * 12, data: data) <= 0 { out[role] = (out[role] ?? 0) + 1 }
        }
        for (role, v) in owner where role != seasonalKey && isStaffRole(role, data: data) { out[role] = v.int }
        return out
    }

    static func permanentRows(_ s: GameState, _ co: Company, _ bd: Trade, _ h: Hirer?, data: GameData) -> [Row] {
        let tgt = targets(s, co, bd, h, data: data)
        let p = co.value("stfPlan")
        return tgt.keys.sorted().compactMap { role in
            let all = ManagerHiring.heads(co, role: role)
            let leaving = all.filter { ManagerHiring.departure(s, $0) != nil }.count
            let filled = all.count - leaving
            let target = tgt[role] ?? 0
            let opened = p["o"][role]
            let ownerSet = !p["t"][role].isNull
            guard target > 0 || filled > 0 || ownerSet else { return nil }
            return Row(role: role, roleName: data.catalog.tables.roles[role]?.name ?? role, target: target, filled: filled, leaving: leaving,
                       weeksOpen: target > filled && !opened.isNull ? max(0, s.week - opened.int) : 0, ownerSet: ownerSet, seasonal: false, hirerName: h?.name ?? "")
        }
    }

    /// The seasonal crew: shown from three weeks before a busy season until it is over.
    static func seasonalRow(_ s: GameState, _ co: Company, _ bd: Trade, _ h: Hirer?, data: GameData) -> Row? {
        let cap = co.value("lastW")["cap"].double
        let plan = ManagerModel.seasonalPlan(s, companyID: co.id, capacity: cap, data: data)
        let now = StaffTalks.month1(s.week), ahead = StaffTalks.month1(s.week + 3)
        let crew = co.staff.filter { m in m.value("seas").array.contains { $0.int == ahead || $0.int == now } }
        guard plan != nil || !crew.isEmpty, let role = plan?.role ?? crew.first?.role else { return nil }
        let set = co.value("stfPlan")["t"][seasonalKey]
        let target = plan.map { p in set.isNull ? ((h?.mayGrow(monthly: p.monthlyCost) ?? false) ? p.count : 0) : set.int } ?? crew.count
        return Row(role: role, roleName: data.catalog.tables.roles[role]?.name ?? role, target: target, filled: crew.count, leaving: 0, weeksOpen: 0,
                   ownerSet: !set.isNull, seasonal: true, hirerName: h?.name ?? "")
    }

    /// The store manager's post as a row (read only: `HierarchyHiring` fills it).
    static func managerRow(_ s: GameState, _ co: Company, _ bd: Trade, _ h: Hirer?, data: GameData) -> Row? {
        let open = HierarchyHiring.needsStoreManager(s, co, data: data)
        guard open || (co.managerID != nil && co.ownerHours <= 0) else { return nil }
        let boss = HierarchyHiring.appointer(s, post: .storeManager(companyID: co.id), data: data)
        return Row(role: managerRole, roleName: ManagerModel.title(bd), target: 1, filled: open ? 0 : 1, leaving: 0,
                   weeksOpen: open ? HierarchyHiring.weeksOpen(s, .storeManager(companyID: co.id)) : 0, ownerSet: false, seasonal: false, hirerName: boss?.name ?? "")
    }

    // MARK: Reading and setting

    /// The plan of one company: a row per role (target, who is in, vacancies, weeks open), then the seasonal crew and the store manager's post.
    public static func plan(_ s: GameState, companyID: Int, data: GameData) -> [Row] {
        guard let co = s.company(companyID), let bd = data.catalog[co.type], !bd.hasTrait("noStaff"), bd.family != "rent" else { return [] }
        let h = hirer(s, co, data: data)
        var rows = permanentRows(s, co, bd, h, data: data)
        if let r = seasonalRow(s, co, bd, h, data: data) { rows.append(r) }
        if let r = managerRow(s, co, bd, h, data: data) { rows.append(r) }
        return rows
    }

    static func write(_ s: inout GameState, _ ci: Int, _ change: (inout [String: JSONValue]) -> Void) {
        var d = s.companies[ci].value("stfPlan").object
        change(&d)
        s.companies[ci].set("stfPlan", d.isEmpty ? JSONValue.null : JSONValue.object(d))
    }

    /// Set the headcount to hire towards for a role (or, with `seasonal`, the size of the seasonal crew). The owner's setting is the instruction: the hirer
    /// fills it without asking again. False for a role that is not an ordinary job, or an unknown company.
    @discardableResult
    public static func setTarget(_ s: inout GameState, companyID: Int, role: String, target: Int, seasonal: Bool = false, data: GameData) -> Bool {
        guard let ci = s.companyIndex(companyID), seasonal || isStaffRole(role, data: data) else { return false }
        let key = seasonal ? seasonalKey : role
        write(&s, ci) { d in
            var t = d["t"]?.object ?? [:]
            t[key] = .number(Double(min(maxTarget, max(0, target))))
            d["t"] = .object(t)
        }
        return true
    }

    /// Go back to the derived target for a role (or the seasonal crew).
    @discardableResult
    public static func resetTarget(_ s: inout GameState, companyID: Int, role: String, seasonal: Bool = false) -> Bool {
        guard let ci = s.companyIndex(companyID) else { return false }
        let key = seasonal ? seasonalKey : role
        write(&s, ci) { d in
            var t = d["t"]?.object ?? [:]
            t[key] = nil
            if t.isEmpty { d["t"] = nil } else { d["t"] = .object(t) }
        }
        return true
    }

    /// Head office sets one role's target for every open store of a chain. Returns how many stores took it.
    @discardableResult
    public static func setChainTarget(_ s: inout GameState, chainID: Int, role: String, target: Int, data: GameData) -> Int {
        guard let ch = Chains.chain(s, id: chainID) else { return 0 }
        var n = 0
        for id in Chains.stores(s, ch).filter({ $0.status.isLive }).map({ $0.id }) where setTarget(&s, companyID: id, role: role, target: target, data: data) { n += 1 }
        return n
    }

    // MARK: Timing and cost

    /// Has the search for this role run long enough, and has the company not hired already this week?
    static func searchDone(_ s: GameState, _ co: Company, role: String) -> Bool {
        let p = co.value("stfPlan")
        if !p["h"].isNull, p["h"].int == s.week { return false }
        let opened = p["o"][role]
        return !opened.isNull && s.week - opened.int >= searchWeeks
    }

    /// A hire was made: no second one this week, and the recruiting fee is paid.
    static func hired(_ s: inout GameState, companyIndex ci: Int, role: String, data: GameData) {
        let week = Double(s.week)
        write(&s, ci) { $0["h"] = .number(week) }
        payRecruiting(&s, companyID: s.companies[ci].id, role: role, months: recruitingFeeMonths, data: data)
    }

    static func payRecruiting(_ s: inout GameState, companyID: Int, role: String, months: Double, data: GameData) {
        guard let co = s.company(companyID) else { return }
        let fee = jsRound(ManagerModel.marketWage(s, co, role: role, data: data) * months)
        if fee > 0 { Payments.companyPays(&s, companyID: companyID, amount: fee, category: "oth", label: "Recruiting") }
    }

    // MARK: The weekly step

    /// Every week, for every open company: note which vacancies have opened or closed, then let the responsible person fill one, and plan the seasonal crew.
    public static func weekly(_ s: inout GameState, data: GameData) {
        let context = FinanceContext(countries: data.countries, trades: data.catalog)
        for i in s.companies.indices {
            let co = s.companies[i]
            guard co.status == .open, let bd = data.catalog[co.type], !bd.hasTrait("noStaff"), bd.family != "rent" else { continue }
            let h = hirer(s, co, data: data)
            let rows = permanentRows(s, co, bd, h, data: data)
            track(&s, i, rows)
            guard let boss = h else { continue }
            let owner = ownerTargets(co)
            let standing = Delegation.autoRehire(s, co) || (s.policy.autoRehire && boss.isBoss)
            // a company with nobody yet is staffed by the player, unless the owner has set a target
            guard standing || !owner.isEmpty, !co.staff.isEmpty || !owner.isEmpty else { continue }
            if !fillOne(&s, i, rows, boss, standing: standing, context: context, data: data) { seasonalStep(&s, i, boss, data: data) }
        }
    }

    /// Open a vacancy's clock when it appears, close it when it is filled. The company record is written only when something changed.
    static func track(_ s: inout GameState, _ ci: Int, _ rows: [Row]) {
        let before = s.companies[ci].value("stfPlan")["o"].object
        var open: [String: JSONValue] = [:]
        for r in rows where r.vacancies > 0 { open[r.role] = before[r.role] ?? .number(Double(s.week)) }
        guard open != before else { return }
        write(&s, ci) { d in if open.isEmpty { d["o"] = nil } else { d["o"] = .object(open) } }
    }

    /// One permanent hire at most: the vacancy that has waited longest and may be filled. True if a search was made.
    private static func fillOne(_ s: inout GameState, _ ci: Int, _ rows: [Row], _ boss: Hirer, standing: Bool, context: FinanceContext, data: GameData) -> Bool {
        let co = s.companies[ci]
        let waiting = rows.filter { $0.vacancies > 0 && $0.weeksOpen >= searchWeeks && (standing || $0.ownerSet) }.sorted { ($0.weeksOpen, $1.role) > ($1.weeksOpen, $0.role) }
        guard let row = waiting.first(where: { ManagerHiring.verdict(s, companyID: co.id, role: $0.role, target: $0.target, data: data).allowed }) else { return false }
        let wage = ManagerModel.marketWage(s, co, role: row.role, data: data)
        guard co.cash > context.weeklyCost(co, s) * 4 + wage * 2 else {
            let p = co.value("stfPlan")
            if p["w"].isNull || s.week - p["w"].int > 8 {
                let week = Double(s.week)
                write(&s, ci) { $0["w"] = .number(week) }
                s.note("\(co.name) is short of \(row.roleName.lowercased()) but cannot afford to take someone on yet.", tone: "bad", companyID: co.id)
            }
            return false
        }
        if let r = ManagerHiring.fill(&s, companyID: co.id, role: row.role, target: row.target, data: data) {
            s.note("\(co.name): \(r.person.name) hired as \(row.roleName.lowercased()) by \(boss.isBoss ? "\(boss.name), the boss above" : "the manager")\(ManagerHiring.earlyNote(r.verdict)).", tone: "n", companyID: co.id)
        }
        return true
    }

    /// Three weeks before a busy season: hire the crew if the hirer may carry its pay (or the owner set the size), else tell the owner once.
    private static func seasonalStep(_ s: inout GameState, _ ci: Int, _ boss: Hirer, data: GameData) {
        let co = s.companies[ci]
        let cap = co.value("lastW")["cap"].double
        guard let plan = ManagerModel.seasonalPlan(s, companyID: co.id, capacity: cap, data: data) else { return }
        let stamp = Double(GameCalendar.year(week: s.week + 3) * 12 + StaffTalks.month1(s.week + 3))
        var fl = co.value("flags")
        guard fl["seasAt"].isNull || fl["seasAt"].double != stamp else { return }
        let set = co.value("stfPlan")["t"][seasonalKey]
        let count = set.isNull ? plan.count : set.int
        let monthly = plan.monthlyCost / Double(max(1, plan.count)) * Double(count)
        func done() { fl["seasAt"] = .number(stamp); s.companies[ci].set("flags", fl) }
        if count <= 0 { done(); return }
        // the season's wages must be safe to carry, as for any other hire
        if ManagerModel.hireShort(s, co, cost: monthly / Double(count) * Double(plan.months.count), data: data) > 0 { return }
        done()
        let roleName = (data.catalog.tables.roles[plan.role]?.name ?? plan.role).lowercased()
        let when = StaffTalks.seasonText(plan.months)
        guard !set.isNull || boss.mayGrow(monthly: monthly) else {
            s.note("A busy season is coming at \(co.name) (\(when)). \(boss.name) would need \(count) seasonal \(roleName)\(count > 1 ? "s" : ""); set the crew size in the staffing plan to go ahead.", tone: "n", companyID: co.id)
            return
        }
        let got = ManagerModel.hireSeasonalCrew(&s, companyID: co.id, role: plan.role, months: plan.months, count: count, data: data)
        guard got > 0 else { return }
        let cur = World(state: s, data: data).currency(co)
        s.note("\(boss.name) hired \(got) seasonal \(roleName)\(got > 1 ? "s" : "") for the busy \(when) months at \(co.name): about \(cur.display(monthly / Double(count) * Double(got))) a month while they work.", tone: "n", companyID: co.id)
    }
}
