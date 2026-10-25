import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Monthly targets and the yearly budget for managed companies.
/// Originals: `TG58` (features/people/targets_and_budgets.js): setter, budget, `setTargets`, `standing`, `judge`, `talk`, `yearEnd`,
/// `monthEnd`, the answers `tg58talk`, `tg58bad`, `tg58bud`, the steps 'demand' (a manager chasing a bonus) and 'window.qualityTarget:2'.
///
/// Every managed company gets three targets a month: sales, profit and a third (rating, how busy it is, or how well known it is). They are
/// set by the first level above the manager (regional, chain or managing director) or by you. Hitting targets pays the manager a bonus,
/// lifts mood and the scorecard (`Headquarters.review` reads the log); missing most of them brings a talk, and after three bad months
/// the boss asks whether to replace the manager. The budget for the year is drafted from last year, tightened by the boss or approved
/// by you; meeting both sales and profit at the year end pays a year-end bonus. All of it is paid through `Payments.companyPays`.
///
/// Saved on the company as `tg58` {m (this month's targets), y (the budget), log, bo (bonus level 0...2), bad, own, ownMode, easy, push,
/// warn58, years}, the same shape as the original so saves carry over. Month numbers are `GameCalendar.monthIndex` (year * 12 + month).
public enum ManagerTargets {
    /// Bonus per target met, as a share of the monthly wage. Original: `BO`.
    public static let bonusLevels: [(rate: Double, name: String)] = [(0, "No bonus"), (0.08, "Standard"), (0.15, "High")]
    static let noFamily: Set<String> = ["fin", "energy", "rent", "club"]

    public struct Setter: Equatable, Sendable {
        public var kind: String
        public var name: String
        public var title: String
        public var quality: Double
        public var isOwner: Bool { kind == "you" }
    }

    /// One line of the target card: where a target stands now.
    public struct Standing: Equatable, Sendable {
        public var key: String        // rev, profit, rating, util, aware
        public var target: Double
        public var now: Double
        public var onTrack: Bool
    }

    // MARK: Which companies, and the saved record

    public static func eligible(_ co: Company, data: GameData) -> Bool {
        guard co.status == .open, co.type != "hold", let bd = data.catalog[co.type] else { return false }
        return !noFamily.contains(bd.family)
    }

    static func record(_ co: Company) -> JSONValue {
        let t = co.value("tg58")
        return t.isNull ? .object(["m": .null, "y": .null, "log": .array([]), "bo": .number(1), "bad": .number(0)]) : t
    }
    static func put(_ s: inout GameState, _ ci: Int, _ t: JSONValue) { s.companies[ci].set("tg58", t) }
    static func mi(_ s: GameState) -> Int { GameCalendar.monthIndex(week: s.week) }
    static func month0(_ m: Int) -> Int { (((m - 1) % 12) + 12) % 12 }   // never negative, so a month counter of 0 cannot index out of range
    static func yearOf(_ m: Int) -> Int { (m - 1) / 12 }
    static func monthName(_ m: Int) -> String { GameCalendar.monthNames[month0(m)] }
    static func bonusRate(_ t: JSONValue) -> Double { bonusLevels[min(2, max(0, t["bo"].isNull ? 1 : t["bo"].int))].rate }

