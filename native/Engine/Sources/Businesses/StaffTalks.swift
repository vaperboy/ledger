import Foundation
import GameCore
import Countries
import Employees

/// Pay talks: people ask for a raise when their pay has fallen behind or a year has passed, and good hourly workers ask for a fixed
/// salary. Originals: `raiseFelt`, `raiseStaff`, `setFixedPay`, `wantsFix`, `ACTS.staffx` and the 'payask' / 'fixask' parts of
/// `handleStaffEvent` (engine/people/people.js, staff_extras.js).
public enum StaffTalks {
    /// The raise that feels like a raise: most people shrug at 3 %, 6 % is noticed; younger people in lower-paid jobs feel a smaller one.
    public static func raiseNeeded(role: String, age: Int, tables: TradeTables) -> Double {
        let base = tables.roles[role]?.baseMonthlyWage ?? 50000
        var need = base >= 70000 ? 0.07 : 0.06
        if age < 26 { need = base < 45000 ? 0.03 : 0.04 } else if age < 30 { need -= 0.01 }
        return need
    }

    /// Some people want a fixed salary, some prefer hours. Stable per person. Original: `wantsFix`.
    static func wantsFixedSalary(_ n: Person) -> Bool { HashedRandom.first("fix:\(n.id)") < (n.age < 26 ? 0.55 : 0.8) }

    /// Skill including what they have learned, minus the "not rested" penalty, plus the lift of commission. Original: `staffSkill`.
    static func skill(_ m: StaffMember, _ n: Person, salesRoles: Set<String>) -> Double {
        var v = n.skill + m.skillGain - (m.num("nr") > 0 ? 10 : 0)
        if let mode = m.commissionMode, salesRoles.contains(m.role) { v += mode == "com" ? 9 : mode == "mix" ? 4 : 0 }
        return clamp(v, 0, 100)
    }

    // MARK: Asking

    /// Should this person ask something this week? Returns the kind of talk. Original: inside `staffWeek`.
    static func nextTalk(_ m: StaffMember, _ n: Person, company co: Company, gap: Double, tenure ten: Double, week: Int, salesRoles: Set<String>) -> StaffEvent? {
        guard co.managerID == nil else { return nil }
        let lastRaise = m.raw["lr"].map { $0.isNull ? m.hiredWeek : $0.int } ?? m.hiredWeek
        let askW = m.raw["askW"].flatMap { $0.isNull ? nil : $0.int }
        if ten >= 13, gap > 0.06 || week - lastRaise >= 52, askW == nil || askW == 0 || week - askW! >= 13, m.noticeWeeks == 0 { return .payAsk(staffID: m.id) }
        let fixAsk = m.raw["fixAskW"].flatMap { $0.isNull ? nil : $0.int }
        if m.payBasis == "hour", (m.weeklyHours ?? 0) == 0, !m.flag("seas"), ten >= 26, skill(m, n, salesRoles: salesRoles) >= 55, !m.flag("flag") && m.raw["flag"] == nil,
           wantsFixedSalary(n), fixAsk == nil || fixAsk == 0 || week - fixAsk! >= 26 { return .fixedSalaryAsk(staffID: m.id) }
        return nil
    }

