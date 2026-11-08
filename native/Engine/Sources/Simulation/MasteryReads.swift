import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// One lever a good operator pulls, as a row of the Stats app's "How you are playing" panel.
public struct PlayingRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// The reading, in words where the thing cannot be measured exactly.
    public var value: String
    /// One line on why it matters.
    public var why: String
    /// "good", "ok" or "weak": how the lever looks now.
    public var tone: String
}

/// The two-second card shown when the player comes back: what changed since the game was last seen.
public struct ReturnRecap: Equatable, Sendable {
    public var title: String
    public var lines: [String]
    public var isEmpty: Bool { lines.isEmpty }
}

public extension GameEngine {
    // MARK: Delegation

    /// Decisions raised in the weeks `firstWeek...lastWeek`: how many in all, how many your team handled, how many reached you.
    func delegationCounts(firstWeek: Int, lastWeek: Int) -> (total: Int, team: Int, you: Int) {
        let all = state.inbox.filter { !$0.options.isEmpty && $0.companyID != 0 && $0.week >= firstWeek && $0.week <= lastWeek }
        let team = all.filter { !$0.handledBy.isEmpty || !$0.value("mgrName").isNull }.count
        return (all.count, team, all.count - team)
    }

    /// The delegation line of a report ("Decisions this week: 7. Handled by your team: 5. Escalated to you: 2."); empty when none were raised.
    func delegationLine(firstWeek: Int, lastWeek: Int, period: String = "this week") -> String {
        let c = delegationCounts(firstWeek: firstWeek, lastWeek: lastWeek)
        guard c.total > 0 else { return "" }
        return "Decisions \(period): \(c.total). Handled by your team: \(c.team). Escalated to you: \(c.you)."
    }

    // MARK: How you are playing

    /// The levers a good operator pulls, each with its reading and why it matters. Unmeasurable things are in words.
    func playingPanel() -> [PlayingRow] {
        let s = state
        var rows: [PlayingRow] = []

        let c = delegationCounts(firstWeek: max(0, s.week - 12), lastWeek: s.week)
        let hasTeam = s.companies.contains { $0.status == .open && $0.managerID != nil }
        if c.total == 0 {
            rows.append(PlayingRow(id: "delegation", title: "Delegation coverage", value: hasTeam ? "Nothing to hand over yet" : "No team yet", tone: hasTeam ? "ok" : "weak",
                                   why: "Managers who take routine decisions leave you the few that only you can make."))
        } else {
            let share = Double(c.team) / Double(c.total)
            rows.append(PlayingRow(id: "delegation", title: "Delegation coverage", value: "\(c.team) of \(c.total) decisions by your team", tone: share >= 0.6 ? "good" : share >= 0.25 ? "ok" : "weak",
                                   why: "Managers who take routine decisions leave you the few that only you can make."))
        }

        let mgr = s.companies.filter { $0.status == .open && $0.managerID != nil && $0.type != "hold" }
        let qs: [Double] = mgr.compactMap { co in data.catalog[co.type].map { ManagerModel.quality(co, $0, people: s.people) } }
        if qs.isEmpty {
            rows.append(PlayingRow(id: "managers", title: "Manager quality", value: "No managers yet", tone: "weak", why: "A good manager decides as you would, so delegating costs little."))
        } else {
            let q = qs.reduce(0, +) / Double(qs.count)
            rows.append(PlayingRow(id: "managers", title: "Manager quality", value: q >= 0.7 ? "Strong" : q >= 0.5 ? "Solid" : "Weak", tone: q >= 0.7 ? "good" : q >= 0.5 ? "ok" : "weak",
                                   why: "A good manager decides as you would, so delegating costs little."))
        }

        let brand = BrandValue.group(s).score
        rows.append(PlayingRow(id: "brand", title: "Brand value", value: brand < 20 ? "Unknown" : brand < 40 ? "Known locally" : brand < 60 ? "Respected" : brand < 80 ? "Trusted" : "A household name",
                               tone: brand >= 60 ? "good" : brand >= 30 ? "ok" : "weak", why: "A name people trust lifts prices, sale value and franchise fees."))

        let band = Banking.creditBand(s.credit)
        let bandWord: [String: String] = ["A": "A: lenders compete", "B": "B: good terms", "C": "C: fair terms", "D": "D: dear credit", "E": "E: lenders hesitate"]
        rows.append(PlayingRow(id: "credit", title: "Credit band", value: bandWord[band] ?? band, tone: band <= "B" ? "good" : band == "C" ? "ok" : "weak",
                               why: "Pay on time and borrowing gets cheaper; a late payment is remembered."))

        let open = s.companies.filter { $0.status == .open && $0.type != "hold" }.flatMap { Satisfaction.openComplaints($0) }
        if open.isEmpty {
            rows.append(PlayingRow(id: "complaints", title: "Complaint answers", value: "Nothing waiting", tone: "good", why: "A complaint answered fast usually turns into a customer who stays."))
        } else {
            let age = Double(open.reduce(0) { $0 + max(0, s.week - $1["w"].int) }) / Double(open.count)
            rows.append(PlayingRow(id: "complaints", title: "Complaint answers", value: age <= 1 ? "Answered within days" : age <= 3 ? "Slowing down" : "Piling up", tone: age <= 1 ? "good" : age <= 3 ? "ok" : "weak",
                                   why: "A complaint answered fast usually turns into a customer who stays."))
        }
        return rows
    }