    /// This month's targets, if set for this month. Original: `cur`.
    public static func current(_ co: Company, week: Int) -> JSONValue? {
        let m = record(co)["m"]
        // Return the optional explicitly: `JSONValue` is ExpressibleByNilLiteral, so a bare `cond ? m : nil` yields `.null`, never nil.
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

    // MARK: Who sets them

    public static func setter(_ s: GameState, _ co: Company, data: GameData) -> Setter {
        if co.managerID != nil, let up = ManagerModel.decisionChain(s, co, data: data).first(where: { $0.kind != "mgr" }), let n = s.people[up.personID] {
            let sales = n.value("stats")["sales"].double
            let skill = sales != 0 ? sales : (n.num("skill") != 0 ? n.num("skill") : 55)
            return Setter(kind: up.kind, name: up.name, title: ManagerModel.titleFor(co, kind: up.kind, data: data, state: s), quality: clamp(skill / 100, 0.2, 1))
        }
        return Setter(kind: "you", name: "You", title: "Owner", quality: 1)
    }

    // MARK: The budget

    struct LastYear { var rev: Double; var profit: Double; var h: [MonthRecord] }
    static func lastYear(_ co: Company) -> LastYear? {
        let h = Array(co.monthlyHistory.suffix(12).filter { $0.revenue > 0 })   // months with sales: not the setup months
        if h.count < 2 { return nil }
        let f = 12 / Double(h.count)
        return LastYear(rev: h.reduce(0) { $0 + $1.revenue } * f, profit: h.reduce(0) { $0 + $1.profit } * f, h: h)
    }
    /// Each calendar month's share of a year, from last year's months when there are twelve, else even.
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
    /// The last three months and the year they point to, the latest month counting most. Original: `recent`.
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
        let g = clamp(0.04 + (q - 0.5) * 0.08 + (s.economy.demand - 1) * 0.5, -0.06, 0.12)
        let sh = shares(co), left = sh[month0(m0)...].reduce(0, +)
        let base = ly.h.count >= 12 ? (ly.rev + r3.ann) / 2 : r3.ann
        let margin = r3.rev > 0 ? (r3.profit / r3.rev + (ly.rev > 0 ? ly.profit / ly.rev : 0)) / 2 : 0
        let rev = base * (1 + g) * left
        return (cur.roundedStep(rev, about: 1000), cur.roundedStep(rev * min(0.35, margin + 0.01), about: 1000), sh)
    }

    /// The budget a company works to this year: {yr, m0, rev, profit, by, ok (approved), sh, d0}. Original: `makeBudget`.
    @discardableResult
    static func makeBudget(_ s: inout GameState, _ ci: Int, year yr: Int, data: GameData) -> JSONValue? {
        let co = s.companies[ci], monthEnd = GameCalendar.isMonthEnd(week: s.week)
        let m0 = max(mi(s) + (monthEnd ? 1 : 0), yr * 12 + 1)
        guard let d = draft(s, co, from: m0, data: data) else { return nil }
        let se = setter(s, co, data: data), cur = World(state: s, data: data).currency(co), managed = co.managerID != nil
        var rev = d.rev, profit = d.profit, by = managed ? se.kind : "acc", ok = 1
        // A boss above the manager tightens the draft; you approve it yourself.
        if managed && !se.isOwner { let x = 0.02 + 0.05 * se.quality; rev = cur.roundedStep(d.rev * (1 + x), about: 1000); profit = cur.roundedStep(d.profit + abs(d.profit) * x * 1.5, about: 1000) }
        if managed && se.isOwner { if monthEnd && GameCalendar.isYearEnd(week: s.week) { ok = 0 } else { by = "draft" } }
        let y: JSONValue = .object(["yr": .number(Double(yr)), "m0": .number(Double(m0)), "rev": .number(rev), "profit": .number(profit), "sh": .array(d.sh.map { .number($0) }),
                                    "by": .string(by), "ok": .number(Double(ok)), "d0": .object(["rev": .number(d.rev), "profit": .number(d.profit)])])
        var t = record(co); t["y"] = y; put(&s, ci, t)
        return y
    }

    /// What the year has brought so far against the budget: (sales, profit). Original: `ytd`.
    public static func yearToDate(_ co: Company, week: Int) -> (rev: Double, profit: Double)? {
        let y = record(co)["y"]
        if y.isNull { return nil }
        let now = GameCalendar.monthIndex(week: week), m0 = y["m0"].int, yr = y["yr"].int
        let h = co.monthlyHistory.filter { $0.monthIndex >= m0 && yearOf($0.monthIndex) == yr }
        let bm = co.books.month, inCurrent = now >= m0 && yearOf(now) == yr && !h.contains { $0.monthIndex == now }
        return (h.reduce(0) { $0 + $1.revenue } + (inCurrent ? bm["rev"] ?? 0 : 0),
                h.reduce(0) { $0 + $1.profit } + (inCurrent ? Books.profit(bm) : 0))
    }

    // MARK: This month's targets

