import Foundation
import GameCore
import Countries
import Employees

// Employment types: part time, seasonal, fixed salary, hours, pay model (an extension of the pay talks in StaffTalks.swift).
// Originals: `setStaffHours`, `workWish`, `wishWhy`, `offerFullTime`, `offerPartTime`, `weekHours`, `setPay`, `seasonsTurn`,
// `ACT.stseas/stpart/stfix/sthrs/stfull/setpay/setrate/carallow`, `HIRE_HOURS`/`HIRE_SEAS` (engine/people/people.js, features/people/*).
extension StaffTalks {
    /// The seasons a seasonal worker can sign up for, as months 1-12. Original: `R54.SEASONS`.
    public static let seasons: [(id: String, name: String, months: [Int])] = [
        ("winter", "Winter", [1, 2]), ("spring", "Spring", [3, 4, 5]), ("summer", "Summer", [6, 7, 8]), ("autumn", "Autumn", [9, 10]), ("xmas", "Christmas", [11, 12])]
    static let monthNames = ["", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    public enum OfferResult: Equatable, Sendable { case ok, already, student, refused, unknown }
    public enum PayModelResult: Equatable, Sendable { case ok, resigned, unknown }

    /// The months (1-12) as seasons in words. Original: `R54.seasText`.
    public static func seasonText(_ ms: [Int]) -> String {
        let full = seasons.filter { $0.months.allSatisfy(ms.contains) }
        let covered = Set(full.flatMap(\.months))
        let out = (full.map(\.name) + ms.filter { !covered.contains($0) }.map { monthNames[$0] }).joined(separator: ", ")
        return out.isEmpty ? "no months yet" : out
    }

    /// Months (1-12) in which the trade is busy: the ones a seasonal worker is for. Original: `R54.busyMonths`.
    public static func busyMonths(_ co: Company, data: GameData) -> [Int] {
        ManagerModel.seasonalBusyMonths(co, data: data)   // the trade's year with its own peak, as the original
    }

    static func month1(_ week: Int) -> Int { GameCalendar.month(week: week) + 1 }
    static func payFollowsHours(_ m: StaffMember) -> Bool { m.payBasis != "fix" && !(m.commissionMode != nil && m.commissionMode != "fix") }

    /// Pay and hours for a person hired part time or for a season. One in four studies and can work 20 or 30 h at most. Original: `hireWorker`.
    static func applyPartTime(_ m: inout StaffMember, terms: Hiring.Terms, week: Int) {
        var r = HashedRandom("stu:\(m.id)")
        if r.next() < 0.25 { m.set("maxH", r.next() < 0.5 ? 20 : 30) }
        m.payBasis = "hour"
        setHours(&m, min(terms.hours > 0 ? terms.hours : 30, m.num("maxH", 60)))
        if let ms = terms.seasonMonths {
            m.set("seas", .array(ms.map { .number(Double($0)) }))
            m.set("off", !ms.contains(month1(week)))
        }
        if m.role == "estate", terms.ownCar { m.set("ownCar", 1) }
    }

    /// Hours a week for a part-timer or seasonal worker; pay follows hours. Original: `setStaffHours`.
    @discardableResult
    static func setHours(_ m: inout StaffMember, _ h0: Double) -> Double {
        let h = max(5, min(m.num("maxH", 60), h0.rounded()))
        if payFollowsHours(m) { m.monthlyWage = m.monthlyWage * h / (m.weeklyHours ?? StaffModel.fullWeekHours) }
        m.weeklyHours = h
        m.partTimeShare = h / StaffModel.fullWeekHours
        return h
    }

    /// What work someone wants, stable per person: "season", "part" or "full". Original: `workWish`.
    static func workWish(_ m: inout StaffMember, week: Int) -> String {
        let yr = Int(floor(Double(week - m.hiredWeek) / 52))
        if m.str("wish").isEmpty {
            let r = HashedRandom.first("wish:\(m.id)")
            let seasonal = !m.value("seas").isNull
            m.set("wish", seasonal ? (r < 0.4 ? "season" : r < 0.65 ? "part" : "full") : (m.weeklyHours ?? 0) > 0 ? (r < 0.5 ? "part" : "full") : "full")
            m.set("wishY", yr)
        }
        if yr > m.int("wishY") {
            m.set("wishY", yr)
            if m.str("wish") != "full", HashedRandom.first("wish:\(m.id):\(yr)") < 0.3 { m.set("wish", m.str("wish") == "season" ? "part" : "full") }
        }
        if m.num("maxH", 999) < StaffModel.fullWeekHours, m.str("wish") == "full" { m.set("wish", "part") }
        return m.str("wish")
    }

    /// Why they say no, in words. Original: `wishWhy`.
    public static func wishWhy(_ m: StaffMember, name: String, want: String) -> String {
        let f = name.split(separator: " ").first.map(String.init) ?? "They", r = HashedRandom.first("why:\(m.id)")
        if m.num("maxH", 999) < StaffModel.fullWeekHours { return "\(f) studies and can work at most \(Int(m.num("maxH"))) h a week." }
        if want == "season" { return f + (r < 0.4 ? " has other work the rest of the year" : r < 0.7 ? " studies outside the season" : " likes having the rest of the year off") + " and only wants the seasonal work." }
        return f + (r < 0.4 ? " has small children at home" : r < 0.7 ? " has another job on the side" : " likes the shorter week")
            + (!m.value("seas").isNull ? " and would work part time all year, but not full time." : " and wants to stay part time.")
    }

    @discardableResult
    private static func edit(_ s: inout GameState, _ ci: Int, _ id: Int, _ f: (inout StaffMember) -> Void) -> Bool {
        guard let k = s.companies[ci].staff.firstIndex(where: { $0.id == id }) else { return false }
        var st = s.companies[ci].staff
        f(&st[k])
        s.companies[ci].staff = st
        return true
    }

    /// Set the weekly hours of a part-timer or seasonal worker. Original: `ACT.sthrs`.
    @discardableResult
    public static func setStaffHours(_ s: inout GameState, companyID: Int, staffID: Int, hours: Double) -> OfferResult {
        guard let ci = s.companyIndex(companyID), let m = s.companies[ci].staff.first(where: { $0.id == staffID }) else { return .unknown }
        if hours > m.num("maxH", 999) { return .student }
        edit(&s, ci, staffID) { setHours(&$0, hours) }
        return .ok
    }

    /// Ask a part-timer or seasonal worker to go full time; yes only if that is the work they want. Original: `offerFullTime`.
    public static func offerFullTime(_ s: inout GameState, companyID: Int, staffID: Int, data: GameData) -> OfferResult {
        guard let ci = s.companyIndex(companyID), let m0 = s.companies[ci].staff.first(where: { $0.id == staffID }) else { return .unknown }
        guard (m0.weeklyHours ?? 0) != 0 else { return .already }
        if m0.num("maxH", 999) < StaffModel.fullWeekHours { return .student }
        let cur = World(state: s, data: data).currency(s.companies[ci])
        var result = OfferResult.ok
        let week = s.week
        edit(&s, ci, staffID) { m in
            if workWish(&m, week: week) != "full" { m.set("wishNo", week); result = .refused; return }
            if payFollowsHours(m) { m.monthlyWage = cur.roundedStep(m.monthlyWage * StaffModel.fullWeekHours / (m.weeklyHours ?? StaffModel.fullWeekHours), about: 100) }
            for key in ["hrs", "pt", "maxH", "seas", "off", "wishNo"] { m.raw.removeValue(forKey: key) }
        }
        return result
    }

    /// Ask a seasonal worker to stay on all year, part time; yes unless they only want the season. Original: `offerPartTime`.
    public static func offerPartTime(_ s: inout GameState, companyID: Int, staffID: Int, hours: Double = 20) -> OfferResult {
        guard let ci = s.companyIndex(companyID), let m0 = s.companies[ci].staff.first(where: { $0.id == staffID }) else { return .unknown }
        guard !m0.value("seas").isNull else { return .already }
        var result = OfferResult.ok
        let week = s.week
        edit(&s, ci, staffID) { m in
            if workWish(&m, week: week) == "season" { m.set("wishNo", week); result = .refused; return }
            for key in ["seas", "off", "wishNo"] { m.raw.removeValue(forKey: key) }
            setHours(&m, min(hours > 0 ? hours : (m.weeklyHours ?? 20), m.num("maxH", 60)))
        }
        return result
    }

    /// Choose the months a seasonal worker works; the person is off and unpaid outside them. Original: `ACT.stseas`.
    @discardableResult
    public static func setSeasons(_ s: inout GameState, companyID: Int, staffID: Int, months: [Int]) -> Bool {
        guard let ci = s.companyIndex(companyID), !months.isEmpty else { return false }
        let week = s.week
        return edit(&s, ci, staffID) { m in
            guard !m.value("seas").isNull else { return }
            let ms = Array(Set(months)).sorted()
            m.set("seas", .array(ms.map { .number(Double($0)) }))
            m.set("off", !ms.contains(month1(week)))
        }
    }

    /// Toggle one season on or off in a seasonal worker's months (the chips of the staff screen).
    @discardableResult
    public static func toggleSeason(_ s: inout GameState, companyID: Int, staffID: Int, season id: String) -> Bool {
        guard let ci = s.companyIndex(companyID), let m = s.companies[ci].staff.first(where: { $0.id == staffID }),
              let sea = seasons.first(where: { $0.id == id }) else { return false }
        var ms = m.value("seas").array.map { $0.int }
        let all = sea.months.allSatisfy(ms.contains)
        ms = all ? ms.filter { !sea.months.contains($0) } : ms + sea.months.filter { !ms.contains($0) }
        return setSeasons(&s, companyID: companyID, staffID: staffID, months: ms)
    }

    /// Give a full-timer a fixed salary. Original: `ACT.stfix`.
    @discardableResult
    public static func offerFixedSalary(_ s: inout GameState, companyID: Int, staffID: Int, data: GameData) -> Bool {
        guard let ci = s.companyIndex(companyID), s.companies[ci].staff.contains(where: { $0.id == staffID }) else { return false }
        setFixedPay(&s, companyIndex: ci, staffID: staffID, data: data)
        let w = s.week
        return edit(&s, ci, staffID) { $0.happyUntilWeek = max($0.happyUntilWeek, w + 26) }
    }

    /// Pay model of a seller: fixed, fixed plus commission, commission only. Someone who wants security may refuse commission only
    /// and resign. Original: `setPay`, `ACT.setpay`.
    @discardableResult
    public static func setPayModel(_ s: inout GameState, companyID: Int, staffID: Int, mode: String, data: GameData) -> PayModelResult {
        guard let ci = s.companyIndex(companyID), let m0 = s.companies[ci].staff.first(where: { $0.id == staffID }), let n = s.people[staffID] else { return .unknown }
        if mode == "com", n.num("sec") > 0.65, s.random.chance(0.6) {
            _ = Hiring.fire(staffID, from: companyID, state: &s, data: data, withCause: true)
            return .resigned
        }
        let rate = mode == "fix" ? 0.0 : mode == "mix" ? 0.03 : 0.06
        let cur = World(state: s, data: data).currency(s.companies[ci])
        let mk = cur.roundedStep(ManagerModel.marketWage(s, s.companies[ci], role: m0.role, data: data) * m0.partTimeShare * (0.7 + n.skill / 160), about: 100)
        edit(&s, ci, staffID) { m in
            m.monthlyWage = mode == "fix" ? max(m.monthlyWage, cur.roundedStep(mk * 0.95, about: 100)) : mode == "mix" ? cur.roundedStep(mk * 0.6, about: 100) : 0
            m.set("pay", .object(["m": .string(mode), "rate": .number(rate)]))
            m.set("commEma", 0)
        }
        return .ok
    }

    /// Commission share of a seller on a pay plan. Original: `ACT.setrate`.
    @discardableResult
    public static func setCommissionRate(_ s: inout GameState, companyID: Int, staffID: Int, rate: Double) -> Bool {
        guard let ci = s.companyIndex(companyID) else { return false }
        return edit(&s, ci, staffID) { m in
            var p = m.value("pay")
            guard !p.isNull else { return }
            p["rate"] = .number(rate)
            m.set("pay", p)
        }
    }

    /// Let an estate agent use their own car for work, paid by mileage, or give back the company car. Original: `ACT.carallow`.
    @discardableResult
    public static func toggleOwnCar(_ s: inout GameState, companyID: Int, staffID: Int) -> Bool {
        guard let ci = s.companyIndex(companyID) else { return false }
        return edit(&s, ci, staffID) { m in m.set("ownCar", m.num("ownCar") != 0 ? 0 : 1) }
    }

    /// Seasonal workers come back for their season and finish it. Original: `seasonsTurn` (features/people/seasons_and_hours.js).
    static func seasonsTurn(_ s: inout GameState, companyIndex i: Int) {
        let m1 = month1(s.week)
        var back: [Int] = [], gone: [Int] = []
        var staff = s.companies[i].staff
        for k in staff.indices {
            guard !staff[k].value("seas").isNull else { continue }
            let ms = staff[k].value("seas").array.map { $0.int }
            let on = ms.contains(m1), off = staff[k].isOffSeason
            if on && off { staff[k].set("off", false); back.append(staff[k].id) }
            else if !on && !off { staff[k].set("off", true); gone.append(staff[k].id) }
        }
        guard !back.isEmpty || !gone.isEmpty else { return }
        s.companies[i].staff = staff
        let co = s.companies[i]
        func nm(_ id: Int) -> String { s.people[id]?.name ?? "A seasonal worker" }
        if !back.isEmpty { s.note((back.count == 1 ? "\(nm(back[0])) is" : "\(back.count) seasonal workers are") + " back at \(co.name) for the season.", companyID: co.id) }
        if !gone.isEmpty {
            let ms = (staff.first { $0.id == gone[0] }?.value("seas").array ?? []).map { $0.int }
            let next = (1...12).map { (m1 - 1 + $0) % 12 + 1 }.first { ms.contains($0) }
            s.note((gone.count == 1 ? "\(nm(gone[0])) has" : "\(gone.count) seasonal workers have") + " finished the season at \(co.name) and will be back "
                   + (next.map { "in \(monthNames[$0])" } ?? "next year") + ".", companyID: co.id)
        }
    }
}