    // MARK: Seed

    /// The text for the game-over screen: the number another player can start the same world with.
    var seedLine: String { "Seed \(state.seed). Start a new game with this number to play the same world." }

    // MARK: Streak and daily goal reads

    /// The daily-goal streak (read only): count, best, protection tokens, earned title and the next milestone.
    func streakInfo(now: Date = Date()) -> PlayerGoals.StreakInfo { PlayerGoals.streakInfo(state, now: now) }

    /// The app opened a Phone app; a daily goal that watches it counts it. True when something was recorded.
    mutating func noteVisit(app: String, now: Date = Date()) -> Bool {
        var changed = false
        update { s, _, _ in changed = PlayerGoals.noteVisit(&s, app: app, today: PlayerGoals.dayKey(now)) }
        return changed
    }

    // MARK: Return recap

    /// The game day as one number (week * 7 + day): the unit of `lastSeenDay`.
    var gameDayNumber: Int { state.week * 7 + state.day }

    /// Remember what the player has seen: the game day, how many rivals share the markets, and the open decisions.
    mutating func markSeen() {
        let day = gameDayNumber, rivals = Self.rivalCount(state)
        update { s, _, _ in s.rest["seen"] = .object(["d": .number(Double(day)), "riv": .number(Double(rivals))]) }
    }

    /// The game day recorded by `markSeen`, nil when none.
    var lastSeenDay: Int? { state.rest["seen"].map { $0["d"].int } }

    internal static func rivalCount(_ s: GameState) -> Int {
        var keys = Set<String>()
        var n = 0
        for co in s.companies where co.status == .open && co.type != "hold" && keys.insert(Rivals.key(co)).inserted { n += Rivals.rivals(s, for: co).count }
        return n
    }

    /// What changed since `lastSeenDay`: days played, decisions that ran out and took the default, rivals that came or went, a Saturday next,
    /// and a decision about to expire. At most four lines; nil when there is nothing to say.
    func sinceYouLeft(lastSeenDay: Int) -> ReturnRecap? {
        let s = state
        var lines: [String] = []
        let passed = gameDayNumber - lastSeenDay
        let seenWeek = lastSeenDay / 7
        if passed > 0 { lines.append(passed == 1 ? "One day has passed." : "\(passed) days have passed.") }
        let expired = s.inbox.filter { $0.flag("auto") && $0.status == "done" && !$0.options.isEmpty && ($0.expiresWeek ?? -1) > seenWeek && ($0.expiresWeek ?? -1) <= s.week }.count
        if expired > 0 { lines.append(expired == 1 ? "One decision ran out and took the default answer." : "\(expired) decisions ran out and took the default answer.") }
        if let before = s.rest["seen"]?["riv"], !before.isNull {
            let now = Self.rivalCount(s), was = before.int
            if now > was { lines.append(now - was == 1 ? "A new rival has opened in your markets." : "\(now - was) new rivals have opened in your markets.") }
            if now < was { lines.append(was - now == 1 ? "A rival has left your markets." : "\(was - now) rivals have left your markets.") }
        }
        let soon = s.inbox.filter { $0.status == "open" && !$0.options.isEmpty && ($0.expiresWeek.map { $0 - s.week <= 1 } ?? false) }.count
        if soon > 0 { lines.append(soon == 1 ? "One decision expires within a week." : "\(soon) decisions expire within a week.") }
        if GameCalendar.date(week: s.week, dayOffset: s.day + 1).weekday == 5 { lines.append("Saturday trading is next: the busiest day for shops and venues.") }
        guard !lines.isEmpty else { return nil }
        return ReturnRecap(title: "Since you left", lines: Array(lines.prefix(4)))
    }
}
