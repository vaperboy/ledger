import Foundation
import GameCore
import Finance

enum CounterpartMeeting {
    static let cooldownWeeks = 4

    enum Outcome: Equatable { case ok, wait, cash }

    static func isCoolingDown(lastWeek: Double?, now week: Int, weeks: Int = cooldownWeeks) -> Bool {
        guard let last = lastWeek else { return false }
        return Double(week) - last < Double(weeks)
    }

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
