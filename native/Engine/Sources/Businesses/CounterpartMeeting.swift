import Foundation
import GameCore
import Finance

/// The one rule behind every "meet someone" button: a supplier lunch, a rival lunch, a key-account dinner and the manager meeting.
/// A meeting can be repeated only after a cool-down (four weeks), costs a set amount from your cash if it costs anything (the caller
/// passes the already-scaled amount and the statement label), and then does what is particular to the counterpart (`effect`: warm a
/// relationship, stamp the week, write the manager's message). The callers keep their own results and their own numbers.
enum CounterpartMeeting {
    static let cooldownWeeks = 4

    enum Outcome: Equatable { case ok, wait, cash }

    /// Whether the last meeting (a week number, nil if never) is still too recent. The board's "call a meeting" uses it with 3 weeks.
    static func isCoolingDown(lastWeek: Double?, now week: Int, weeks: Int = cooldownWeeks) -> Bool {
        guard let last = lastWeek else { return false }
        return Double(week) - last < Double(weeks)
    }

    /// Meet: `.wait` while cooling down, `.cash` if you cannot pay (cost nil: the meeting is free), else pay and run `effect`.
    static func meet(_ s: inout GameState, lastWeek: Double?, cost: Double?, label: String, companyID: Int = 0,
                     effect: (inout GameState) -> Void) -> Outcome {
        if isCoolingDown(lastWeek: lastWeek, now: s.week) { return .wait }
        if let cost = cost {
            if s.cash < cost { return .cash }
            Payments.playerPays(&s, cost, label: label, companyID: companyID)
        }
        effect(&s)
        return .ok
    }
}