    static func ask(_ s: inout GameState, companyIndex i: Int, staffID: Int, fixed: Bool, data: GameData) {
        guard let k = s.companies[i].staff.firstIndex(where: { $0.id == staffID }), let n = s.people[staffID] else { return }
        var staff = s.companies[i].staff
        let m = staff[k]
        let co = s.companies[i]
        let w = World(state: s, data: data)
        let cur = w.currency(co)
        let roleName = data.catalog.tables.roles[m.role]?.name ?? m.role
        if fixed {
            staff[k].set("fixAskW", s.week); s.companies[i].staff = staff
            s.addMessage(kind: "ask", from: n.name, title: "\(n.name) asks for a fixed salary at \(co.name)",
                         body: "I have been here \(Int(jsRound(Double(s.week - m.hiredWeek) / 4.35))) months and the work goes well. I would like a fixed monthly salary instead of being paid by the hour, so I know what comes in each month.",
                         companyID: co.id, tone: "n", status: "open",
                         options: [.option("Fixed salary", "\(cur.format(cur.roundedStep(m.monthlyWage, about: 100)))/month, a full week"), .option("Keep it hourly", "Disappointed")],
                         action: "staffx", data: .object(["t": "fixask", "sid": .number(Double(staffID))]), expiresWeek: s.week + 3)
            return
        }
        staff[k].set("askW", s.week); s.companies[i].staff = staff
        let lastRaise = m.raw["lr"].map { $0.isNull ? m.hiredWeek : $0.int } ?? m.hiredWeek
        let years = (s.week - lastRaise) / 52
        let need = raiseNeeded(role: m.role, age: n.age, tables: data.catalog.tables)
        let big = max(need, 0.06), small = 0.03
        let why = s.week - lastRaise >= 52
            ? "It has been \(years > 1 ? "\(years) years" : "a year") since my last raise."
            : "I have looked around, and people doing my job earn more."
        s.addMessage(kind: "ask", from: n.name, title: "\(n.name) asks about pay at \(co.name)",
                     body: "\(why) I like it here and would like to stay. Could we look at my pay? (\(roleName))",
                     companyID: co.id, tone: "n", status: "open",
                     options: [.option("+\(Int(jsRound(big * 100)))%", "+\(cur.format(m.monthlyWage * big))/month"),
                               .option("+\(Int(jsRound(small * 100)))%", "+\(cur.format(m.monthlyWage * small))/month"),
                               .option("Not now", "Disappointed. They may start looking around.")],
                     action: "staffx", data: .object(["t": "payask", "sid": .number(Double(staffID)), "big": .number(big), "small": .number(small)]), expiresWeek: s.week + 3)
    }

    // MARK: Answering

    /// Give a raise. Original: `raiseStaff`.
    public static func raise(_ s: inout GameState, companyIndex i: Int, staffID: Int, percent: Double, data: GameData) {
        guard let k = s.companies[i].staff.firstIndex(where: { $0.id == staffID }), let n = s.people[staffID] else { return }
        let w = World(state: s, data: data)
        let cur = w.currency(s.companies[i])
        var staff = s.companies[i].staff
        var m = staff[k]
        let need = raiseNeeded(role: m.role, age: n.age, tables: data.catalog.tables)
        m.monthlyWage = (m.weeklyHours ?? 0) != 0 ? m.monthlyWage * (1 + percent) : cur.roundedStep(m.monthlyWage * (1 + percent), about: 100)
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
    }

    /// Move a full-timer to a fixed salary. Original: `setFixedPay`.
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

    /// The player's answer to "asks about pay" / "asks for a fixed salary". Original: `ACTS.staffx`.
    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData) {
        guard let i = s.companyIndex(m.companyID) else { return }
        let d = m.value("data")
        let sid = d["sid"].int
        guard s.companies[i].staff.contains(where: { $0.id == sid }) else { return }
        if d["t"].string == "payask" {
            if idx == 0 || idx == 1 { raise(&s, companyIndex: i, staffID: sid, percent: idx == 0 ? d["big"].double : d["small"].double, data: data) }
            else { markDenied(&s, companyIndex: i, staffID: sid) }
        } else if d["t"].string == "fixask" {
            if idx == 0 {
                setFixedPay(&s, companyIndex: i, staffID: sid, data: data)
                if let k = s.companies[i].staff.firstIndex(where: { $0.id == sid }) {
                    var st = s.companies[i].staff; st[k].happyUntilWeek = max(st[k].happyUntilWeek, s.week + 26); s.companies[i].staff = st
                }
            } else { markDenied(&s, companyIndex: i, staffID: sid) }
        }
    }

    static func markDenied(_ s: inout GameState, companyIndex i: Int, staffID: Int) {
        guard let k = s.companies[i].staff.firstIndex(where: { $0.id == staffID }) else { return }
        var st = s.companies[i].staff; st[k].set("denied", s.week); s.companies[i].staff = st
    }
}