    /// What the targets would be for month `m` (nothing saved). `mode`: 0 easy, 1 realistic, 2 stretch, nil = the setter's own stretch. Original: `setTargets`.
    static func compute(_ s: GameState, _ co: Company, month m: Int, mode: Int?, data: GameData) -> JSONValue? {
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
        // The boss's own stretch: a skilled one aims close to what is possible, a weaker one guesses.
        var x = 0.0
        if !se.isOwner { x = 0.01 + 0.03 * se.quality + (HashedRandom.first("\(s.seed):tg58:\(co.id):\(m)") - 0.5) * 0.16 * (1 - se.quality) }
        if let md = mode { x = [-0.05, 0, 0.08][min(2, max(0, md))] }
        let k3 = third(co), n3 = now3(co, k3), up: Double = mode == 2 ? 1 : mode == 0 ? -1 : 0
        let t3: Double
        if k3 == "rating" { t3 = min(4.8, floor(n3 * 10 + 1e-6) / 10 + (n3 < 3.6 ? 0.1 : 0) + 0.1 * up) }
        else if k3 == "util" { t3 = clamp(floor(n3 * 20 + 1e-6) / 20 + 0.05 * up, 0.1, 0.95) }
        else { t3 = min(95, floor(n3) + 1 + 2 * up) }
        return .object(["mi": .number(Double(m)), "by": .string(se.kind), "n": .string(se.name),
                        "T": .object(["rev": .number(cur.roundedStep(max(0, rev * (1 + x)), about: 1000)), "profit": .number(cur.roundedStep(profit + abs(profit) * x * 1.5, about: 1000)), k3: .number(t3)]),
                        "k3": .string(k3), "from3": .number(n3), "mode": .number(Double(mode ?? 1))])
    }
    @discardableResult
    static func setTargets(_ s: inout GameState, _ ci: Int, month m: Int, mode: Int?, data: GameData) -> Bool {
        guard let v = compute(s, s.companies[ci], month: m, mode: mode, data: data) else { return false }
        var t = record(s.companies[ci]); t["m"] = v; put(&s, ci, t)
        return true
    }

    /// Weeks into the month, of the weeks it has. Original: `monthPart`.
    static func monthPart(week: Int) -> (done: Int, of: Int) {
        let m = GameCalendar.monthIndex(week: week)
        var a = week, b = week
        while GameCalendar.monthIndex(week: a - 1) == m { a -= 1 }
        while GameCalendar.monthIndex(week: b + 1) == m { b += 1 }
        return (week - a, b - a + 1)
    }

    /// Where each target stands now. Original: `standing`.
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

    // MARK: Month end

    /// The month against the targets: bonus, mood, the log. Original: `judge`. Returns the log entry.
    static func judge(_ s: inout GameState, _ ci: Int, data: GameData) -> JSONValue? {
        let co = s.companies[ci]
        guard let m = current(co, week: s.week), let h = co.monthlyHistory.last, h.monthIndex == m["mi"].int else { return nil }
        var t = record(co)
        let k3 = m["k3"].string, T = m["T"]
        let A: [String: Double] = ["rev": h.revenue, "profit": h.profit, k3: now3(co, k3)]
        let hit: [String: Bool] = ["rev": h.revenue >= T["rev"].double, "profit": h.profit >= T["profit"].double, k3: now3(co, k3) >= T[k3].double - 1e-9]
        let n = hit.values.filter { $0 }.count, managed = co.managerID != nil
        let bonus = managed ? jsRound(Double(n) * bonusRate(t) * co.managerMonthlyWage) : 0
        if bonus > 0 {
            Payments.companyPays(&s, companyID: co.id, amount: bonus, category: "wages", label: "Bonus: monthly targets met")
            s.companies[ci].set("mgrBonusLast", bonus)
        }
        if managed { s.companies[ci].set("mood", clamp(ManagerModel.mood(co) + [-4, -1, 2, 4][n] + (bonus > 0 ? 1 : 0), 0, 100)) }
        let r: JSONValue = .object(["mi": m["mi"], "n": .number(Double(n)), "of": .number(3), "hit": .object(hit.mapValues { .bool($0) }), "A": .object(A.mapValues { .number($0) }),
                                    "T": T, "k3": .string(k3), "by": m["by"], "bonus": .number(bonus)])
        var log = t["log"].array; log.append(r)
        if log.count > 24 { log.removeFirst(log.count - 24) }
        t["log"] = .array(log)
        t["bad"] = .number(n <= 1 ? t["bad"].double + 1 : 0)
        put(&s, ci, t)
        return r
    }

