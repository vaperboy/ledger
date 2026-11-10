import Foundation
import GameCore
import Countries
import Employees
import Finance

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
    public static var securityThreshold: Double { tables.securityLimit }

    public static func endWeek(_ m: StaffMember) -> Int? { m.value("ft").isNull ? nil : m.int("ft") }
    public static func isFixed(_ m: StaffMember) -> Bool { endWeek(m) != nil }
    public static func wantsPermanent(_ n: Person) -> Bool { n.num("sec") > tables.securityLimit }

    public static func reviewWindowWeeks(_ lab: LabourRules) -> Int { reviewWindow(lab) }
    static func reviewWindow(_ lab: LabourRules) -> Int { max(tables.review, Int(saturating: lab.fixedTermNoticeWeeks.rounded(.up))) }

    static func runStart(_ m: StaffMember) -> Int? {
        guard let end = endWeek(m) else { return nil }
        if !m.value("fts").isNull { return m.int("fts") }
        return end - max(0, m.int("ftl"))
    }
    static func renewals(_ m: StaffMember) -> Int { m.int("ftr") }

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

    static func allowedRenewal(_ lab: LabourRules, _ m: StaffMember, wanted: Int, now: Int) -> Int? {
        tables.weeks.filter { $0 <= wanted && renewalBlock(lab, m, weeks: $0, now: now) == nil }.max()
    }

    @discardableResult
    public static func set(_ s: inout GameState, companyID: Int, staffID: Int, weeks: Int?, labour: LabourRules? = nil, anyLength: Bool = false) -> Bool {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }) else { return false }
        var st = s.companies[ci].staff
        if let weeks {
            guard tables.weeks.contains(weeks) || (anyLength && Hiring.workingFixedTermWeeks.contains(weeks)) else { return false }
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
                    let seasonal = !m.value("seas").isNull
                    s.addMessage(kind: "ask", from: n.name, title: seasonal ? "\(n.name)'s season at \(co.name) ends in \(end - s.week) weeks" : "\(n.name)'s fixed term at \(co.name) ends in \(end - s.week) weeks",
                                 body: seasonal ? "Their seasonal contract ends in week \(end). Bring them back for another season, or let it end on its date?" : "Their contract ends in week \(end). Renew it for \(weeks) weeks, or let it end on its date?", companyID: co.id, tone: "n", status: "open",
                                 options: [.option(seasonal ? "Another season" : "Renew for \(weeks) weeks", seasonal ? "The contract runs to the end of the next season." : "Another fixed term\(weeks == len ? " of the same length" : ", the longest the rules here allow")."), .option("Let it end", "They leave on the date. What the country's rules require is paid.")],
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

    public static func answer(_ s: inout GameState, message m: Message, option idx: Int) {
        let d = m.value("data"), sid = d["sid"].int
        guard let ci = s.companyIndex(m.companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == sid }), endWeek(s.companies[ci].staff[k]) == d["end"].int else { return }
        if idx == 0 {
            if d["perm"].int != 1, !s.companies[ci].staff[k].value("seas").isNull {
                _ = StaffTalks.renewSeason(&s, companyID: m.companyID, staffID: sid)
            } else {
                _ = set(&s, companyID: m.companyID, staffID: sid, weeks: d["perm"].int == 1 ? nil : d["weeks"].int, anyLength: true)
            }
            ContractHistory.record(&s, companyID: m.companyID, staffID: sid, kind: "term", text: d["perm"].int == 1 ? "Contract made permanent." : "Contract renewed.")
        }
        else { var st = s.companies[ci].staff; st[k].set("ftd", d["end"].int); s.companies[ci].staff = st }
    }
}
