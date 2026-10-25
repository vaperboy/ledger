import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Fixed-term contracts. A person is permanent unless they carry `ft`, the week the term ends (written only for a fixed term, with `ftl` the length it
/// was agreed for). The term is a topic of the contract discussion and a term of the hire offer. A few weeks before the end date the owner is asked in
/// the Inbox whether to renew; on the date the job ends. What that costs is the country's labour data for the reason `expiry`: the notice and the
/// severance it lists for it, and nothing where it lists none (the neutral default; no country lists any yet). Figures: `Resources/contract_terms.json`.
public enum FixedTerm {
    public static let action = "ftx"

    struct Tables { var weeks = [26, 52, 104], review = 4, securityLimit = 0.65 }
    static let tables: Tables = {
        var t = Tables()
        guard let url = Bundle.module.url(forResource: "contract_terms", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return t }
        let w = j["termWeeks"].array.map { $0.int }
        if !w.isEmpty { t.weeks = w }
        t.review = max(1, j["reviewWeeks"].int)
        if !j["securityLimit"].isNull { t.securityLimit = j["securityLimit"].double }
        return t
    }()

    public static var termChoices: [Int] { tables.weeks }

    /// The week the term ends, nil for a permanent contract.
    public static func endWeek(_ m: StaffMember) -> Int? { m.value("ft").isNull ? nil : m.int("ft") }
    public static func isFixed(_ m: StaffMember) -> Bool { endWeek(m) != nil }
    /// Someone who needs security does not take a fixed-term job instead of a permanent one.
    public static func wantsPermanent(_ n: Person) -> Bool { n.num("sec") > tables.securityLimit }

    /// Weeks before the end date at which the owner is asked: the data's review time, or the country's notice for not renewing when that is longer.
    public static func reviewWindowWeeks(_ lab: LabourRules) -> Int { reviewWindow(lab) }
    static func reviewWindow(_ lab: LabourRules) -> Int { max(tables.review, Int(lab.fixedTermNoticeWeeks.rounded(.up))) }

    /// When the run of fixed terms the person is on began (`fts`; for a term from before that key existed, the start of the current term).
    static func runStart(_ m: StaffMember) -> Int? {
        guard let end = endWeek(m) else { return nil }
        if !m.value("fts").isNull { return m.int("fts") }
        return end - max(0, m.int("ftl"))
    }
    /// How many times the running term has been renewed (`ftr`, written only after the first renewal).
    static func renewals(_ m: StaffMember) -> Int { m.int("ftr") }

    /// Why a fixed term of `weeks` (a first term, or a renewal of the running one) is not allowed under the country's limits, or nil when it is.
    /// Both limits are optional data (`fixedTermMaxWeeks`, `fixedTermMaxRenewals`); at 0 nothing is limited and nothing converts.
    public static func renewalBlock(_ lab: LabourRules, _ m: StaffMember, weeks: Int, now: Int) -> String? {
        let running = endWeek(m)
        let start = runStart(m) ?? now
        let newEnd = max(now, running ?? now) + weeks
        if lab.fixedTermMaxWeeks > 0, Double(newEnd - start) > lab.fixedTermMaxWeeks {
            return "Fixed terms with the same employer may not run longer than \(Int(lab.fixedTermMaxWeeks)) weeks in all here."
        }
        if running != nil, lab.fixedTermMaxRenewals > 0, Double(renewals(m)) >= lab.fixedTermMaxRenewals {
            return "A fixed term may be renewed at most \(Int(lab.fixedTermMaxRenewals)) times here."
        }
        return nil
    }

    /// The longest renewal (one of the data's lengths, no longer than `wanted`) the limits allow; nil when none is allowed, so the owner must
    /// choose between a permanent contract and letting the person go.
    static func allowedRenewal(_ lab: LabourRules, _ m: StaffMember, wanted: Int, now: Int) -> Int? {
        tables.weeks.filter { $0 <= wanted && renewalBlock(lab, m, weeks: $0, now: now) == nil }.max()
    }

    /// Put someone on a fixed term of `weeks` from now (`weeks` nil: make the contract permanent). On a term already running, `weeks` is added to
    /// its end date (a renewal). False for an unknown person, a term that is not one of the data's lengths, or (when `labour` is given) a term its limits refuse.
    @discardableResult
    public static func set(_ s: inout GameState, companyID: Int, staffID: Int, weeks: Int?, labour: LabourRules? = nil) -> Bool {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }) else { return false }
        var st = s.companies[ci].staff
        if let weeks {
            guard tables.weeks.contains(weeks) else { return false }
            if let labour, renewalBlock(labour, st[k], weeks: weeks, now: s.week) != nil { return false }
            let running = isFixed(st[k])
            let from = max(s.week, endWeek(st[k]) ?? s.week)
            let start = runStart(st[k]) ?? s.week
            let renewed = running ? renewals(st[k]) + 1 : 0
            st[k].set("ft", from + weeks); st[k].set("ftl", weeks); st[k].set("fts", start)
            if renewed > 0 { st[k].set("ftr", renewed) } else { st[k].raw.removeValue(forKey: "ftr") }
            st[k].raw.removeValue(forKey: "ftn"); st[k].raw.removeValue(forKey: "ftd")
        } else {
            for key in ["ft", "ftl", "ftn", "ftd", "fts", "ftr"] { st[k].raw.removeValue(forKey: key) }
        }
        s.companies[ci].staff = st
        return true
    }

    // MARK: Weekly

    /// Ask about renewal when the end date is near; end the job on the date. Where the country's limits allow no further renewal the question is
    /// permanent contract or let go, and an unanswered question turns the contract permanent on the date (a term that is not allowed to continue as a
    /// term does not simply lapse for the employer). `labour` is read from the company's country unless a caller supplies it.
    public static func weekly(_ s: inout GameState, data: GameData, labour: ((GameState, GameData, Company) -> LabourRules)? = nil) {
        for ci in s.companies.indices where s.companies[ci].status.isLive {
            for m in s.companies[ci].staff where isFixed(m) {
                guard let end = endWeek(m), let n = s.people[m.id] else { continue }
                let co = s.companies[ci]
                let lab = labour?(s, data, co) ?? World(state: s, data: data).labour(co)
                let len = m.int("ftl") > 0 ? m.int("ftl") : (tables.weeks.first ?? 52)
                let limited = lab.fixedTermMaxWeeks > 0 || lab.fixedTermMaxRenewals > 0
                let renew: Int? = limited ? allowedRenewal(lab, m, wanted: len, now: s.week) : len
                if s.week >= end {
                    let given = m.int("ftd") == end
                    if renew == nil, !given {
                        set(&s, companyID: co.id, staffID: m.id, weeks: nil)
                        s.note("\(n.name) has been on fixed terms at \(co.name) for as long as the rules here allow, so the contract is now permanent.", tone: "n", companyID: co.id)
                        continue
                    }
                    if let q = Dismissal.expire(&s, companyID: co.id, staffID: m.id, noticeGiven: given, data: data) {
                        s.note("\(n.name)'s fixed term at \(co.name) ended" + (q.total > 0 ? " (paid \(World(state: s, data: data).currency(s.companies[ci]).display(q.total)) as the labour rules require)." : "."), tone: "n", companyID: co.id)
                    }
                    continue
                }
                let window = reviewWindow(lab)
                guard s.week >= end - window, m.int("ftn") != end else { continue }
                var st = s.companies[ci].staff
                if let k = st.firstIndex(where: { $0.id == m.id }) { st[k].set("ftn", end); s.companies[ci].staff = st }
                if let weeks = renew {
                    s.addMessage(kind: "ask", from: n.name, title: "\(n.name)'s fixed term at \(co.name) ends in \(end - s.week) weeks",
                                 body: "Their contract ends in week \(end). Renew it for \(weeks) weeks, or let it end on its date?", companyID: co.id, tone: "n", status: "open",
                                 options: [.option("Renew for \(weeks) weeks", "Another fixed term\(weeks == len ? " of the same length" : ", the longest the rules here allow")."), .option("Let it end", "They leave on the date. What the country's rules require is paid.")],
                                 action: action, data: .object(["sid": .number(Double(m.id)), "weeks": .number(Double(weeks)), "end": .number(Double(end))]), expiresWeek: end)
                } else {
                    s.addMessage(kind: "ask", from: n.name, title: "\(n.name)'s fixed term at \(co.name) cannot be renewed again",
                                 body: "Their contract ends in week \(end), and the rules here allow no further fixed term. Make the contract permanent, or let it end on its date? If you do not answer, it becomes permanent.", companyID: co.id, tone: "n", status: "open",
                                 options: [.option("Make permanent", "They stay on a permanent contract, with the notice and severance that comes with it."), .option("Let it end", "They leave on the date. What the country's rules require is paid.")],
                                 action: action, data: .object(["sid": .number(Double(m.id)), "perm": .number(1), "end": .number(Double(end))]), expiresWeek: end)
                }
            }
        }
    }

    /// The owner's answer to the renewal question.
    public static func answer(_ s: inout GameState, message m: Message, option idx: Int) {
        let d = m.value("data"), sid = d["sid"].int
        guard let ci = s.companyIndex(m.companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == sid }), endWeek(s.companies[ci].staff[k]) == d["end"].int else { return }
        if idx == 0 { _ = set(&s, companyID: m.companyID, staffID: sid, weeks: d["perm"].int == 1 ? nil : d["weeks"].int) }
        else { var st = s.companies[ci].staff; st[k].set("ftd", d["end"].int); s.companies[ci].staff = st }
    }
}
