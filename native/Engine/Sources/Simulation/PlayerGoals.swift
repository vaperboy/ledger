import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The player's own goals: the ten-goal ladder (the one teaching spine) and the daily goal, a streak badge that pays nothing.
/// (Ambitions live in Businesses/Ambitions.swift.) State lives in `rest["ldr"]` and `rest["dy59"]`.
public enum PlayerGoals {
    // MARK: Shared facts

    static func live(_ s: GameState) -> [Company] { s.companies.filter { $0.status == .open && $0.type != "hold" } }
    static func staffCount(_ s: GameState) -> Int { live(s).reduce(0) { $0 + $1.staff.count + ($1.managerID != nil ? 1 : 0) } }
    static func openComplaints(_ s: GameState) -> Int { live(s).reduce(0) { $0 + Satisfaction.openComplaints($1).count } }

    // MARK: Daily goal

    /// Today's goal and the streak it keeps. There is no cash: the badge counts days in a row.
    public struct DailyGoal: Equatable, Sendable {
        public var id: String, title: String, progress: String
        public var done: Bool
        /// Days in a row, counting today once the goal is done.
        public var streak: Int
        /// Where today's goal is done (a `GameStore.openLadderLink` key).
        public var link: String { ["start": "newCompany", "weeks": "inbox", "hire": "hire", "cmp": "customers", "grow": "money"][id] ?? "" }
    }

    static let dailyIDs: [(id: String, title: String)] = [
        ("start", "Open your first business"), ("weeks", "Play two weeks"), ("hire", "Hire someone"),
        ("cmp", "Answer the complaints waiting"), ("grow", "Grow your net worth by 1%")]

    static func dailyFits(_ id: String, _ s: GameState) -> Bool {
        switch id {
        // "start" and "hire" are setup steps: they are no longer offered as a new daily goal (a goal already picked in an older save still works).
        case "start", "hire", "weeks": return false
        case "grow": return !live(s).isEmpty
        case "cmp": return openComplaints(s) > 0
        default: return false
        }
    }

    static func dailyDone(_ id: String, _ b: JSONValue, _ s: GameState, nw: Double) -> Bool {
        switch id {
        case "start": return !live(s).isEmpty
        case "weeks": return s.week - b["week"].int >= 2
        case "hire": return staffCount(s) > b["staff"].int
        case "cmp": return openComplaints(s) < b["cmp"].int
        case "grow": return b["nw"].double > 0 && nw >= b["nw"].double * 1.01
        default: return false
        }
    }

    static func dailyProgress(_ id: String, _ b: JSONValue, _ s: GameState, nw: Double, _ cur: Currency) -> String {
        switch id {
        case "start": return live(s).isEmpty ? "Not yet" : "Open"
        case "weeks": return "\(min(2, s.week - b["week"].int)) of 2 weeks"
        case "hire": return staffCount(s) > b["staff"].int ? "Done" : "Not yet"
        case "cmp": return "\(openComplaints(s)) still open"
        case "grow": return (nw >= b["nw"].double ? "+" : "-") + cur.display(abs(nw - b["nw"].double)) + " of " + cur.display(b["nw"].double * 0.01) + " so far"
        default: return ""
        }
    }

    /// Today's goal; a new one is picked when the real day changes, and the streak grows the first time it is seen done.
    /// `today` and `yesterday` are "yyyy-m-d" (the phone's own date).
    public static func dailyGoal(_ s: inout GameState, today: String, yesterday: String, data: GameData, currency cur: Currency) -> DailyGoal? {
        if dailyGoalsOff(s) { return nil }
        var d = s.rest["dy59"] ?? .object(["streak": 0, "last": ""])
        let nw = Valuation.netWorth(s, trades: data.catalog).total
        if d["d"].string != today {
            let fit = dailyIDs.filter { dailyFits($0.id, s) }
            let h = today.split(separator: "-").reduce(7) { ($0 * 31 + (Int($1) ?? 0)) & 0x7fffffff }
            d["d"] = .string(today); d["got"] = 0
            d["k"] = .string(fit.isEmpty ? "grow" : fit[h % fit.count].id)
            d["b"] = .object(["week": .number(Double(s.week)), "staff": .number(Double(staffCount(s))), "cmp": .number(Double(openComplaints(s))), "nw": .number(nw)])
            s.rest["dy59"] = d
        }
        let id = d["k"].string
        guard let g = dailyIDs.first(where: { $0.id == id }) ?? dailyIDs.first(where: { $0.id == "grow" }) else { return nil }
        var streak = d["last"].string == yesterday || d["last"].string == today ? d["streak"].int : 0
        let counted = d["got"].int != 0
        let done = counted || dailyDone(g.id, d["b"], s, nw: nw)
        if done && !counted {
            streak += 1
            d["streak"] = .number(Double(streak)); d["last"] = .string(today); d["got"] = 1
            s.rest["dy59"] = d
        }
        return DailyGoal(id: g.id, title: g.title, progress: dailyProgress(g.id, d["b"], s, nw: nw, cur), done: done, streak: streak)
    }

