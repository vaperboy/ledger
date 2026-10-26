import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The player's own goals and how they are tracked: the daily goal with its streak, the first-steps checklist, and the
/// (Ambitions live in Businesses/Ambitions.swift.) State lives in `rest["dy59"]`, `rest["fs58"]`.
/// Originals: features/player/daily_goals.js (`DY59`), first_steps.js (`FS58`), ambitions.js (`R27` amb).
public enum PlayerGoals {
    // MARK: Shared facts

    static func live(_ s: GameState) -> [Company] { s.companies.filter { $0.status == .open && $0.type != "hold" } }
    static func staffCount(_ s: GameState) -> Int { live(s).reduce(0) { $0 + $1.staff.count + ($1.managerID != nil ? 1 : 0) } }
    static func openComplaints(_ s: GameState) -> Int { live(s).reduce(0) { $0 + Satisfaction.openComplaints($1).count } }

    // MARK: Daily goal

    public struct DailyGoal: Equatable, Sendable {
        public var id: String, title: String, progress: String
        public var done: Bool, claimed: Bool
        public var reward: Double
        /// Days in a row including today once claimed.
        public var streak: Int
    }

    static let dailyIDs: [(id: String, title: String)] = [
        ("start", "Open your first business"), ("weeks", "Play two weeks"), ("hire", "Hire someone"),
        ("cmp", "Answer the complaints waiting"), ("grow", "Grow your net worth by 1%")]

