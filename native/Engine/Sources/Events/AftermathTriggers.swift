import Foundation
import GameCore
import Businesses

extension Aftermath {
    static let lateWindowWeeks = 8

    static func scanTriggers(_ s: inout GameState) {
        for i in s.companies.indices where s.companies[i].status == .open {
            let co = s.companies[i]
            if co.value("lt").array.contains(where: { s.week >= $0.int && s.week - $0.int < lateWindowWeeks }) {
                queue(&s, i, "suppnotice", delay: 1, why: "A supplier has noticed the late payments.")
            }
            let level = Double(co.priceLevel)
            let seen = co.value("flags")["plSeen"]
            if seen.isNull || abs(seen.double - level) > 0.01 {
                EventEngine.setFlag(&s, i, "plSeen", level)
                if !seen.isNull, level < seen.double - 0.5, co.lastWeekUnits > 0.5, jitter(s, co.id, "pw", 3) == 0 {
                    queue(&s, i, "pwreply", delay: 2, why: "A rival may answer your price cut.")
                }
            }
        }
    }
}