    /// Missions are optional: a player who turns them off sees no daily goal. The key exists only once it was set.
    public static func dailyGoalsOff(_ s: GameState) -> Bool { (s.rest["dy59"]?["off"].int ?? 0) != 0 }

    public static func setDailyGoalsOff(_ s: inout GameState, _ off: Bool) {
        var d = s.rest["dy59"] ?? .object(["streak": 0, "last": ""])
        if off { d["off"] = .number(1) } else if !d["off"].isNull { d["off"] = .number(0) }
        s.rest["dy59"] = d
    }

    // MARK: Facts the ladder reads

    static func stepsLive(_ s: GameState) -> [Company] { s.companies.filter { $0.status.isLive && $0.type != "hold" } }

    /// Has the player done this early thing? Ids: co, staff, open, week, sell, ad, inbox, pay, profit, mgr. The ladder goals are built on these.
    public static func stepDone(_ id: String, _ s: GameState) -> Bool {
        let L = stepsLive(s)
        switch id {
        case "co": return !L.isEmpty
        case "staff": return L.contains { !$0.staff.isEmpty }
        case "open": return L.contains { $0.status == .open }
        case "week": return !((s.rest["reports"]?[ReportKind.week.storeKey] ?? .null).array.isEmpty)
        case "sell": return L.contains { $0.priceLevel != 0 || $0.value("knob").object.values.contains { $0.double != 0 } }
        case "ad": return L.contains { $0.value("mkt").object.values.contains { $0["b"].double > 0 } }
        // Answered by the player: a real pick, not an expired decision (pick -1 or the default taken) and not one a manager decided.
        case "inbox": return s.inbox.contains { !$0.options.isEmpty && $0.value("pick").int >= 0 && !$0.value("pick").isNull && !$0.flag("auto") && $0.value("mgrName").isNull }
        case "pay": return L.contains { $0.ownerMonthlySalary > 0 || $0.distributed > 0 }
        case "profit": return L.contains { $0.monthlyHistory.contains { $0.profit > 0 } }
        case "mgr": return L.contains { $0.managerID != nil || !$0.value("asst").isNull }
        default: return false
        }
    }

    // MARK: Ladder M1 to M10

    /// One goal of the linear ladder: the spine of the first 90 days. Exactly one is open at a time.
    public struct LadderGoal: Equatable, Sendable {
        public var id: String, title: String, body: String
        /// Button label and the screen it opens ("" when the goal has none).
        public var button: String, link: String
        /// Sentence for the week report when the goal finishes in the period ("You hired your first worker.").
        public var pastTense: String
        /// What finishing the goal changes, in words ("" when it changes nothing).
        public var reward: String
        public var done: Bool
    }