    /// A talk after missed targets: with you if you set them, else with their boss. Returns a line for the summary. Original: `talk`.
    static func talk(_ s: inout GameState, _ ci: Int, _ r: JSONValue, data: GameData) -> String {
        let co = s.companies[ci]
        guard let mid = co.managerID, let mg = s.people[mid] else { return "" }
        let se = setter(s, co, data: data), names: [String: String] = ["rev": "sales", "profit": "profit", "rating": "rating", "util": "how busy it is", "aware": "awareness"]
        let miss = r["hit"].object.filter { !$0.value.bool }.keys.sorted().map { names[$0] ?? $0 }.joined(separator: " and ")
        let cd: JSONValue = .object(["co": .number(Double(co.id))])
        if se.isOwner {
            s.addMessage(kind: "ask", from: mg.name, title: "Targets missed at \(co.name)", body: "\"We missed \(miss) in \(monthName(r["mi"].int)). I would like to talk about it.\"", companyID: co.id, tone: "n", status: "open",
                         options: [.option("Back them", "Better mood. The targets stay."), .option("Give a warning", "They push harder this month, and take it badly if it happens again."), .option("Lower the bar", "Easier targets next month.")],
                         action: "tg58talk", data: cd, expiresWeek: s.week + 3)
            return ""
        }
        if record(co)["bad"].double >= 3 {
            s.addMessage(kind: "ask", from: se.name, title: "Three bad months at \(co.name)", body: "\"\(mg.name) has missed most targets three months running. Do we keep them?\"", companyID: co.id, tone: "bad", status: "open",
                         options: [.option("One more chance", "The manager knows it is serious."), .option("Find a successor", "Time to open the hiring for a new manager.")],
                         action: "tg58bad", data: cd, expiresWeek: s.week + 4)
            return "\(se.name) asks you about \(mg.name)"
        }
        s.companies[ci].set("mood", clamp(ManagerModel.mood(co) - 2, 0, 100))
        return "\(se.name) had a talk with \(mg.name)"
    }

    /// The year against the budget, and the year-end bonus. Original: `yearEnd`.
    static func yearEnd(_ s: inout GameState, _ ci: Int) -> (name: String, rev: Double, profit: Double, budget: (Double, Double), okR: Bool, okP: Bool, bonus: Double, yr: Int)? {
        let co = s.companies[ci], y = record(co)["y"]
        guard !y.isNull, y["yr"].int == GameCalendar.year(week: s.week), let a = yearToDate(co, week: s.week) else { return nil }
        var t = record(co)
        let okR = a.rev >= y["rev"].double, okP = a.profit >= y["profit"].double, managed = co.managerID != nil
        var bonus = 0.0
        if managed && okR && okP {
            bonus = jsRound(co.managerMonthlyWage * [0, 1, 1.5][min(2, max(0, t["bo"].isNull ? 1 : t["bo"].int))])
            if bonus > 0 { Payments.companyPays(&s, companyID: co.id, amount: bonus, category: "wages", label: "Bonus: the year's budget met") }
        }
        if managed { s.companies[ci].set("mood", clamp(ManagerModel.mood(co) + (okR && okP ? 8 : !okR && !okP ? -4 : 1), 0, 100)) }
        var years = t["years"].array
        years.append(.object(["yr": y["yr"], "rev": .number(a.rev), "profit": .number(a.profit), "B": .object(["rev": y["rev"], "profit": y["profit"]]), "okR": .bool(okR), "okP": .bool(okP), "bonus": .number(bonus)]))
        if years.count > 6 { years.removeFirst(years.count - 6) }
        t["years"] = .array(years); put(&s, ci, t)
        return (co.name, a.rev, a.profit, (y["rev"].double, y["profit"].double), okR, okP, bonus, y["yr"].int)
    }

