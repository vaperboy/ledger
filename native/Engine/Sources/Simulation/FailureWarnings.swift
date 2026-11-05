import Foundation
import GameCore
import Finance
import Businesses

/// A company about to be sold by its creditors says so first: a red alert, once every four weeks, while there is still
/// time to put money in, cut costs or talk to the bank. The sale itself is `Failure.bankrupt`.
public extension Failure {
    static func warn(_ s: inout GameState, context: FinanceContext) {
        for i in s.companies.indices {
            let c = s.companies[i]
            guard c.status == .open || c.status == .closed else { continue }
            var left: Int? = nil
            var why = ""
            if c.weeksNegative > 8 && c.cash < -context.overdraftRoom(c, s) {
                left = max(1, 13 - c.weeksNegative)
                why = "its account has been overdrawn past its limit for \(c.weeksNegative) weeks"
            }
            let call = c.int("loanCall")
            if call > 0 && call - s.week <= 3 {
                left = min(left ?? 99, max(0, call - s.week))
                why = "the bank has called its loan and it has not caught up"
            }
            guard let weeks = left else { continue }
            let last = c.int("warnW")
            if last != 0 && s.week + 1 - last < 4 { continue }   // stored as week + 1 so that week 0 counts
            s.companies[i].set("warnW", s.week + 1)
            let when = weeks <= 1 ? "this week or next" : "in about \(weeks) weeks"
            let id = s.addMessage(from: "Creditors", title: "\(c.name) is about to be sold",
                                  body: "Unless something changes, its creditors will force a sale \(when): \(why). Put money in, cut costs or talk to the bank now.",
                                  companyID: c.id, tone: "bad")
            if let k = s.inbox.firstIndex(where: { $0.id == id }) { s.inbox[k].isAlert = true }
        }
    }
}
