import Foundation
import GameCore
import Countries
import Employees

public enum StaffTalks {
    public static func raiseNeeded(role: String, tables: TradeTables) -> Double {
        let base = tables.roles[role]?.baseMonthlyWage ?? 50000
        return base >= 70000 ? 0.07 : 0.06
    }

    static func wantsFixedSalary(_ n: Person) -> Bool { HashedRandom.first("fix:\(n.id)") < 0.75 }

    static func skill(_ m: StaffMember, _ n: Person, salesRoles: Set<String>) -> Double {
        var v = n.skill + m.skillGain - (m.num("nr") > 0 ? 10 : 0)
        if let mode = m.commissionMode, salesRoles.contains(m.role) || m.flag("ppx") { v += mode == "com" ? 9 : mode == "mix" ? 4 : 0 }
        return clamp(v, 0, 100)
    }

    static func nextTalk(_ m: StaffMember, _ n: Person, company co: Company, gap rawGap: Double, perkShare: Double = 0, tenure ten: Double, week: Int, salesRoles: Set<String>) -> StaffEvent? {
        let gap = rawGap - perkShare
        if co.managerID == nil {
            let lastRaise = m.raw["lr"].map { $0.isNull ? m.hiredWeek : $0.int } ?? m.hiredWeek
            let askW = m.raw["askW"].flatMap { $0.isNull ? nil : $0.int }
            if ten >= 13, gap > 0.06 || week - lastRaise >= 52, askW == nil || askW == 0 || week - askW! >= 13, m.noticeWeeks == 0 { return .payAsk(staffID: m.id) }
            let fixAsk = m.raw["fixAskW"].flatMap { $0.isNull ? nil : $0.int }
            if m.payBasis == "hour", (m.weeklyHours ?? 0) == 0, !m.flag("seas"), ten >= 26, skill(m, n, salesRoles: salesRoles) >= 55, !m.flag("flag") && m.raw["flag"] == nil,
               wantsFixedSalary(n), fixAsk == nil || fixAsk == 0 || week - fixAsk! >= 26 { return .fixedSalaryAsk(staffID: m.id) }
        }
        return ContractTalk.requestTrigger(m, n, company: co, week: week, salesRoles: salesRoles, tenure: ten)
    }

    static let maxAsksPerWeek = 2
    static func askedThisWeek(_ s: GameState, companyID: Int) -> Int {
        s.inbox.filter { $0.companyID == companyID && $0.actionID == "staffx" && $0.week == s.week }.count
    }

    static func ask(_ s: inout GameState, companyIndex i: Int, staffID: Int, fixed: Bool, data: GameData) {
        ContractTalk.employeeAsks(&s, companyIndex: i, staffID: staffID, topic: fixed ? .payBasis : .payRise, data: data)
    }

    public static func keptPromiseRaise(_ s: inout GameState, companyIndex i: Int, staffID: Int, percent: Double, data: GameData) {
        raise(&s, companyIndex: i, staffID: staffID, percent: percent, data: data)
    }

    public static func raise(_ s: inout GameState, companyIndex i: Int, staffID: Int, percent: Double, data: GameData) {
        guard let k = s.companies[i].staff.firstIndex(where: { $0.id == staffID }), let n = s.people[staffID] else { return }
        let w = World(state: s, data: data)
        let cur = w.currency(s.companies[i])
        var staff = s.companies[i].staff
        var m = staff[k]
        let need = raiseNeeded(role: m.role, tables: data.catalog.tables)
        m.monthlyWage = (m.weeklyHours ?? 0) != 0 ? m.monthlyWage * (1 + percent) : cur.roundedStep(m.monthlyWage * (1 + percent), about: 100)
        if m.commissionMode == nil || m.commissionMode == "fix" {
            m.monthlyWage = max(m.monthlyWage, w.minimumWage(s.companies[i], hours: m.weeklyHours ?? StaffModel.fullWeekHours))
        }
        m.set("denied", 0)
        if percent >= need {
            m.lastRaiseWeek = s.week
            m.happyUntilWeek = max(m.happyUntilWeek, s.week + (percent >= need * 1.6 ? 52 : 30))
            if m.noticeWeeks > 0 {
                m.noticeWeeks = 0
                s.note("\(n.name) will stay after the raise.", tone: "good", companyID: s.companies[i].id)
            }
        } else {
            m.lastRaiseWeek = s.week - (percent >= need * 0.5 ? 26 : 39)
        }
        staff[k] = m
        s.companies[i].staff = staff
        StaffPromises.noticeChange(&s, companyID: s.companies[i].id)
    }

    static func setFixedPay(_ s: inout GameState, companyIndex i: Int, staffID: Int, data: GameData) {
        guard let k = s.companies[i].staff.firstIndex(where: { $0.id == staffID }) else { return }
        let cur = World(state: s, data: data).currency(s.companies[i])
        var staff = s.companies[i].staff
        var m = staff[k]
        if (m.weeklyHours ?? 0) != 0 || m.flag("seas") { return }
        let wh = m.num("wh")
        if wh != 0 {
            m.monthlyWage = cur.roundedStep(m.monthlyWage * StaffModel.fullWeekHours / wh, about: 100)
            m.raw.removeValue(forKey: "wh"); m.raw.removeValue(forKey: "pt")
        }
        m.payBasis = "fix"
        staff[k] = m
        s.companies[i].staff = staff
    }

    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData) {
        guard let i = s.companyIndex(m.companyID) else { return }
        let d = m.value("data")
        let sid = d["sid"].int
        guard s.companies[i].staff.contains(where: { $0.id == sid }) else { return }
        if d["t"].string == "raise" {
            if idx == 0, let k = s.companies[i].staff.first(where: { $0.id == sid }) { raise(&s, companyIndex: i, staffID: sid, percent: max(0, d["w"].double / k.monthlyWage - 1), data: data) }
            else { markDenied(&s, companyIndex: i, staffID: sid) }
        } else if ["payask", "fixask", "promoask", "hoursask"].contains(d["t"].string) {
            ContractTalk.answerMessage(&s, message: m, option: idx, data: data)
        }
    }

    static func markDenied(_ s: inout GameState, companyIndex i: Int, staffID: Int) {
        guard let k = s.companies[i].staff.firstIndex(where: { $0.id == staffID }) else { return }
        var st = s.companies[i].staff; st[k].set("denied", s.week); s.companies[i].staff = st
    }
}
