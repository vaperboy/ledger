import Foundation
import GameCore
import Countries
import Employees

public enum StaffExtras {
    public struct Outcome {
        public var fines: [(amount: Double, note: String)] = []
        public var reputationLoss = 0.0
        public var notes: [(text: String, tone: String)] = []
        public var left = false
    }

    public static func week(_ m: inout StaffMember, person n: inout Person, week: Int, random r: inout DeterministicRandom, companyUtilisation util: Double?, canLeave: Bool = true) -> Outcome {
        var out = Outcome()
        if m.commissionMode == "com" {
            if r.chance(0.003) {
                let f = jsRound(r.range(10000, 40000))
                out.fines.append((f, "A customer complaint about pushy selling by \(n.name) cost {co} {fine}."))
                out.reputationLoss += 1.5
            }
            if r.chance(0.004 + ((util ?? 1) < 0.5 ? 0.01 : 0)) && canLeave {
                out.notes.append(("\(n.name) left {co} after a slow month on commission.", "bad"))
                out.left = true
                return out
            }
        }
        let goodCharacter = ["driven", "steady", "loyal"].contains(n.str("pers"))
        if n.flag("golden") && goodCharacter && (week - m.hiredWeek) % 4 == 3 {
            m.skillGain = clamp(m.skillGain + 1.6, -10, 30)
            if week - m.hiredWeek == 19 && !n.flag("rev") {
                n.set("rev", 1)
                out.notes.append(("\(n.name) at {co} is turning into a real star.", "good"))
            }
        }
        return out
    }
}
