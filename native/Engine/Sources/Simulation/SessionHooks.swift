import Foundation
import GameCore

/// Brief Part 7.3: the number of consecutive calendar days with at least one game day played. Stored as `rest["playStreak"]`
/// = { d: calendar day number of the last day played, n: count }. No reward, no penalty; the app shows it from 3 up.
public enum PlayStreak {
    /// Records one game day played on calendar day `today` (any whole-number day count, for example days since 1970 in the local calendar).
    public static func record(_ s: inout GameState, today: Int) {
        let last: Int = s.rest["playStreak"]?["d"].int ?? Int.min
        var n: Int = s.rest["playStreak"]?["n"].int ?? 0
        if today == last { return }
        n = (last != Int.min && today == last + 1) ? n + 1 : 1
        s.rest["playStreak"] = .object(["d": .number(Double(today)), "n": .number(Double(n))])
    }

    /// The streak as of `today`: the saved count if the last day played was today or yesterday, else 0 (the run is over).
    public static func current(_ s: GameState, today: Int) -> Int {
        guard let p = s.rest["playStreak"] else { return 0 }
        let gap: Int = today - p["d"].int
        return (gap == 0 || gap == 1) ? p["n"].int : 0
    }

    /// Smallest streak the Home week strip shows.
    public static let showFrom: Int = 3
}

/// Brief Part 7.1 and 7.2: what the app may remind the player of, as pure data. The app turns each plan into one local notification.
public enum SessionHooks {
    public struct Reminder: Equatable, Sendable {
        public var id: String, title: String, body: String
        /// Seconds after the app goes to the background.
        public var after: Double
    }

    static let banned: [String] = ["luxury", "award", "rival", "offer", "buy", "bid", "acqui", "sale"]

    /// The open Inbox decision with the soonest expiry (no talk of luxury, awards, rivals or offers to buy); nil when none.
    static func expiring(_ s: GameState) -> (message: Message, weeksLeft: Int)? {
        let open: [Message] = s.inbox.filter { m in
            guard m.status == "open", let e = m.expiresWeek, e > s.week else { return false }
            let t: String = m.title.lowercased()
            return !banned.contains { t.contains($0) }
        }
        guard let m = open.min(by: { ($0.expiresWeek ?? 0) < ($1.expiresWeek ?? 0) }) else { return nil }
        return (m, (m.expiresWeek ?? s.week) - s.week)
    }

    /// The reminders for a player who has just left the app. The third only when neither of the first two applies.
    public static func reminders(_ s: GameState) -> [Reminder] {
        var out: [Reminder] = []
        if let hit = expiring(s) {
            let who: String = s.companies.first(where: { $0.id == hit.message.companyID })?.name ?? s.companies.first?.name ?? "Ledger"
            let weeks: String = hit.weeksLeft == 1 ? "1 week left" : "\(hit.weeksLeft) weeks left"
            out.append(Reminder(id: "ledger.expiry", title: who, body: "\(who): \(hit.message.title). \(weeks).", after: 20 * 3600))
        }
        if let g = PlayerGoals.currentLadderGoal(s) {
            out.append(Reminder(id: "ledger.goal", title: g.title, body: g.body, after: 48 * 3600))
        }
        if out.isEmpty, let name = s.companies.first?.name {
            out.append(Reminder(id: "ledger.idle", title: name, body: "\(name) is waiting for its next day.", after: 7 * 86400))
        }
        return out
    }

    /// Brief 7.2: is an open decision due within 2 weeks? (After Continue, Home scrolls to Needs you and the expiry pill pulses once.)
    public static func cliffhanger(_ s: GameState) -> Bool {
        guard let hit = expiring(s) else { return false }
        return hit.weeksLeft <= 2
    }
}
