import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum ManagerTargets {
    static let noFamily: Set<String> = ["fin", "energy", "rent", "club"]

    public struct Setter: Equatable, Sendable {
        public var kind: String
        public var name: String
        public var title: String
        public var quality: Double
        public var isOwner: Bool { kind == "you" }
    }

    public struct Standing: Equatable, Sendable {
        public var key: String
        public var target: Double
        public var now: Double
        public var onTrack: Bool
    }

    public static func eligible(_ co: Company, data: GameData) -> Bool {
        guard co.status == .open, co.type != "hold", let bd = data.catalog[co.type] else { return false }
        return !noFamily.contains(bd.family)
    }

    static func record(_ co: Company) -> JSONValue {
        let t = co.value("tg58")
        return t.isNull ? .object(["m": .null, "y": .null, "log": .array([]), "bad": .number(0)]) : t
    }
    static func put(_ s: inout GameState, _ ci: Int, _ t: JSONValue) { s.companies[ci].set("tg58", t) }
    static func mi(_ s: GameState) -> Int { GameCalendar.monthIndex(week: s.week) }
    static func month0(_ m: Int) -> Int { (((m - 1) % 12) + 12) % 12 }
    static func yearOf(_ m: Int) -> Int { (m - 1) / 12 }
    static func monthName(_ m: Int) -> String { GameCalendar.monthNames[month0(m)] }

    public static func current(_ co: Company, week: Int) -> JSONValue? {
        let m = record(co)["m"]
        guard !m.isNull, m["mi"].int == GameCalendar.monthIndex(week: week) else { return Optional<JSONValue>.none }
        return m
    }

    static func hasRating(_ co: Company) -> Bool { co.int("rvN") >= 10 }
    static func utilNow(_ co: Company) -> Double {
        let h = co.value("wh22").array.suffix(4).filter { !$0["u"].isNull }
        if !h.isEmpty { return h.reduce(0) { $0 + $1["u"].double } / Double(h.count) }
        return co.value("lastW")["util"].double
    }
    static func third(_ co: Company) -> String { hasRating(co) ? "rating" : utilNow(co) > 0.05 ? "util" : "aware" }
    static func now3(_ co: Company, _ k: String) -> Double { k == "rating" ? Reviews.rating(co) : k == "util" ? utilNow(co) : co.awareness }

    public static func setter(_ s: GameState, _ co: Company, data: GameData) -> Setter {
        if co.managerID != nil, let up = ManagerModel.decisionChain(s, co, data: data).first(where: { $0.kind != "mgr" }), let n = s.people[up.personID] {
            let sales = n.value("stats")["sales"].double
            let skill = sales != 0 ? sales : (n.num("skill") != 0 ? n.num("skill") : 55)
            return Setter(kind: up.kind, name: up.name, title: ManagerModel.titleFor(co, kind: up.kind, data: data, state: s), quality: clamp(skill / 100, 0.2, 1))
        }
        return Setter(kind: "you", name: "You", title: "Owner", quality: 1)
    }

    static func tilt(_ co: Company) -> (rev: Double, profit: Double, third: Double) {
        switch OwnerMeetings.directive(co) ?? "" {
        case "growth": return (0.06, -0.01, 0)
        case "lean": return (0, 0.08, 0)
        case "quality": return (0, 0, 1)
        case "cash": return (-0.02, 0.1, 0)
        default: return (0, 0, 0)
        }
    }

    struct LastYear { var rev: Double; var profit: Double; var h: [MonthRecord] }
    static func lastYear(_ co: Company) -> LastYear? {
        let h = Array(co.monthlyHistory.suffix(12).filter { $0.revenue > 0 })
        if h.count < 2 { return nil }
        let f = 12 / Double(h.count)
        return LastYear(rev: h.reduce(0) { $0 + $1.revenue } * f, profit: h.reduce(0) { $0 + $1.profit } * f, h: h)
    }
    static func shares(_ co: Company) -> [Double] {
        let even = [Double](repeating: 1.0 / 12, count: 12)
        guard let ly = lastYear(co), ly.h.count >= 12 else { return even }
        let tot = ly.h.reduce(0) { $0 + max(0, $1.revenue) }
        if tot <= 0 { return even }
        var sh = [Double](repeating: 0, count: 12)
        for x in ly.h { sh[month0(x.monthIndex)] += max(0, x.revenue) / tot }
        return sh.map { $0 * 0.7 + 0.3 / 12 }
    }
    struct Recent { var rev: Double; var profit: Double; var ann: Double; var margin: Double }
    static func recent(_ co: Company) -> Recent {
        let h = Array(co.monthlyHistory.filter { $0.revenue > 0 }.suffix(3)), sh = shares(co)
        let weights: [[Double]] = [[1], [0.4, 0.6], [0.2, 0.3, 0.5]]
        let w = weights[max(0, h.count - 1)]
        let ann = h.map { $0.revenue / max(0.02, sh[month0($0.monthIndex)]) }
        let tr: Double = ann.count > 1 && ann[0] > 0 ? clamp(pow(ann[ann.count - 1] / ann[0], 1 / Double(ann.count - 1)) - 1, -0.1, 0.1) : 0
        var a = 0.0
        for (i, v) in ann.enumerated() { a += v * w[i] }
        a *= 1 + tr * 0.5
        let rv = h.reduce(0) { $0 + $1.revenue }, pr = h.reduce(0) { $0 + $1.profit }, n = Double(max(1, h.count))
        return Recent(rev: rv / n * 3, profit: pr / n * 3, ann: a, margin: rv > 0 ? pr / rv : 0)
    }
    static func draft(_ s: GameState, _ co: Company, from m0: Int, data: GameData) -> (rev: Double, profit: Double, sh: [Double])? {
        guard let ly = lastYear(co) else { return nil }
        let r3 = recent(co), cur = World(state: s, data: data).currency(co)
        let q: Double = co.managerID != nil ? (data.catalog[co.type].map { ManagerModel.quality(co, $0, people: s.people) } ?? 0.5) : 0.5
        let g = clamp(0.04 + (q - 0.5) * 0.08 + (s.economy.demand - 1) * 0.5 + tilt(co).rev * 0.3, -0.06, 0.12)
        let sh = shares(co), left = sh[month0(m0)...].reduce(0, +)
        let base = ly.h.count >= 12 ? (ly.rev + r3.ann) / 2 : r3.ann
        let margin = r3.rev > 0 ? (r3.profit / r3.rev + (ly.rev > 0 ? ly.profit / ly.rev : 0)) / 2 : 0
        let rev = base * (1 + g) * left
        return (cur.roundedStep(rev, about: 1000), cur.roundedStep(rev * min(0.35, margin + 0.01), about: 1000), sh)
    }

    @discardableResult
    static func makeBudget(_ s: inout GameState, _ ci: Int, year yr: Int, data: GameData) -> JSONValue? {
        let co = s.companies[ci], monthEnd = GameCalendar.isMonthEnd(week: s.week)
        let m0 = max(mi(s) + (monthEnd ? 1 : 0), yr * 12 + 1)
        guard let d = draft(s, co, from: m0, data: data) else { return nil }
        let se = setter(s, co, data: data), cur = World(state: s, data: data).currency(co), managed = co.managerID != nil
        var rev = d.rev, profit = d.profit, by = managed ? se.kind : "acc", ok = 1
        if managed && !se.isOwner { let x = 0.02 + 0.05 * se.quality; rev = cur.roundedStep(d.rev * (1 + x), about: 1000); profit = cur.roundedStep(d.profit + abs(d.profit) * x * 1.5, about: 1000) }
        if managed && se.isOwner { if monthEnd && GameCalendar.isYearEnd(week: s.week) { ok = 0 } else { by = "draft" } }
        let y: JSONValue = .object(["yr": .number(Double(yr)), "m0": .number(Double(m0)), "rev": .number(rev), "profit": .number(profit), "sh": .array(d.sh.map { .number($0) }),
                                    "by": .string(by), "ok": .number(Double(ok)), "d0": .object(["rev": .number(d.rev), "profit": .number(d.profit)])])
        var t = record(co); t["y"] = y; put(&s, ci, t)
        return y
    }

    public static func yearToDate(_ co: Company, week: Int) -> (rev: Double, profit: Double)? {
        let y = record(co)["y"]
        if y.isNull { return nil }
        let now = GameCalendar.monthIndex(week: week), m0 = y["m0"].int, yr = y["yr"].int
        let h = co.monthlyHistory.filter { $0.monthIndex >= m0 && yearOf($0.monthIndex) == yr }
        let bm = co.books.month, inCurrent = now >= m0 && yearOf(now) == yr && !h.contains { $0.monthIndex == now }
        return (h.reduce(0) { $0 + $1.revenue } + (inCurrent ? bm["rev"] ?? 0 : 0),
                h.reduce(0) { $0 + $1.profit } + (inCurrent ? Books.profit(bm) : 0))
    }

    static func compute(_ s: GameState, _ co: Company, month m: Int, data: GameData) -> JSONValue? {
        guard let _ = lastYear(co) else { return nil }
        let t = record(co), y = t["y"], se = setter(s, co, data: data), cur = World(state: s, data: data).currency(co)
        let sh: [Double] = y["sh"].array.count == 12 ? y["sh"].array.map { $0.double } : shares(co)
        let r3 = recent(co), run = r3.ann * sh[month0(m)]
        let runP = r3.rev > 0 ? run * r3.margin : r3.profit / 3
        var bRev = run * 1.04, bProfit = runP + abs(runP) * 0.05
        if !y.isNull && yearOf(m) == y["yr"].int {
            let left = sh[month0(y["m0"].int)...].reduce(0, +), f = sh[month0(m)] / (left == 0 ? 1 : left)
            bRev = y["rev"].double * f; bProfit = y["profit"].double * f
        }
        let rev = (bRev + run * 1.02) / 2, profit = (bProfit + runP + abs(runP) * 0.03) / 2
        var x = 0.0
        if !se.isOwner { x = 0.01 + 0.03 * se.quality + (HashedRandom.first("\(s.seed):tg58:\(co.id):\(m)") - 0.5) * 0.16 * (1 - se.quality) }
        let tl = tilt(co)
        let k3 = third(co), n3 = now3(co, k3), up = tl.third
        let t3: Double
        if k3 == "rating" { t3 = min(4.8, floor(n3 * 10 + 1e-6) / 10 + (n3 < 3.6 ? 0.1 : 0) + 0.1 * up) }
        else if k3 == "util" { t3 = clamp(floor(n3 * 20 + 1e-6) / 20 + 0.05 * up, 0.1, 0.95) }
        else { t3 = min(95, floor(n3) + 1 + 2 * up) }
        return .object(["mi": .number(Double(m)), "by": .string(se.kind), "n": .string(se.name),
                        "T": .object(["rev": .number(cur.roundedStep(max(0, rev * (1 + x + tl.rev)), about: 1000)),
                                      "profit": .number(cur.roundedStep(profit + abs(profit) * (x + tl.profit) * 1.5, about: 1000)), k3: .number(t3)]),
                        "k3": .string(k3), "from3": .number(n3)])
    }
    @discardableResult
    static func setTargets(_ s: inout GameState, _ ci: Int, month m: Int, data: GameData) -> Bool {
        guard let v = compute(s, s.companies[ci], month: m, data: data) else { return false }
        var t = record(s.companies[ci]); t["m"] = v; put(&s, ci, t)
        return true
    }

    static func monthPart(week: Int) -> (done: Int, of: Int) {
        let m = GameCalendar.monthIndex(week: week)
        var a = week, b = week
        while GameCalendar.monthIndex(week: a - 1) == m { a -= 1 }
        while GameCalendar.monthIndex(week: b + 1) == m { b += 1 }
        return (week - a, b - a + 1)
    }

    public static func standing(_ co: Company, week: Int) -> [Standing] {
        guard let m = current(co, week: week) else { return [] }
        let bm = co.books.month, mp = monthPart(week: week), part = max(0.25, Double(mp.done) / Double(mp.of)), k3 = m["k3"].string
        let L: [(String, Double, Double)] = [("rev", m["T"]["rev"].double, bm["rev"] ?? 0), ("profit", m["T"]["profit"].double, Books.profit(bm)), (k3, m["T"][k3].double, now3(co, k3))]
        return L.map { x in
            let (k, t, v) = x
            let pace: Bool = (k == "rating" || k == "util" || k == "aware") ? v >= t : k == "profit" ? v >= t * part - abs(t) * 0.05 : v >= t * part * 0.95
            return Standing(key: k, target: t, now: v, onTrack: pace)
        }
    }

    static func judge(_ s: inout GameState, _ ci: Int, data: GameData) -> JSONValue? {
        let co = s.companies[ci]
        guard let m = current(co, week: s.week), let h = co.monthlyHistory.last, h.monthIndex == m["mi"].int else { return nil }
        var t = record(co)
        let k3 = m["k3"].string, T = m["T"]
        let A: [String: Double] = ["rev": h.revenue, "profit": h.profit, k3: now3(co, k3)]
        let hit: [String: Bool] = ["rev": h.revenue >= T["rev"].double, "profit": h.profit >= T["profit"].double, k3: now3(co, k3) >= T[k3].double - 1e-9]
        let n = hit.values.filter { $0 }.count
        if co.managerID != nil { s.companies[ci].set("mood", clamp(ManagerModel.mood(co) + [-4, -1, 2, 4][n], 0, 100)) }
        let r: JSONValue = .object(["mi": m["mi"], "n": .number(Double(n)), "of": .number(3), "hit": .object(hit.mapValues { .bool($0) }), "A": .object(A.mapValues { .number($0) }),
                                    "T": T, "k3": .string(k3), "by": m["by"]])
        var log = t["log"].array; log.append(r)
        if log.count > 24 { log.removeFirst(log.count - 24) }
        t["log"] = .array(log)
        t["bad"] = .number(n <= 1 ? t["bad"].double + 1 : 0)
        put(&s, ci, t)
        return r
    }

    static func talk(_ s: inout GameState, _ ci: Int, _ r: JSONValue, data: GameData) -> String {
        let co = s.companies[ci]
        guard let mid = co.managerID, let mg = s.people[mid] else { return "" }
        let se = setter(s, co, data: data)
        let cd: JSONValue = .object(["co": .number(Double(co.id))])
        if !se.isOwner, record(co)["bad"].double >= 3 {
            s.addMessage(kind: "ask", from: se.name, title: "Three bad months at \(co.name)", body: "\"\(mg.name) has missed most targets three months running. Do we keep them?\"", companyID: co.id, tone: "bad", status: "open",
                         options: [.option("One more chance", "The manager knows it is serious."), .option("Find a successor", "Time to open the hiring for a new manager.")],
                         action: "tg58bad", data: cd, expiresWeek: s.week + 4)
            return "\(se.name) asks you about \(mg.name)"
        }
        s.companies[ci].set("mood", clamp(ManagerModel.mood(co) - 2, 0, 100))
        return se.isOwner ? "" : "\(se.name) had a talk with \(mg.name)"
    }

    static func yearEnd(_ s: inout GameState, _ ci: Int) -> (name: String, rev: Double, profit: Double, budget: (Double, Double), okR: Bool, okP: Bool, yr: Int)? {
        let co = s.companies[ci], y = record(co)["y"]
        guard !y.isNull, y["yr"].int == GameCalendar.year(week: s.week), let a = yearToDate(co, week: s.week) else { return nil }
        var t = record(co)
        let okR = a.rev >= y["rev"].double, okP = a.profit >= y["profit"].double
        if co.managerID != nil { s.companies[ci].set("mood", clamp(ManagerModel.mood(co) + (okR && okP ? 8 : !okR && !okP ? -4 : 1), 0, 100)) }
        var years = t["years"].array
        years.append(.object(["yr": y["yr"], "rev": .number(a.rev), "profit": .number(a.profit), "B": .object(["rev": y["rev"], "profit": y["profit"]]), "okR": .bool(okR), "okP": .bool(okP)]))
        if years.count > 6 { years.removeFirst(years.count - 6) }
        t["years"] = .array(years); put(&s, ci, t)
        return (co.name, a.rev, a.profit, (y["rev"].double, y["profit"].double), okR, okP, y["yr"].int)
    }

    public static func weekly(_ s: inout GameState, data: GameData) {
        let live = s.companies.indices.filter { eligible(s.companies[$0], data: data) }
        if live.isEmpty { return }
        guard GameCalendar.isMonthEnd(week: s.week) else {
            for ci in live {
                let co = s.companies[ci], t = record(co)
                guard current(co, week: s.week) == nil, lastYear(co) != nil else { continue }
                if t["y"].isNull || t["y"]["yr"].int != GameCalendar.year(week: s.week) || !(t["y"]["rev"].double > 0) { makeBudget(&s, ci, year: GameCalendar.year(week: s.week), data: data) }
                setTargets(&s, ci, month: mi(s), data: data)
            }
            return
        }
        var hitsByCompany: [Int: Int] = [:]
        var res: [(String, JSONValue)] = [], talks: [String] = [], years: [(name: String, rev: Double, profit: Double, budget: (Double, Double), okR: Bool, okP: Bool, yr: Int)] = [], asks: [Int] = []
        for ci in live {
            guard let r = judge(&s, ci, data: data) else { continue }
            hitsByCompany[s.companies[ci].id] = r["n"].int
            guard s.companies[ci].managerID != nil else { continue }
            res.append((s.companies[ci].name, r))
            if r["n"].int <= 1 { let line = talk(&s, ci, r, data: data); if !line.isEmpty { talks.append(line) } }
        }
        if GameCalendar.isYearEnd(week: s.week) {
            for ci in live {
                let y = yearEnd(&s, ci)
                if let y { years.append(y) }
                WorkerBonus.yearEnd(&s, ci, budgetMet: y.map { $0.okR && $0.okP } ?? false)
            }
        }
        for ci in live { WorkerBonus.monthEnd(&s, ci, hits: hitsByCompany[s.companies[ci].id]) }
        let nm = mi(s) + 1, yr = yearOf(nm)
        for ci in live {
            let t = record(s.companies[ci])
            if t["y"].isNull || t["y"]["yr"].int != yr || !(t["y"]["rev"].double > 0) {
                if let b = makeBudget(&s, ci, year: yr, data: data), b["ok"].int == 0 { asks.append(s.companies[ci].id) }
            }
            setTargets(&s, ci, month: nm, data: data)
        }
        let cur = World(state: s, data: data).currency(s.companies[live[0]])
        if !res.isEmpty {
            let all = res.filter { $0.1["n"].int == 3 }.count
            var body: String = res.map { "\($0.0) \($0.1["n"].int)/3" }.joined(separator: " · ") + "."
            if !talks.isEmpty { body += " " + talks.joined(separator: ". ") + "." }
            s.addMessage(kind: "info", from: "Your management", title: "Targets in \(monthName(mi(s))): \(all) of \(res.count) \(res.count > 1 ? "companies" : "company") hit all three", body: body,
                         tone: all == res.count ? "good" : all > 0 ? "n" : "bad", status: "done", sev: 1)
        }
        if let first = years.first {
            let body = years.map { "\($0.name): sales \(cur.display($0.rev)) of \(cur.display($0.budget.0)), profit \(cur.display($0.profit)) of \(cur.display($0.budget.1))" }.joined(separator: " · ") + "."
            var desk: Desk?
            for ci in live where desk == nil { desk = Delegation.desk("finance", in: s.companies[ci], state: s, data: data) }
            s.addMessage(kind: "info", from: "Your accountant", title: "The year \(first.yr) against the budgets", body: body, tone: years.allSatisfy { $0.okR && $0.okP } ? "good" : "n", status: "done", sev: 1, aud: desk == nil ? "owner" : "finance", handledBy: desk?.label)
        }
        if !asks.isEmpty {
            let body = asks.compactMap { id in s.company(id).map { "\($0.name): sales \(cur.display(record($0)["y"]["rev"].double)), profit \(cur.display(record($0)["y"]["profit"].double))" } }.joined(separator: " · ") + ". Their drafts, from last year and what they think they can do."
            s.addMessage(kind: "ask", from: "Your managers", title: "Budgets for \(yr) to approve", body: body, tone: "n", status: "open",
                         options: [.option("Approve them", "The managers like a budget they made.")],
                         action: "tg58bud", data: .object(["cos": .array(asks.map { .number(Double($0)) }), "yr": .number(Double(yr))]), expiresWeek: s.week + 4)
        }
    }

    public static let successorAction = "mgrsucc"
    public static func handlesAnswer(_ action: String) -> Bool { action == "tg58talk" || action == "tg58bad" || action == "tg58bud" || action == successorAction }

    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData) {
        let d = m.value("data")
        switch m.actionID {
        case "tg58talk": break
        case "tg58bad":
            guard let ci = s.companyIndex(d["co"].int), s.companies[ci].managerID != nil else { return }
            var t = record(s.companies[ci])
            if idx == 0 { t["bad"] = .number(0); s.companies[ci].set("mood", clamp(ManagerModel.mood(s.companies[ci]) - 3, 0, 100)) }
            else { _ = ManagerModel.findSuccessor(&s, companyID: s.companies[ci].id, data: data) }
            put(&s, ci, t)
        case successorAction:
            if idx == 0 { _ = ManagerModel.findSuccessor(&s, companyID: d["co"].int, data: data) }
        default:
            for id in d["cos"].array.map({ $0.int }) where s.companyIndex(id) != nil { approveBudget(&s, companyID: id, year: d["yr"].int) }
        }
    }

    public static func demandFactor(_ co: Company, week: Int) -> Double {
        guard co.managerID != nil, current(co, week: week) != nil else { return 1 }
        return 1 + (co.managerProfitBonus > 0 ? 0.012 + co.managerProfitBonus * 0.12 : 0.005)
    }
    public static func qualityCare(_ co: Company, week: Int) -> Double {
        guard co.managerID != nil, let m = current(co, week: week), m["k3"].string == "rating", m["T"]["rating"].double > m["from3"].double else { return 0 }
        return co.managerProfitBonus > 0 ? 3 : 2
    }
}