    /// The step after each week: at the month end the results, bonuses, talks, next year's budget and next month's targets; otherwise a
    /// newly managed company gets its first targets straight away. Call it after `MonthEnd.closeMonth`. Original: the step 'targets and budgets: the month end'.
    public static func weekly(_ s: inout GameState, data: GameData) {
        let live = s.companies.indices.filter { eligible(s.companies[$0], data: data) }
        if live.isEmpty { return }
        guard GameCalendar.isMonthEnd(week: s.week) else {
            for ci in live {
                let co = s.companies[ci], t = record(co)
                guard co.managerID != nil || t["own"].bool, current(co, week: s.week) == nil, lastYear(co) != nil else { continue }
                if t["y"].isNull || t["y"]["yr"].int != GameCalendar.year(week: s.week) || !(t["y"]["rev"].double > 0) { makeBudget(&s, ci, year: GameCalendar.year(week: s.week), data: data) }
                setTargets(&s, ci, month: mi(s), mode: t["own"].bool ? t["ownMode"].int : nil, data: data)
            }
            return
        }
        var hitsByCompany: [Int: Int] = [:]
        var res: [(String, JSONValue)] = [], talks: [String] = [], years: [(name: String, rev: Double, profit: Double, budget: (Double, Double), okR: Bool, okP: Bool, bonus: Double, yr: Int)] = [], asks: [Int] = []
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
                WorkerBonus.yearEnd(&s, ci, budgetMet: y.map { $0.okR && $0.okP } ?? false)   // the staff's year-end bonus, on the same budget
            }
        }
        for ci in live { WorkerBonus.monthEnd(&s, ci, hits: hitsByCompany[s.companies[ci].id]) }
        // Next month: a budget for the coming year where there is none, then the targets.
        let nm = mi(s) + 1, yr = yearOf(nm)
        for ci in live {
            var t = record(s.companies[ci])
            if t["y"].isNull || t["y"]["yr"].int != yr || !(t["y"]["rev"].double > 0) {
                if let b = makeBudget(&s, ci, year: yr, data: data), b["ok"].int == 0 { asks.append(s.companies[ci].id) }
                t = record(s.companies[ci])
            }
            let co = s.companies[ci]
            if co.managerID != nil || t["own"].bool {
                var mode: Int? = nil
                if !t["easy"].isNull && t["easy"].int == nm { mode = 0 }
                else if t["own"].bool { mode = t["ownMode"].int }
                else if t["m"]["by"].string == "you" && !t["m"]["mode"].isNull { mode = t["m"]["mode"].int }
                setTargets(&s, ci, month: nm, mode: mode, data: data)
            }
        }
        let cur = World(state: s, data: data).currency(s.companies[live[0]])
        if !res.isEmpty {
            let all = res.filter { $0.1["n"].int == 3 }.count, bon = res.reduce(0) { $0 + $1.1["bonus"].double }
            var parts: [String] = []
            for r in res {
                let bonusPart: String = r.1["bonus"].double > 0 ? " (bonus \(cur.display(r.1["bonus"].double)))" : ""
                parts.append("\(r.0) \(r.1["n"].int)/3" + bonusPart)
            }
            var body: String = parts.joined(separator: " · ") + "."
            if !talks.isEmpty { body += " " + talks.joined(separator: ". ") + "." }
            if bon > 0 { body += " Bonuses paid: \(cur.display(bon))." }
            s.addMessage(kind: "info", from: "Your management", title: "Targets in \(monthName(mi(s))): \(all) of \(res.count) \(res.count > 1 ? "companies" : "company") hit all three", body: body,
                         tone: all == res.count ? "good" : all > 0 ? "n" : "bad", status: "done")
        }
        if let first = years.first {
            let body = years.map { "\($0.name): sales \(cur.display($0.rev)) of \(cur.display($0.budget.0)), profit \(cur.display($0.profit)) of \(cur.display($0.budget.1))" + ($0.bonus > 0 ? ", year-end bonus \(cur.display($0.bonus))" : "") }.joined(separator: " · ") + "."
            s.addMessage(kind: "info", from: "Your accountant", title: "The year \(first.yr) against the budgets", body: body, tone: years.allSatisfy { $0.okR && $0.okP } ? "good" : "n", status: "done")
        }
        if !asks.isEmpty {
            let body = asks.compactMap { id in s.company(id).map { "\($0.name): sales \(cur.display(record($0)["y"]["rev"].double)), profit \(cur.display(record($0)["y"]["profit"].double))" } }.joined(separator: " · ") + ". Their drafts, from last year and what they think they can do."
            s.addMessage(kind: "ask", from: "Your managers", title: "Budgets for \(yr) to approve", body: body, tone: "n", status: "open",
                         options: [.option("Approve them", "The managers like a budget they made."), .option("Ask for 10% more", "Harder targets all year. Some will grumble."), .option("Keep them safe", "5% lower: easier bonuses, less ambition.")],
                         action: "tg58bud", data: .object(["cos": .array(asks.map { .number(Double($0)) }), "yr": .number(Double(yr))]), expiresWeek: s.week + 4)
        }
    }

    // MARK: Answers

    /// "Find a successor", asked when a manager gives notice (`ManagerModel.resign`) or after three bad months.
    public static let successorAction = "mgrsucc"
    public static func handlesAnswer(_ action: String) -> Bool { action == "tg58talk" || action == "tg58bad" || action == "tg58bud" || action == successorAction }

    /// The player's answer to a target talk, a successor question or the budgets. Original: `ACTS.tg58talk`, `tg58bad`, `tg58bud`.
    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData) {
        let d = m.value("data")
        switch m.actionID {
        case "tg58talk", "tg58bad":
            guard let ci = s.companyIndex(d["co"].int), s.companies[ci].managerID != nil else { return }
            var t = record(s.companies[ci]); let mood = ManagerModel.mood(s.companies[ci])
            if m.actionID == "tg58bad" {
                if idx == 0 { t["bad"] = .number(0); s.companies[ci].set("mood", clamp(mood - 3, 0, 100)) }
                else { _ = ManagerModel.findSuccessor(&s, companyID: s.companies[ci].id, data: data) }
                put(&s, ci, t)
            } else if idx == 0 {
                s.companies[ci].set("mood", clamp(mood + 4, 0, 100))
            } else if idx == 1 {
                s.companies[ci].set("mood", clamp(mood - (t["warn58"].bool ? 8 : 4), 0, 100))
                t["warn58"] = .number(Double(s.week)); t["push"] = .number(Double(mi(s))); put(&s, ci, t)
            } else {
                t["easy"] = .number(Double(mi(s) + 1)); put(&s, ci, t)
                if current(s.companies[ci], week: s.week) != nil { setTargets(&s, ci, month: mi(s), mode: 0, data: data) }
            }
        case successorAction:
            if idx == 0 { _ = ManagerModel.findSuccessor(&s, companyID: d["co"].int, data: data) }
        default:
            for id in d["cos"].array.map({ $0.int }) {
                guard let ci = s.companyIndex(id) else { continue }
                var t = record(s.companies[ci]); let y = t["y"]
                guard !y.isNull, y["yr"].int == d["yr"].int else { continue }
                let f = [0, 0.1, -0.05][min(2, max(0, idx))], cur = World(state: s, data: data).currency(s.companies[ci])
                var y2 = y
                y2["rev"] = .number(cur.roundedStep(y["d0"]["rev"].double * (1 + f), about: 1000))
                y2["profit"] = .number(cur.roundedStep(y["d0"]["profit"].double + abs(y["d0"]["profit"].double) * f * 1.5, about: 1000))
                y2["ok"] = .number(1)
                t["y"] = y2; put(&s, ci, t)
                if s.companies[ci].managerID != nil { s.companies[ci].set("mood", clamp(ManagerModel.mood(s.companies[ci]) + [2, -3, 1][min(2, max(0, idx))], 0, 100)) }
                if let cm = current(s.companies[ci], week: s.week) { setTargets(&s, ci, month: mi(s), mode: cm["mode"].int, data: data) }
            }
        }
    }

    // MARK: Chasing a bonus

    /// A few per cent more customers while the manager chases a bonus (more after a warning). Original: step 'demand' 80.
    public static func demandFactor(_ co: Company, week: Int) -> Double {
        guard co.managerID != nil, current(co, week: week) != nil else { return 1 }
        let t = record(co), b = bonusRate(t)
        return 1 + (b > 0 ? 0.012 + b * 0.12 : 0.005) + (t["push"].int == GameCalendar.monthIndex(week: week) && !t["push"].isNull ? 0.01 : 0)
    }
    /// More care for quality while the rating is a target the company has not reached. Original: step 'window.qualityTarget:2'.
    public static func qualityCare(_ co: Company, week: Int) -> Double {
        guard co.managerID != nil, let m = current(co, week: week), m["k3"].string == "rating", m["T"]["rating"].double > m["from3"].double else { return 0 }
        return bonusRate(record(co)) > 0 ? 3 : 2
    }
}