    /// Weeks after M9 when M10 completes by itself if no bad week came: the player has kept the lights on all that time.
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
        ("M9", "Open a second company", "Pick a trade and see the full start-up cost before you decide.", "New company", "newCompany", "You opened a second company.", "World ranking unlocks"),
        ("M10", "Survive a bad week", "Something will go wrong. Keep the lights on.", "", "", "You survived a bad week.", "Your credit score goes up a little"),
    ]

    /// Start the ladder on a new game (older saves have none and nothing is gated). Adds `rest["ldr"]` = { done: { "M1": week, ... } }.
    public static func startLadder(_ s: inout GameState) { s.rest["ldr"] = .object(["done": .object([:])]) }

    /// Is this ladder goal's condition met right now? (The ladder only looks at the open one, so earlier work counts.)
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
        case "M9": return stepsLive(s).count >= 2
        case "M10":
            // Nothing else waits on this goal: it finishes when a bad week was survived, or on its own once enough quiet weeks have passed.
            let since: Int = s.rest["ldr"]?["done"]["M9"]["w"].int ?? s.week
            if s.week >= since + quietWeeksForM10 { return true }
            // A bad event that cost money in a closed week, and every company still has money in the bank two weeks later.
            let weeks = Reports.stored(s, .week)
            guard let hit = weeks.first(where: { r in r.group.events.contains { $0.tone == "bad" } && r.group.pnl.fines + r.group.pnl.losses > 0 }) else { return false }
            return s.week >= hit.id + 2 && stepsLive(s).allSatisfy { $0.cash >= 0 }
        default: return false
        }
    }

    /// All ten goals with their state; nil when the game has no ladder.
    public static func ladder(_ s: GameState) -> [LadderGoal]? {
        guard let l = s.rest["ldr"] else { return nil }
        return ladderList.map { LadderGoal(id: $0.id, title: $0.title, body: $0.body, button: $0.button, link: $0.link, pastTense: $0.past, reward: $0.reward, done: !l["done"][$0.id].isNull) }
    }

    /// The one open goal; nil after M9 (M10 finishes quietly in the background, so no card asks for it) or without a ladder.
    public static func currentLadderGoal(_ s: GameState) -> LadderGoal? { ladder(s)?.first { !$0.done && $0.id != "M10" } }

    /// The past tense of the first goal finished in the weeks `first...last` (for the story sentence of a report), nil if none.
    public static func ladderPastTense(_ s: GameState, firstWeek: Int, lastWeek: Int) -> String? {
        guard let d = s.rest["ldr"]?["done"] else { return nil }
        let hit = ladderList.filter { !d[$0.id].isNull && d[$0.id]["w"].int >= firstWeek && d[$0.id]["w"].int <= lastWeek }
        return hit.first?.past
    }

    /// Finish every goal whose turn has come and whose condition holds (several can fall at once), apply its reward once. Returns the ids finished.
    @discardableResult
    public static func ladderSweep(_ s: inout GameState, currency cur: Currency) -> [String] {
        guard s.rest["ldr"] != nil else { return [] }
        var finished: [String] = []
        for g in ladderList where s.rest["ldr"]?["done"][g.id].isNull ?? true {
            guard ladderCondition(g.id, s) else { break }
            var l = s.rest["ldr"] ?? .object([:])
            var d = l["done"]; d[g.id] = .object(["w": .number(Double(s.week))]); l["done"] = d
            s.rest["ldr"] = l
            let line: String = ladderReward(&s, g.id, cur)
            if !line.isEmpty { s.note(line, tone: "good") }
            Celebrations.add(&s, kind: "goal", title: g.title, detail: g.past, reward: g.reward, art: "goal." + g.id, tier: 1)   // a goal completion celebrates
            finished.append(g.id)
        }
        return finished
    }

    /// Applies the reward of a finished goal and returns the line for the report ("" when the goal changes nothing). Rewards are real
    /// consequences (credit score, reputation, awareness, an opened feature), never cash.
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
            var l = s.rest["ldr"] ?? .object([:]); l["amb"] = 1; s.rest["ldr"] = l   // the ambition card may appear now
            return "A profitable month: the bank offers you better terms."
        case "M8":
            each { $0.reputation = min(100, $0.reputation + 2) }
            var l = s.rest["ldr"] ?? .object([:]); l["classic"] = 1; s.rest["ldr"] = l   // the app turns this into `ledger.classicStartUnlocked`
            return "A company that runs without you looks steadier: customers and suppliers think better of it."
        case "M9":
            var l = s.rest["ldr"] ?? .object([:]); l["rank"] = 1; s.rest["ldr"] = l   // world ranking opens
            return "The world ranking is open to you."
        case "M10": s.credit = min(100, s.credit + 3); return "Lenders see that you came through a hard stretch: your credit score is a little better."
        default: return ""   // M5 and M6 are their own reward
        }
    }

    /// A flag the ladder raised: "amb" (M7, ambition card), "classic" (M8, classic start) or "rank" (M9, world ranking).
    public static func ladderFlag(_ s: GameState, _ key: String) -> Bool { s.rest["ldr"].map { $0[key].int != 0 } ?? false }
}
