import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum PlayerGoals {

    static func live(_ s: GameState) -> [Company] { s.companies.filter { $0.status == .open && $0.type != "hold" } }
    static func staffCount(_ s: GameState) -> Int { live(s).reduce(0) { $0 + $1.staff.count + ($1.managerID != nil ? 1 : 0) } }
    static func openComplaints(_ s: GameState) -> Int { live(s).reduce(0) { $0 + Satisfaction.openComplaints($1).count } }

    public struct DailyGoal: Equatable, Sendable {
        public var id: String, title: String, progress: String
        public var done: Bool
        public var streak: Int
        public var claimed: Bool = false
        public var link: String { PlayerGoals.dailyDefs.first { $0.id == id }?.link ?? "" }
    }

    struct DailyDef { var id: String, title: String, link: String, visit: String = "" }

    static let dailyDefs: [DailyDef] = [
        DailyDef(id: "start", title: "Open your first business", link: "newCompany"),
        DailyDef(id: "weeks", title: "Play two weeks", link: "inbox"),
        DailyDef(id: "hire", title: "Hire someone", link: "hire"),
        DailyDef(id: "cmp", title: "Answer the complaints waiting", link: "customers"),
        DailyDef(id: "grow", title: "Grow your net worth by 1%", link: "money"),
        DailyDef(id: "ans", title: "Answer an Inbox decision today", link: "inbox"),
        DailyDef(id: "news", title: "Read one news story", link: "news", visit: "news"),
        DailyDef(id: "stock", title: "Check the stock page", link: "market", visit: "market"),
        DailyDef(id: "quote", title: "Review a supplier quote", link: "techPro", visit: "techPro"),
        DailyDef(id: "collect", title: "Chase an unpaid invoice", link: "money"),
        DailyDef(id: "reviews", title: "Read what customers say", link: "reviews", visit: "reviews"),
        DailyDef(id: "weather", title: "Check the weather outlook", link: "weather", visit: "weather")]

    static func families(_ s: GameState, _ data: GameData) -> Set<String> { Set(live(s).compactMap { data.catalog[$0.type]?.family }) }
    static func openPayrollAsks(_ s: GameState) -> Int { s.inbox.filter { $0.status == "open" && $0.actionID.hasPrefix("pay29") }.count }
    static func openDecisionCount(_ s: GameState) -> Int { s.inbox.filter { $0.status == "open" && !$0.options.isEmpty && !$0.actionID.hasPrefix("pay29") }.count }
    static func answeredCount(_ s: GameState) -> Int {
        s.inbox.filter { !$0.options.isEmpty && !$0.value("pick").isNull && $0.value("pick").int >= 0 && !$0.flag("auto") && $0.value("mgrName").isNull }.count
    }
    static func receivableCount(_ s: GameState) -> Int { live(s).reduce(0) { $0 + $1.receivables.count } }

    static func visited(_ s: GameState, _ app: String, today: String) -> Bool {
        guard let v = s.rest["dy59"]?["vis"], v["d"].string == today else { return false }
        return v["k"].array.contains { $0.string == app }
    }

    @discardableResult
    public static func noteVisit(_ s: inout GameState, app: String, today: String) -> Bool {
        guard dailyDefs.contains(where: { $0.visit == app }) else { return false }
        var d = s.rest["dy59"] ?? .object(["streak": 0, "last": ""])
        var keys: [JSONValue] = d["vis"]["d"].string == today ? d["vis"]["k"].array : []
        if keys.contains(where: { $0.string == app }) { return false }
        keys.append(.string(app))
        d["vis"] = .object(["d": .string(today), "k": .array(keys)])
        s.rest["dy59"] = d
        return true
    }

    static func dailyFits(_ id: String, _ s: GameState, _ data: GameData) -> Bool {
        switch id {
        case "start", "hire", "weeks": return false
        case "grow": return !live(s).isEmpty
        case "news": return !live(s).isEmpty && Gates.isOpen(.bank, s, data: data)
        case "stock": return !live(s).isEmpty
        case "quote": return !live(s).isEmpty && Gates.isOpen(.techpro, s, data: data)
        case "cmp": return openComplaints(s) > 0
        case "ans": return openDecisionCount(s) > 0
        case "collect": return receivableCount(s) > 0 && !families(s, data).isDisjoint(with: ["svc", "project"])
        case "reviews": return Gates.isOpen(.reviews, s, data: data) && !families(s, data).isDisjoint(with: ["venue", "retail"])
        case "weather": return Gates.isOpen(.weather, s, data: data) && !families(s, data).isDisjoint(with: ["venue", "logi", "prod"])
        default: return false
        }
    }

    static func dailyDone(_ id: String, _ b: JSONValue, _ s: GameState, nw: Double, today: String) -> Bool {
        if let v = dailyDefs.first(where: { $0.id == id })?.visit, !v.isEmpty { return visited(s, v, today: today) }
        switch id {
        case "start": return !live(s).isEmpty
        case "weeks": return s.week - b["week"].int >= 2
        case "hire": return staffCount(s) > b["staff"].int
        case "cmp": return openComplaints(s) < b["cmp"].int
        case "grow": return b["nw"].double > 0 && nw >= b["nw"].double * 1.01
        case "ans": return answeredCount(s) > b["ans"].int
        case "collect": return receivableCount(s) < b["rcv"].int
        default: return false
        }
    }

    static func dailyProgress(_ id: String, _ b: JSONValue, _ s: GameState, nw: Double, today: String, _ cur: Currency) -> String {
        if let v = dailyDefs.first(where: { $0.id == id })?.visit, !v.isEmpty { return visited(s, v, today: today) ? "Done" : "Not yet" }
        switch id {
        case "start": return live(s).isEmpty ? "Not yet" : "Open"
        case "weeks": return "\(min(2, s.week - b["week"].int)) of 2 weeks"
        case "hire": return staffCount(s) > b["staff"].int ? "Done" : "Not yet"
        case "cmp": return "\(openComplaints(s)) still open"
        case "grow": return (nw >= b["nw"].double ? "+" : "-") + cur.display(abs(nw - b["nw"].double)) + " of " + cur.display(b["nw"].double * 0.01) + " so far"
        case "ans": return answeredCount(s) > b["ans"].int ? "Done" : "\(openDecisionCount(s)) waiting"
        case "collect": return "\(receivableCount(s)) invoices waiting"
        default: return ""
        }
    }

    public static func dayKey(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    static func dayNumber(_ key: String) -> Int? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? GameCalendar.daysFromCivil(year: p[0], month: p[1], day: p[2]) : nil
    }

    static func streakNow(_ d: JSONValue, today: String, yesterday: String) -> (count: Int, protected: Bool) {
        let last = d["last"].string
        if last == today || last == yesterday { return (d["streak"].int, false) }
        if d["prot"].int > 0, let t = dayNumber(today), let l = dayNumber(last), t - l == 2 { return (d["streak"].int, true) }
        return (0, false)
    }

    public static func dailyGoal(_ s: inout GameState, today: String, yesterday: String, data: GameData, currency cur: Currency) -> DailyGoal? {
        if dailyGoalsOff(s) { return nil }
        var d = s.rest["dy59"] ?? .object(["streak": 0, "last": ""])
        let nw = Valuation.netWorth(s, trades: data.catalog).total
        if d["d"].string != today {
            var fit = dailyDefs.filter { dailyFits($0.id, s, data) }
            if fit.count > 1 { fit.removeAll { $0.id == d["k"].string } }
            let h = today.split(separator: "-").reduce(7) { ($0 * 31 + (Int($1) ?? 0)) & 0x7fffffff }
            d["d"] = .string(today); d["got"] = 0
            d["k"] = .string(fit.isEmpty ? "grow" : fit[h % fit.count].id)
            d["b"] = .object(["week": .number(Double(s.week)), "staff": .number(Double(staffCount(s))), "cmp": .number(Double(openComplaints(s))), "nw": .number(nw),
                              "pay": .number(Double(openPayrollAsks(s))), "ans": .number(Double(answeredCount(s))), "rcv": .number(Double(receivableCount(s)))])
            s.rest["dy59"] = d
        }
        let id = d["k"].string
        guard let g = dailyDefs.first(where: { $0.id == id }) ?? dailyDefs.first(where: { $0.id == "grow" }) else { return nil }
        let now = streakNow(d, today: today, yesterday: yesterday)
        var streak = now.count
        let counted = d["got"].int != 0
        let done = counted || dailyDone(g.id, d["b"], s, nw: nw, today: today)
        if done && !counted {
            if now.protected {
                d["prot"] = .number(Double(max(0, d["prot"].int - 1)))
                s.note("Your streak protection kept the \(streak)-day streak alive.", tone: "good")
            }
            streak += 1
            d["streak"] = .number(Double(streak)); d["last"] = .string(today); d["got"] = 1
            if streak > d["best"].int { d["best"] = .number(Double(streak)) }
            grantStreakPerks(&s, &d, streak: streak)
            s.rest["dy59"] = d
            PlayerLevel.award(&s, PlayerLevel.dailyXP)
        }
        return DailyGoal(id: g.id, title: g.title, progress: dailyProgress(g.id, d["b"], s, nw: nw, today: today, cur), done: done, streak: streak, claimed: d["cl"].string == today)
    }

    public static func dailyGoalsOff(_ s: GameState) -> Bool { (s.rest["dy59"]?["off"].int ?? 0) != 0 }

    public static func setDailyGoalsOff(_ s: inout GameState, _ off: Bool) {
        var d = s.rest["dy59"] ?? .object(["streak": 0, "last": ""])
        if off { d["off"] = .number(1) } else if !d["off"].isNull { d["off"] = .number(0) }
        s.rest["dy59"] = d
    }

    static func stepsLive(_ s: GameState) -> [Company] { s.companies.filter { $0.status.isLive && $0.type != "hold" } }

    public static func stepDone(_ id: String, _ s: GameState) -> Bool {
        let L = stepsLive(s)
        switch id {
        case "co": return !L.isEmpty
        case "staff": return L.contains { !$0.staff.isEmpty }
        case "open": return L.contains { $0.status == .open }
        case "week": return !((s.rest["reports"]?[ReportKind.week.storeKey] ?? .null).array.isEmpty)
        case "sell": return L.contains { $0.priceLevel != 0 || $0.value("chose").int != 0 }
        case "ad": return L.contains { $0.value("mkt").object.values.contains { $0["b"].double > 0 } }
        case "inbox": return s.inbox.contains { !$0.options.isEmpty && $0.value("pick").int >= 0 && !$0.value("pick").isNull && !$0.flag("auto") && $0.value("mgrName").isNull }
        case "pay": return L.contains { $0.ownerMonthlySalary > 0 || $0.distributed > 0 }
        case "profit": return L.contains { $0.monthlyHistory.contains { $0.profit > 0 } }
        case "mgr": return L.contains { $0.managerID != nil || !$0.value("asst").isNull }
        default: return false
        }
    }

    public struct LadderGoal: Equatable, Sendable {
        public var id: String, title: String, body: String
        public var button: String, link: String
        public var pastTense: String
        public var reward: String
        public var done: Bool
        public var advanced: Bool = false
        public var unclaimed: Bool = false
    }

    public static let quietWeeksForM10 = 12

    static let ladderList: [(id: String, title: String, body: String, button: String, link: String, past: String, reward: String)] = [
        ("M1", "Get through your first week", "Tap Next day. Each day trades, each week ends with a report.", "", "", "You got through your first week.", "Your credit score goes up a little"),
        ("M2", "Choose how you sell", "Pick who you are for and what else you offer.", "Open sales", "sales", "You chose how you sell.", "More people know the name"),
        ("M3", "Hire your first worker", "Check what they claim before you hire.", "Find workers", "hire", "You hired your first worker.", "A better name as an employer"),
        ("M4", "Answer a decision", "Problems and offers wait in the Inbox for your answer.", "Open Inbox", "inbox", "You answered your first decision.", "A little better reputation"),
        ("M5", "Word gets around", "Even a small campaign brings people in.", "Open marketing", "marketing", "Your first campaign ran.", ""),
        ("M6", "Pay yourself", "Take money out of the business for yourself. Leave enough for the bills.", "Open money", "money", "You paid yourself.", ""),
        ("M7", "Make a profit in a month", "Keep the costs in check and the customers coming.", "Open company", "company", "Your first profitable month.", "Your credit score goes up, and you can choose an ambition"),
        ("M8", "Hire a manager", "They run it day to day while you grow.", "Open management", "management", "You hired a manager.", "A better reputation"),
        ("M9", "Trade for a quarter", "Thirteen weeks of keeping the doors open.", "", "", "You traded for a quarter.", "World ranking unlocks"),
        ("M10", "Survive a bad week", "Something will go wrong. Keep the lights on.", "", "", "You survived a bad week.", "Your credit score goes up a little"),
    ]

    public static func startLadder(_ s: inout GameState) { s.rest["ldr"] = .object(["done": .object([:])]) }

    static func ladderCondition(_ id: String, _ s: GameState) -> Bool {
        switch id {
        case "M1": return stepDone("week", s)
        case "M2": return stepDone("sell", s)
        case "M3": return stepDone("staff", s)
        case "M4": return stepDone("inbox", s)
        case "M5": return stepDone("ad", s)
        case "M6": return stepDone("pay", s)
        case "M7": return stepDone("profit", s)
        case "M8": return stepDone("mgr", s)
        case "M9": return s.week >= 13
        case "M10":
            let since: Int = s.rest["ldr"]?["done"]["M9"]["w"].int ?? s.week
            if s.week >= since + quietWeeksForM10 { return true }
            let weeks = Reports.stored(s, .week)
            guard let hit = weeks.first(where: { r in r.group.events.contains { $0.tone == "bad" } && r.group.pnl.fines + r.group.pnl.losses > 0 }) else { return false }
            return s.week >= hit.id + 2 && stepsLive(s).allSatisfy { $0.cash >= 0 }
        default: return false
        }
    }

    public static func ladder(_ s: GameState) -> [LadderGoal]? {
        guard let l = s.rest["ldr"] else { return nil }
        return ladderList.map { LadderGoal(id: $0.id, title: $0.title, body: $0.body, button: $0.button, link: $0.link, pastTense: $0.past, reward: $0.reward, done: !l["done"][$0.id].isNull, unclaimed: l["done"][$0.id]["u"].int != 0) }
    }

    public static func currentLadderGoal(_ s: GameState) -> LadderGoal? { ladder(s)?.first { !$0.done && $0.id != "M10" } }

    public static func ladderPastTense(_ s: GameState, firstWeek: Int, lastWeek: Int) -> String? {
        guard let d = s.rest["ldr"]?["done"] else { return nil }
        let hit = ladderList.filter { !d[$0.id].isNull && d[$0.id]["skip"].int == 0 && d[$0.id]["w"].int >= firstWeek && d[$0.id]["w"].int <= lastWeek }
        return hit.first?.past
    }

    @discardableResult
    public static func ladderSweep(_ s: inout GameState, currency cur: Currency) -> [String] {
        guard s.rest["ldr"] != nil else { return [] }
        var finished: [String] = []
        for g in ladderList where s.rest["ldr"]?["done"][g.id].isNull ?? true {
            guard ladderCondition(g.id, s) else {
                if goalStale(g.id, s) { skipGoal(&s, g.id); continue }
                break
            }
            var l = s.rest["ldr"] ?? .object([:])
            var d = l["done"]; d[g.id] = .object(["w": .number(Double(s.week)), "u": .number(1)]); l["done"] = d
            s.rest["ldr"] = l
            PlayerLevel.award(&s, PlayerLevel.ladderXP)
            Celebrations.add(&s, kind: "goal", title: g.title, detail: g.past, reward: g.reward, art: "goal." + g.id, tier: 1)
            finished.append(g.id)
        }
        advancedSweep(&s)
        return finished
    }

    static let skippableGoals: Set<String> = ["M3", "M4", "M5", "M6", "M8"]
    public static let staleWeeks = 12

    static func goalStale(_ id: String, _ s: GameState) -> Bool {
        guard skippableGoals.contains(id), let at = ladderList.firstIndex(where: { $0.id == id }), at > 0 else { return false }
        let before: JSONValue = s.rest["ldr"]?["done"][ladderList[at - 1].id] ?? .null
        return !before.isNull && s.week >= before["w"].int + staleWeeks
    }

    static func skipGoal(_ s: inout GameState, _ id: String) {
        var l = s.rest["ldr"] ?? .object([:])
        var d = l["done"]
        d[id] = .object(["w": .number(Double(s.week)), "u": .number(0), "skip": .number(1)])
        l["done"] = d
        s.rest["ldr"] = l
    }

    public static func ladderReward(_ s: inout GameState, _ id: String, _ cur: Currency) -> String {
        func each(_ f: (inout Company) -> Void) { for i in s.companies.indices where s.companies[i].status.isLive && s.companies[i].type != "hold" { f(&s.companies[i]) } }
        switch id {
        case "M1": s.credit = min(100, s.credit + 3); return "The bank likes a good start: your credit score is a little better."
        case "M2":
            var name = "you"
            if let i = s.companies.firstIndex(where: { $0.status.isLive && $0.type != "hold" }) { s.companies[i].awareness = min(100, s.companies[i].awareness + 8); name = s.companies[i].name }
            return "The local paper writes about \(name): more people know the name."
        case "M3":
            if let i = s.companies.firstIndex(where: { $0.status.isLive && $0.type != "hold" && !$0.staff.isEmpty }) { s.companies[i].reputation = min(100, s.companies[i].reputation + 2) }
            return "Word gets round that you hire fairly: your reputation as an employer is a little better."
        case "M4": each { $0.reputation = min(100, $0.reputation + 1) }; return "People learn they can count on you: a little better reputation."
        case "M7":
            s.credit = min(100, s.credit + 5)
            var l = s.rest["ldr"] ?? .object([:]); l["amb"] = 1; s.rest["ldr"] = l
            return "A profitable month: the bank offers you better terms."
        case "M8":
            each { $0.reputation = min(100, $0.reputation + 2) }
            var l = s.rest["ldr"] ?? .object([:]); l["classic"] = 1; s.rest["ldr"] = l
            return "A company that runs without you looks steadier: customers and suppliers think better of it."
        case "M9":
            var l = s.rest["ldr"] ?? .object([:]); l["rank"] = 1; s.rest["ldr"] = l
            return "The world ranking is open to you."
        case "M10": s.credit = min(100, s.credit + 3); return "Lenders see that you came through a hard stretch: your credit score is a little better."
        default: return ""
        }
    }

    public static func ladderFlag(_ s: GameState, _ key: String) -> Bool { s.rest["ldr"].map { $0[key].int != 0 } ?? false }
}
