import Foundation
import GameCore
import Businesses
import Events

public enum PlayStreak {
    public static func record(_ s: inout GameState, today: Int) {
        let last: Int = s.rest["playStreak"]?["d"].int ?? Int.min
        var n: Int = s.rest["playStreak"]?["n"].int ?? 0
        if today == last { return }
        n = (last != Int.min && today == last + 1) ? n + 1 : 1
        s.rest["playStreak"] = .object(["d": .number(Double(today)), "n": .number(Double(n))])
    }

    public static func current(_ s: GameState, today: Int) -> Int {
        guard let p = s.rest["playStreak"] else { return 0 }
        let gap: Int = today - p["d"].int
        return (gap == 0 || gap == 1) ? p["n"].int : 0
    }

    public static let showFrom: Int = 3
}

public enum SessionHooks {
    public struct Reminder: Equatable, Sendable {
        public var id: String, title: String, body: String
        public var after: Double
    }

    static let banned: [String] = ["luxury", "award", "rival", "offer", "buy", "bid", "acqui", "sale", "weekly plan"]

    static func expiring(_ s: GameState) -> (message: Message, weeksLeft: Int)? {
        let open: [Message] = s.inbox.filter { m in
            guard m.status == "open", let e = m.expiresWeek, e > s.week else { return false }
            let t: String = m.title.lowercased()
            return !banned.contains { t.contains($0) }
        }
        guard let m = open.min(by: { ($0.expiresWeek ?? 0) < ($1.expiresWeek ?? 0) }) else { return nil }
        return (m, (m.expiresWeek ?? s.week) - s.week)
    }

    public static func reminders(_ s: GameState, now: Date = Date()) -> [Reminder] {
        var out: [Reminder] = []
        let days: Int = PlayerGoals.streakInfo(s, now: now).count
        let lead: String = days >= 2 ? "Day \(days) streak. " : ""
        if let hit = expiring(s) {
            let who: String = s.companies.first(where: { $0.id == hit.message.companyID })?.name ?? s.companies.first?.name ?? "Ledger"
            let weeks: String = hit.weeksLeft == 1 ? "1 week left" : "\(hit.weeksLeft) weeks left"
            out.append(Reminder(id: "ledger.expiry", title: who, body: lead + "\(who): \(hit.message.title). \(weeks).", after: 20 * 3600))
        }
        if let g = PlayerGoals.currentLadderGoal(s) {
            out.append(Reminder(id: "ledger.goal", title: g.title, body: lead + g.body, after: 48 * 3600))
        }
        if out.isEmpty, DeskStories.isOpen(s) {
            out.append(Reminder(id: "ledger.idle", title: "The Desk", body: lead + "A small question is waiting on your desk.", after: 22 * 3600))
        } else if out.isEmpty, let name = s.companies.first?.name {
            out.append(Reminder(id: "ledger.idle", title: name, body: lead + "\(name) is waiting for its next day.", after: 7 * 86400))
        }
        if let v = JointVenture.pendingVote(s) {
            let left: String = v.weeksLeft <= 0 ? "Voting closes this week." : v.weeksLeft == 1 ? "1 week left to vote." : "\(v.weeksLeft) weeks left to vote."
            out.append(Reminder(id: v.urgent ? "ledger.jv.urgent" : "ledger.jv.planned", title: v.companyName,
                                body: v.urgent ? "Emergency meeting: \(v.reason). \(left)" : "Board meeting waits for your vote. \(left) A vote not cast counts as an abstention.",
                                after: v.urgent ? 3 * 3600 : 20 * 3600))
        }
        return out
    }

    public static func cliffhanger(_ s: GameState) -> Bool {
        guard let hit = expiring(s) else { return false }
        return hit.weeksLeft <= 2
    }
}
