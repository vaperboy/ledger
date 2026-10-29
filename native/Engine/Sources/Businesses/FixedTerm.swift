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

    /// Put someone on a fixed term of `weeks` from now (`weeks` nil: make the contract permanent). On a term already running, `weeks` is added to
    /// its end date (a renewal). False for an unknown person or a term that is not one of the data's lengths.
    @discardableResult
    public static func set(_ s: inout GameState, companyID: Int, staffID: Int, weeks: Int?) -> Bool {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }) else { return false }
        var st = s.companies[ci].staff
        if let weeks {
            guard tables.weeks.contains(weeks) else { return false }
            let from = max(s.week, endWeek(st[k]) ?? s.week)
            st[k].set("ft", from + weeks); st[k].set("ftl", weeks)
            st[k].raw.removeValue(forKey: "ftn"); st[k].raw.removeValue(forKey: "ftd")
        } else {
            for key in ["ft", "ftl", "ftn", "ftd"] { st[k].raw.removeValue(forKey: key) }
        }
        s.companies[ci].staff = st
        return true
    }

    // MARK: Weekly

    /// Ask about renewal when the end date is near; end the job on the date.
    public static func weekly(_ s: inout GameState, data: GameData) {
        for ci in s.companies.indices where s.companies[ci].status.isLive {
            for m in s.companies[ci].staff where isFixed(m) {
                guard let end = endWeek(m), let n = s.people[m.id] else { continue }
                let co = s.companies[ci]
                if s.week >= end {
                    let given = m.int("ftd") == end
                    if let q = Dismissal.expire(&s, companyID: co.id, staffID: m.id, noticeGiven: given, data: data) {
                        s.note("\(n.name)'s fixed term at \(co.name) ended" + (q.total > 0 ? " (paid \(World(state: s, data: data).currency(s.companies[ci]).display(q.total)) as the labour rules require)." : "."), tone: "n", companyID: co.id)
                    }
                    continue
                }
                let window = reviewWindow(World(state: s, data: data).labour(co))
                guard s.week >= end - window, m.int("ftn") != end else { continue }
                var st = s.companies[ci].staff
                if let k = st.firstIndex(where: { $0.id == m.id }) { st[k].set("ftn", end); s.companies[ci].staff = st }
                let len = m.int("ftl") > 0 ? m.int("ftl") : (tables.weeks.first ?? 52)
                s.addMessage(kind: "ask", from: n.name, title: "\(n.name)'s fixed term at \(co.name) ends in \(end - s.week) weeks",
                             body: "Their contract ends in week \(end). Renew it for \(len) weeks, or let it end on its date?", companyID: co.id, tone: "n", status: "open",
                             options: [.option("Renew for \(len) weeks", "Another fixed term of the same length."), .option("Let it end", "They leave on the date. What the country's rules require is paid.")],
                             action: action, data: .object(["sid": .number(Double(m.id)), "weeks": .number(Double(len)), "end": .number(Double(end))]), expiresWeek: end)
            }
        }
    }

    /// The owner's answer to the renewal question.
    public static func answer(_ s: inout GameState, message m: Message, option idx: Int) {
        let d = m.value("data"), sid = d["sid"].int
        guard let ci = s.companyIndex(m.companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == sid }), endWeek(s.companies[ci].staff[k]) == d["end"].int else { return }
        if idx == 0 { _ = set(&s, companyID: m.companyID, staffID: sid, weeks: d["weeks"].int) }
        else { var st = s.companies[ci].staff; st[k].set("ftd", d["end"].int); s.companies[ci].staff = st }
    }
}
