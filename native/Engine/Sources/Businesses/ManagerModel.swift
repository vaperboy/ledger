import Foundation
import GameCore
import Countries
import Employees
import Finance

/// How good the company's manager is. Original: `mgrQualCore` (engine/people/people.js), 0 ... 1.
public enum ManagerModel {
    /// Stats are 0-100: ops, people, sales, fin, risk, ethic. Fit depends on the manager's type against the trade's.
    public static func quality(_ co: Company, _ bd: Trade, people: [Int: Person]) -> Double {
        guard let id = co.managerID, let n = people[id] else { return 0 }
        let st = n.value("stats")
        let q = (0.34 * st["ops"].double + 0.18 * st["people"].double + 0.2 * st["sales"].double + 0.17 * st["fin"].double + 0.11 * st["risk"].double) / 100
        let type = n.str("mtype")
        let fitTable: [String: Double] = ["gen": 0.8, "ops": 0.75, "host": 0.6, "site": 0.6, "sales": 0.7, "tech": 0.6, "fin": 0.6, "ind": 0.55,
                                          "fleet": 0.55, "prop": 0.55, "fund": 0.45, "energy": 0.5, "pro": 0.55, "retail": 0.65, "game": 0.4, "clin": 0.5]
        let fit: Double = type == bd.managerType ? 1 : type == "gen" ? 0.85 : (fitTable[type] ?? 0.6) * 0.9
        let mood = co.value("mood").isNull ? 60 : co.num("mood")
        var v = clamp(q * fit * (0.88 + 0.24 * mood / 100), 0.05, 1)
        // A managing director coaches the manager (ManagerTeam).
        let coach = co.num("mdCoach")
        if coach > 0 { v = min(1, v + coach) }
        // Bosses above lift (or drag) every manager under them (ManagerTeam.teamWeek).
        if !co.value("mgrLift").isNull { v = clamp(v * co.num("mgrLift"), 0.05, 1) }
        // A manager nobody has met for months slips; a boss above halves the pace. Original step: 'owner attention' (OA59).
        let drift = co.num("drift56")
        if drift > 0 { v *= 1 - drift }
        return clamp(v, 0.05, 1)
    }
}
