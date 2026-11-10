import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum StaffPromises {
    public enum Kind: String, CaseIterable, Sendable {
        case salaryReview, promotion, responsibility, training, betterConditions, futureBenefits, percentageChange
        public var title: String {
            switch self {
            case .salaryReview: return "Salary review"
            case .promotion: return "Promotion"
            case .responsibility: return "Additional responsibility"
            case .training: return "Training"
            case .betterConditions: return "Better conditions"
            case .futureBenefits: return "Future benefits"
            case .percentageChange: return "Change of working percentage"
            }
        }
        public var fulfilledByForGroup: String {
            switch self {
            case .salaryReview: return "A pay review: their pay is raised."
            case .promotion: return "A promotion: one more level of authority and a raise."
            case .responsibility: return "More authority: their level of authority is raised."
            case .training: return "A course is arranged and paid for."
            case .betterConditions: return "A reimbursement (phone, uniform, training, travel) is agreed for them."
            case .futureBenefits: return "The named reimbursement is agreed for them."
            case .percentageChange: return "Their working percentage reaches the agreed one, and pay follows."
            }
        }
        public var fulfilledBy: String {
            switch self {
            case .salaryReview: return "A raise is given."
            case .promotion: return "They are promoted."
            case .responsibility: return "They are given more duties or a lead role."
            case .training: return "They are sent on a course."
            case .betterConditions: return "A perk, a bonus plan or an expense reimbursement is added for them."
            case .futureBenefits: return "The named benefit is switched on for them."
            case .percentageChange: return "Their working percentage reaches the agreed one."
            }
        }
    }

    public enum Status: String, Sendable { case pending = "Pending", due = "Due", fulfilled = "Fulfilled", broken = "Broken", renegotiated = "Renegotiated" }

    public struct Draft: Equatable, Sendable {
        public var kind: Kind
        public var dueInWeeks: Int
        public var detail: String
        public init(_ kind: Kind, dueInWeeks: Int, detail: String = "") { self.kind = kind; self.dueInWeeks = dueInWeeks; self.detail = detail }
        public var isPlausible: Bool {
            guard (1...156).contains(dueInWeeks) else { return false }
            switch kind {
            case .futureBenefits: return StaffPromises.benefit(detail) != nil
            case .percentageChange: return Hiring.workingPercentRange.contains(Double(detail) ?? 0)
            default: return true
            }
        }
    }

    public struct Promise: Equatable, Sendable, Identifiable {
        public var id: Int
        public var personID: Int
        public var companyID: Int
        public var kind: Kind
        public var text: String
        public var detail: String
        public var madeWeek: Int
        public var dueWeek: Int
        public var status: Status
        public var resolvedWeek: Int?
        public var renegotiations: Int
        public var madeDate: GameCalendar.Date { GameCalendar.date(week: madeWeek) }
        public var dueDate: GameCalendar.Date { GameCalendar.date(week: dueWeek) }
        public var consequence: String
        public var isOpen: Bool { status == .pending || status == .due }
    }

    public static let graceWeeks = 4
    static let keep = 12
    static let key = "prm"

    enum Benefit: Equatable { case perk(String), plan(String), expense(String) }
    static func benefit(_ detail: String) -> Benefit? {
        if detail.hasPrefix("perk:"), StaffPerks.perk(String(detail.dropFirst(5))) != nil { return .perk(String(detail.dropFirst(5))) }
        if detail.hasPrefix("plan:"), let l = WorkerBonus.level(String(detail.dropFirst(5))), !l.isNone { return .plan(l.id) }
        if detail.hasPrefix("exp:"), StaffExpenses.item(String(detail.dropFirst(4))) != nil { return .expense(String(detail.dropFirst(4))) }
        return nil
    }

    static func text(for d: Draft, now: Int) -> String {
        let by = GameCalendar.dateString(week: now + d.dueInWeeks)
        switch d.kind {
        case .salaryReview: return "A salary review by \(by)."
        case .promotion: return "A promotion by \(by)."
        case .responsibility: return "More responsibility by \(by)."
        case .training: return "Training by \(by)."
        case .betterConditions: return "Better working conditions by \(by)."
        case .futureBenefits:
            let name: String
            switch benefit(d.detail) {
            case .perk(let id)?: name = StaffPerks.perk(id)?.name ?? id
            case .plan(let id)?: name = WorkerBonus.level(id)?.name ?? id
            case .expense(let id)?: name = StaffExpenses.item(id)?.name ?? id
            case nil: name = "a benefit"
            }
            return "\(name) by \(by)."
        case .percentageChange: return "A working percentage of \(d.detail) percent by \(by)."
        }
    }

    struct Baseline {
        var unitWage = 0.0, role = "", promo = 0, k11Week = 0, duties = 0, courses = 0, conditions = 0, lvl = 0
    }

    static func unitWage(_ m: StaffMember) -> Double { m.monthlyWage / max(0.05, m.partTimeShare) }

    static func conditions(_ co: Company, personID: Int) -> Int {
        if co.managerID == personID { return StaffPerks.onPerks(co).filter { StaffPerks.coversManager(co, $0) }.count }
        guard let m = co.staff.first(where: { $0.id == personID }) else { return 0 }
        return StaffPerks.perks(for: m, in: co).count + (WorkerBonus.level(of: m) == nil ? 0 : 1) + StaffExpenses.on(m).count + (m.flag("ownCar") ? 1 : 0)
    }

    static func isGroup(_ s: GameState, companyID: Int, personID: Int) -> Bool {
        if let co = s.company(companyID), co.managerID == personID || co.staff.contains(where: { $0.id == personID }) { return false }
        return GroupPeople.isGroupPerson(s, personID)
    }

    static func baseline(_ s: GameState, companyID: Int, personID: Int) -> Baseline {
        var b = Baseline()
        if isGroup(s, companyID: companyID, personID: personID), let n = s.people[personID] {
            b.unitWage = (GroupPeople.wage(s, personID: personID) ?? 0) / max(0.05, GroupPeople.percent(s, personID: personID) / 100)
            b.promo = n.int("gpro"); b.courses = n.int("crsN"); b.conditions = GroupPeople.expenseItems(s, personID: personID).count
            b.lvl = GroupPeople.level(s, personID: personID); b.k11Week = n.value("k11")["w0"].int
            return b
        }
        guard let co = s.company(companyID) else { return b }
        if let m = co.staff.first(where: { $0.id == personID }) { b.unitWage = unitWage(m); b.role = m.role; b.promo = m.int("promo"); b.courses = m.int("crsN") }
        else if co.managerID == personID { b.unitWage = co.managerMonthlyWage }
        b.conditions = conditions(co, personID: personID)
        let k = s.people[personID]?.value("k11") ?? .null
        b.k11Week = k["w0"].int; b.duties = k["duties"].array.count
        return b
    }

    static func decode(_ v: JSONValue, personID: Int) -> (Promise, Baseline)? {
        guard let kind = Kind(rawValue: v["k"].string), let status = Status(rawValue: v["s"].string) else { return nil }
        var b = Baseline()
        let bv = v["b"]
        b.unitWage = bv["u"].double; b.role = bv["r"].string; b.promo = bv["p"].int; b.k11Week = bv["w"].int; b.duties = bv["d"].int; b.courses = bv["c"].int; b.conditions = bv["n"].int; b.lvl = bv["l"].int
        let p = Promise(id: v["id"].int, personID: personID, companyID: v["co"].int, kind: kind, text: v["t"].string, detail: v["x"].string, madeWeek: v["m"].int, dueWeek: v["d"].int,
                        status: status, resolvedWeek: v["r"].isNull ? nil : v["r"].int, renegotiations: v["n"].int, consequence: "")
        return (p, b)
    }

    static func encode(_ p: Promise, _ b: Baseline) -> JSONValue {
        var o: [String: JSONValue] = ["id": .number(Double(p.id)), "co": .number(Double(p.companyID)), "k": .string(p.kind.rawValue), "t": .string(p.text), "x": .string(p.detail),
                                      "m": .number(Double(p.madeWeek)), "d": .number(Double(p.dueWeek)), "s": .string(p.status.rawValue),
                                      "b": .object(["u": .number(b.unitWage), "r": .string(b.role), "p": .number(Double(b.promo)), "w": .number(Double(b.k11Week)), "d": .number(Double(b.duties)),
                                                    "c": .number(Double(b.courses)), "n": .number(Double(b.conditions)), "l": .number(Double(b.lvl))])]
        if let r = p.resolvedWeek { o["r"] = .number(Double(r)) }
        if p.renegotiations > 0 { o["n"] = .number(Double(p.renegotiations)) }
        return .object(o)
    }

    static func records(_ n: Person) -> [(Promise, Baseline)] { n.value(key).array.compactMap { decode($0, personID: n.id) } }

    static func store(_ list: [(Promise, Baseline)], _ s: inout GameState, personID: Int) {
        guard var n = s.people[personID] else { return }
        let open = list.filter { $0.0.isOpen }, done = list.filter { !$0.0.isOpen }.suffix(max(0, keep - open.count))
        let merged = (open + done).sorted { $0.0.id < $1.0.id }
        if merged.isEmpty { n.raw.removeValue(forKey: key) } else { n.set(key, .array(merged.map { encode($0.0, $0.1) })) }
        s.people[personID] = n
    }

    static func describe(_ p: Promise, name: String) -> String {
        let first = ManagerModelNames.first(name)
        switch p.status {
        case .pending: return "\(first) is counting on it. Keeping it makes them glad; breaking it makes them feel let down and more likely to look elsewhere."
        case .due: return "\(first) is waiting for it now. If it does not happen soon they will feel let down."
        case .fulfilled: return "Kept. \(first) trusts the company's word a little more."
        case .broken: return "Not kept. \(first) feels let down, is more likely to look for another job and will not take changes to the contract easily; the company's word is doubted."
        case .renegotiated: return "Replaced by a new date that \(first) agreed to."
        }
    }

    @discardableResult
    public static func make(_ s: inout GameState, companyID: Int, personID: Int, draft d: Draft) -> Promise? {
        guard d.isPlausible, let n = s.people[personID] else { return nil }
        if isGroup(s, companyID: companyID, personID: personID) {
            if d.kind == .futureBenefits, case .expense? = benefit(d.detail) {} else if d.kind == .futureBenefits { return nil }
        } else {
            guard let co = s.company(companyID),
                  co.managerID == personID || co.staff.contains(where: { $0.id == personID }) || n.employerID == companyID || n.employerID == 0 else { return nil }
        }
        var list = records(n)
        if list.contains(where: { $0.0.isOpen && $0.0.kind == d.kind && $0.0.detail == d.detail }) { return nil }
        var b = baseline(s, companyID: companyID, personID: personID)
        if n.employerID == 0 {
            b = Baseline()
        }
        let id = s.makeID()
        var p = Promise(id: id, personID: personID, companyID: companyID, kind: d.kind, text: text(for: d, now: s.week), detail: d.detail, madeWeek: s.week, dueWeek: s.week + d.dueInWeeks,
                        status: .pending, resolvedWeek: nil, renegotiations: 0, consequence: "")
        p.consequence = describe(p, name: n.name)
        list.append((p, b))
        store(list, &s, personID: personID)
        return p
    }

    static func rebase(_ s: inout GameState, companyID: Int, personID: Int) {
        guard let n = s.people[personID] else { return }
        let b = baseline(s, companyID: companyID, personID: personID)
        let list = records(n).map { ($0.0.isOpen ? ($0.0, b) : $0) }
        store(list, &s, personID: personID)
    }

    static func isKeptForGroup(_ p: Promise, _ b: Baseline, _ s: GameState, _ n: Person) -> Bool {
        switch p.kind {
        case .salaryReview: return b.unitWage > 0 && (GroupPeople.wage(s, personID: p.personID) ?? 0) / max(0.05, GroupPeople.percent(s, personID: p.personID) / 100) >= b.unitWage * 1.02
        case .promotion: return n.int("gpro") > b.promo || (n.value("k11")["w0"].int > b.k11Week && n.value("k11")["w0"].int >= p.madeWeek)
        case .responsibility: return GroupPeople.level(s, personID: p.personID) > b.lvl || n.int("gpro") > b.promo
        case .training: return n.int("crsN") > b.courses
        case .betterConditions: return GroupPeople.expenseItems(s, personID: p.personID).count > b.conditions
        case .futureBenefits:
            if case .expense(let id)? = benefit(p.detail) { return GroupPeople.expenseItems(s, personID: p.personID).contains(id) }
            return false
        case .percentageChange: return Double(p.detail).map { abs(GroupPeople.percent(s, personID: p.personID) - $0) < 0.6 } ?? false
        }
    }

    static func isKept(_ p: Promise, _ b: Baseline, _ s: GameState) -> Bool {
        if let n = s.people[p.personID], isGroup(s, companyID: p.companyID, personID: p.personID) { return isKeptForGroup(p, b, s, n) }
        guard let co = s.company(p.companyID), let n = s.people[p.personID] else { return false }
        let m = co.staff.first(where: { $0.id == p.personID })
        let k11 = n.value("k11")
        switch p.kind {
        case .salaryReview:
            let now = m.map { unitWage($0) } ?? (co.managerID == p.personID ? co.managerMonthlyWage : b.unitWage)
            return b.unitWage > 0 && now >= b.unitWage * 1.02
        case .promotion:
            return (m?.int("promo") ?? 0) > b.promo || (k11["w0"].int > b.k11Week && k11["w0"].int >= p.madeWeek) || (m != nil && m!.role != b.role && b.role != "" && m!.role == "lead")
        case .responsibility:
            return (m?.role == "lead" && b.role != "lead") || (k11["w0"].int > b.k11Week && k11["w0"].int >= p.madeWeek && (k11["duties"].array.count > b.duties || k11["duties"].array.count > 0))
                || (m?.int("promo") ?? 0) > b.promo
        case .training:
            return (m?.int("crsN") ?? 0) > b.courses
        case .betterConditions:
            return conditions(co, personID: p.personID) > b.conditions
        case .futureBenefits:
            guard let ben = benefit(p.detail) else { return false }
            switch ben {
            case .perk(let id):
                guard let perk = StaffPerks.perk(id) else { return false }
                if let m { return StaffPerks.covers(co, perk, member: m) }
                return StaffPerks.coversManager(co, perk)
            case .plan(let id): return m.map { WorkerBonus.level(of: $0)?.id == id } ?? false
            case .expense(let id): return m.map { StaffExpenses.isOn($0, id) } ?? false
            }
        case .percentageChange:
            guard let m, let target = Double(p.detail) else { return false }
            return abs(EmploymentContract.percent(m) - target) < 0.6
        }
    }

    public static func noticeChange(_ s: inout GameState, companyID: Int) {
        let ids = s.people.values.filter { $0.raw[key] != nil && ($0.employerID == companyID || records($0).contains { $0.0.isOpen && $0.0.companyID == companyID }) }.map { $0.id }
        for id in ids { resolve(&s, personID: id, weekly: false) }
    }

    static func resolve(_ s: inout GameState, personID: Int, weekly: Bool) {
        guard let n = s.people[personID] else { return }
        var list = records(n)
        var changed = false
        for i in list.indices where list[i].0.isOpen {
            var p = list[i].0
            let b = list[i].1
            if p.companyID != 0, s.company(p.companyID) == nil { continue }
            if isKept(p, b, s) {
                p.status = .fulfilled; p.resolvedWeek = s.week
                list[i].0 = p; changed = true
                kept(&s, p, n)
                continue
            }
            guard weekly else { continue }
            if p.status == .pending, s.week >= p.dueWeek {
                p.status = .due; changed = true
                s.addMessage(kind: "info", from: n.name, title: "\(ManagerModelNames.first(n.name)) is waiting for what you promised",
                             body: "You promised: \(p.text) It is due now. \(isGroup(s, companyID: p.companyID, personID: personID) ? p.kind.fulfilledByForGroup : p.kind.fulfilledBy) Keep it, or ask to move the date in the Promises list.", companyID: p.companyID, tone: "n", status: "done",
                             data: .object(["promise": .number(Double(p.id)), "pid": .number(Double(personID))]))
                list[i].0 = p
            } else if p.status == .due, s.week >= p.dueWeek + graceWeeks {
                p.status = .broken; p.resolvedWeek = s.week
                list[i].0 = p; changed = true
                broken(&s, p, n)
            }
        }
        if changed {
            for i in list.indices { list[i].0.consequence = "" }
            store(list, &s, personID: personID)
        }
    }

    static func kept(_ s: inout GameState, _ p: Promise, _ n: Person) {
        s.note("\(n.name) was promised \(p.kind.title.lowercased()) and got it.", tone: "good", companyID: p.companyID)
        MarketEvents.log(&s, .recognition, title: "\(n.name): promise kept", detail: "\(p.kind.title) was promised and delivered.", companyID: p.companyID, tone: "good", employeeID: p.personID)
        if let ci = s.companyIndex(p.companyID) {
            if let k = s.companies[ci].staff.firstIndex(where: { $0.id == p.personID }) {
                var st = s.companies[ci].staff
                st[k].happyUntilWeek = max(st[k].happyUntilWeek, s.week + 26)
                s.companies[ci].staff = st
            }
            var t = s.companies[ci].value("ptr")
            var ks = t["k"].array; ks.append(.number(Double(s.week))); if ks.count > 8 { ks.removeFirst(ks.count - 8) }
            t["k"] = .array(ks)
            s.companies[ci].set("ptr", t)
        }
    }

    static func broken(_ s: inout GameState, _ p: Promise, _ n: Person) {
        s.note("\(n.name) was promised \(p.kind.title.lowercased()) and feels let down.", tone: "bad", companyID: p.companyID)
        if let ci = s.companyIndex(p.companyID) {
            if let k = s.companies[ci].staff.firstIndex(where: { $0.id == p.personID }) {
                var st = s.companies[ci].staff
                st[k].set("denied", s.week)
                st[k].happyUntilWeek = 0
                st[k].set("broke", s.week)
                s.companies[ci].staff = st
            } else if s.companies[ci].managerID == p.personID {
                ManagerModel.declineManagerRaise(&s, companyIndex: ci)
            }
            var t = s.companies[ci].value("ptr")
            var bs = t["b"].array; bs.append(.number(Double(s.week))); if bs.count > 8 { bs.removeFirst(bs.count - 8) }
            t["b"] = .array(bs)
            s.companies[ci].set("ptr", t)
        }
    }

    static func record(_ co: Company, week: Int) -> (kept: Int, broken: Int) {
        let t = co.value("ptr")
        return (t["k"].array.filter { week - $0.int < 52 }.count, t["b"].array.filter { week - $0.int < 52 }.count)
    }

    public static func letDown(_ m: StaffMember, week: Int) -> Bool { m.value("broke").isNull ? false : week - m.int("broke") < 52 }

    public enum RenegotiateResult: Equatable, Sendable { case agreed(String), refused(String), notPossible(String) }

    public static func renegotiate(_ s: inout GameState, personID: Int, promiseID: Int, newDueInWeeks: Int) -> RenegotiateResult {
        guard let n = s.people[personID] else { return .notPossible("This person is gone.") }
        var list = records(n)
        guard let i = list.firstIndex(where: { $0.0.id == promiseID && $0.0.isOpen }) else { return .notPossible("That promise is not open.") }
        guard (1...156).contains(newDueInWeeks) else { return .notPossible("Choose a date between a week and three years away.") }
        let old = list[i].0
        guard old.renegotiations == 0 else { return .refused("\(ManagerModelNames.first(n.name)) has already agreed to move the date once and will not do it again.") }
        let t = Hiring.temperament(of: n)
        var likelihood = ["flexible": 0.1, "steady": 0.3, "stubborn": 0.6, "greedy": 0.55][t.id] ?? 0.3
        if old.status == .due { likelihood += 0.15 }
        if let co = s.company(old.companyID), let m = co.staff.first(where: { $0.id == personID }), letDown(m, week: s.week) { likelihood += 0.2 }
        if HashedRandom.first("renego:\(promiseID)") < likelihood {
            return .refused("\(ManagerModelNames.first(n.name)) wants it kept as promised and is not happy about the delay being asked for.")
        }
        var renewed = old
        renewed.id = s.makeID(); renewed.status = .pending; renewed.madeWeek = s.week; renewed.dueWeek = s.week + newDueInWeeks; renewed.renegotiations = 1
        renewed.text = old.text.replacingOccurrences(of: " by ", with: " (moved) by ", options: [], range: nil)
        if let r = old.text.range(of: " by ") { renewed.text = String(old.text[..<r.lowerBound]) + " by " + GameCalendar.dateString(week: s.week + newDueInWeeks) + " (moved)." }
        var closed = old
        closed.status = .renegotiated; closed.resolvedWeek = s.week
        let b = list[i].1
        list[i] = (closed, b)
        list.append((renewed, b))
        store(list, &s, personID: personID)
        if let ci = s.companyIndex(old.companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == personID }) {
            var st = s.companies[ci].staff
            st[k].happyUntilWeek = min(st[k].happyUntilWeek, s.week)
            s.companies[ci].staff = st
        }
        return .agreed("\(ManagerModelNames.first(n.name)) agrees to wait until \(GameCalendar.dateString(week: s.week + newDueInWeeks)).")
    }

    public static func weekly(_ s: inout GameState, data: GameData) {
        let ids = s.people.values.filter { $0.raw[key] != nil }.map { $0.id }.sorted()
        for id in ids {
            guard let n = s.people[id] else { continue }
            resolve(&s, personID: id, weekly: true)
            if let n2 = s.people[id] {
                var list = records(n2)
                let before = list.count
                list.removeAll { p, _ in
                    guard p.isOpen else { return false }
                    if isGroup(s, companyID: p.companyID, personID: id) { return n2.employerID == 0 || n2.employerID == Hiring.goneElsewhere }
                    guard let co = s.company(p.companyID) else { return false }
                    let still = co.managerID == id || co.staff.contains { $0.id == id } || n2.employerID == p.companyID || n2.employerID == 0
                    return !still
                }
                if list.count != before { store(list, &s, personID: id) }
            }
            _ = n
        }
        GroupPeople.weekly(&s, data: data)
    }

    public static func promises(_ s: GameState, personID: Int) -> [Promise] {
        guard let n = s.people[personID] else { return [] }
        return records(n).map { var p = $0.0; p.consequence = describe(p, name: n.name); return p }
    }

    public static func promises(_ s: GameState, companyID: Int) -> [Promise] {
        var out: [Promise] = []
        for n in s.people.values where n.raw[key] != nil {
            for r in records(n) where r.0.companyID == companyID {
                var p = r.0; p.consequence = describe(p, name: n.name); out.append(p)
            }
        }
        return out.sorted { a, b in a.isOpen != b.isOpen ? a.isOpen : (a.dueWeek != b.dueWeek ? a.dueWeek < b.dueWeek : a.id < b.id) }
    }
}

enum ManagerModelNames {
    static func first(_ name: String) -> String { name.split(separator: " ").first.map(String.init) ?? name }
}