    static func dailyFits(_ id: String, _ s: GameState) -> Bool {
        switch id {
        case "start": return live(s).isEmpty
        case "weeks", "grow": return !live(s).isEmpty
        case "hire": return live(s).contains { $0.managerID == nil }
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

    /// Today's goal; a new one is picked when the real day changes. `today` and `yesterday` are "yyyy-m-d" (the phone's own date).
    public static func dailyGoal(_ s: inout GameState, today: String, yesterday: String, data: GameData, currency cur: Currency) -> DailyGoal? {
        var d = s.rest["dy59"] ?? .object(["streak": 0, "last": ""])
        let nw = Valuation.netWorth(s, trades: data.catalog).total
        if d["d"].string != today {
            let fit = dailyIDs.filter { dailyFits($0.id, s) }
            let h = today.split(separator: "-").reduce(7) { ($0 * 31 + (Int($1) ?? 0)) & 0x7fffffff }
            d["d"] = .string(today); d["got"] = 0
            d["k"] = .string(fit.isEmpty ? "weeks" : fit[h % fit.count].id)
            d["b"] = .object(["week": .number(Double(s.week)), "staff": .number(Double(staffCount(s))), "cmp": .number(Double(openComplaints(s))), "nw": .number(nw)])
            s.rest["dy59"] = d
        }
        let id = d["k"].string
        guard let g = dailyIDs.first(where: { $0.id == id }) ?? dailyIDs.first(where: { $0.id == "weeks" }) else { return nil }
        let streak = d["last"].string == yesterday || d["last"].string == today ? d["streak"].int : 0
        let reward = cur.roundedStep(max(cur.scaledPrice(2500), nw * 0.0005) * Double(min(7, streak + 1)), about: 500)
        return DailyGoal(id: g.id, title: g.title, progress: dailyProgress(g.id, d["b"], s, nw: nw, cur), done: dailyDone(g.id, d["b"], s, nw: nw),
                         claimed: d["got"].int != 0, reward: reward, streak: streak)
    }

    /// Claim the daily reward. Original: `ACT.dy59claim`.
    @discardableResult
    public static func claimDailyGoal(_ s: inout GameState, today: String, yesterday: String, data: GameData, currency cur: Currency) -> Double? {
        guard let g = dailyGoal(&s, today: today, yesterday: yesterday, data: data, currency: cur), g.done, !g.claimed else { return nil }
        var d = s.rest["dy59"] ?? .object([:])
        d["streak"] = .number(Double(g.streak + 1)); d["last"] = .string(today); d["got"] = 1
        s.rest["dy59"] = d
        Payments.playerReceives(&s, g.reward, label: "Daily goal reached")
        return g.reward
    }

    // MARK: First steps

    public struct FirstStep: Equatable, Sendable {
        public var id: String, title: String, how: String, reward: String
        public var done: Bool, claimed: Bool
    }

    static let stepList: [(id: String, title: String, how: String, reward: String)] = [
        ("co", "Start a business", "New company: pick a trade. The small ones are cheap to start.", "A start-up grant from the town"),
        ("staff", "Hire your first worker", "In the company: Manage, Find workers. Check what they claim before you hire.", "The job centre pays a month of payroll tax"),
        ("open", "Open the doors", "Papers, premises, equipment and people in place: it opens by itself.", "The local paper writes about you"),
        ("week", "Read your week report", "Play until the week ends; the report shows what happened and where the money went.", "The bank likes what it sees"),
        ("sell", "Choose how you sell", "Sales: who you are for, and what else you offer. Or set your prices.", "Word gets around"),
        ("ad", "Run an ad", "Sales, Marketing: even a small campaign brings people in.", "The ad agency refunds your first week"),
        ("inbox", "Answer a decision", "Inbox: problems and offers wait there for your answer.", "People learn they can count on you"),
        ("pay", "Pay yourself", "Money: a salary, a dividend, or take money out. Leave enough for the bills.", "Your accountant's first month is free"),
        ("profit", "Make a profit in a month", "Keep the costs in check and the customers coming.", "Better terms from the bank"),
        ("mgr", "Hire a manager or an assistant", "Manage, Management: they run it day to day while you grow.", "The agency waives its fee"),
    ]

    static func stepsLive(_ s: GameState) -> [Company] { s.companies.filter { $0.status.isLive && $0.type != "hold" } }

    static func stepDone(_ id: String, _ s: GameState) -> Bool {
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

    /// Start the checklist on a new game (older saves do not get it). Original: `FS58.start`.
    public static func startFirstSteps(_ s: inout GameState) { s.rest["fs58"] = .object(["got": .object([:]), "off": 0, "w0": .number(Double(s.week))]) }

    public static func firstSteps(_ s: GameState) -> [FirstStep]? {
        guard let st = s.rest["fs58"] else { return nil }
        return stepList.map { FirstStep(id: $0.id, title: $0.title, how: $0.how, reward: $0.reward, done: stepDone($0.id, s), claimed: !st["got"][$0.id].isNull) }
    }
    public static func firstStepsHidden(_ s: GameState) -> Bool { s.rest["fs58"]?["off"].int ?? 1 != 0 }

    /// Claim the reward of a finished step; returns the line to show. Original: `FS58.claim`, `ACT.fs58claim`.
    public static func claimFirstStep(_ s: inout GameState, id: String, currency cur: Currency) -> String? {
        guard var st = s.rest["fs58"], st["got"][id].isNull, stepList.contains(where: { $0.id == id }), stepDone(id, s) else { return nil }
        var got = st["got"]; got[id] = .object(["w": .number(Double(s.week))]); st["got"] = got; s.rest["fs58"] = st
        func cash(_ v: Double, _ why: String) -> String { let a = cur.scaledPrice(v); Payments.playerReceives(&s, a, label: why); return cur.display(a) }
        func each(_ f: (inout Company) -> Void) { for i in s.companies.indices where s.companies[i].status.isLive && s.companies[i].type != "hold" { f(&s.companies[i]) } }
        switch id {
        case "co": return "The town gives new businesses a small grant: \(cash(25000, "Start-up grant from the town"))."
        case "staff": return "The job centre pays a month of payroll tax for your first hire: \(cash(6000, "Job centre: first hire"))."
        case "open":
            var name = "you"
            if let i = s.companies.firstIndex(where: { $0.status == .open && $0.type != "hold" }) { s.companies[i].awareness = min(100, s.companies[i].awareness + 8); name = s.companies[i].name }
            return "The local paper writes about \(name): more people know the name."
        case "week": s.credit = min(100, s.credit + 3); return "The bank likes a good start: your credit score is a little better."
        case "sell":
            if let i = s.companies.firstIndex(where: { $0.status.isLive && $0.type != "hold" && ($0.priceLevel != 0 || $0.value("knob").object.values.contains { $0.double != 0 }) }) { s.companies[i].awareness = min(100, s.companies[i].awareness + 5) }
            return "People talk about what you offer: more of them know the name."
        case "ad": return "The ad agency refunds your first week: \(cash(3000, "Ad agency: first week refunded"))."
        case "inbox": each { $0.reputation = min(100, $0.reputation + 1) }; return "People learn they can count on you: a little better reputation."
        case "pay": return "Your accountant waives the first month: \(cash(2500, "Accountant: first month free"))."
        case "profit": s.credit = min(100, s.credit + 5); return "A profitable month: the bank offers you better terms."
        default: return "The recruitment agency waives its fee for your first hire: \(cash(15000, "Recruitment agency: fee waived"))."
        }
    }

    public static func setFirstStepsHidden(_ s: inout GameState, _ hidden: Bool) {
        guard var st = s.rest["fs58"] else { return }
        st["off"] = hidden ? 1 : 0
        s.rest["fs58"] = st
    }
}
