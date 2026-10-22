import Foundation
import GameCore

/// What can happen to a team member in a week.
public enum StaffEvent: Equatable, Sendable {
    case quit(staffID: Int)           // hands in notice
    case sick(staffID: Int)
    case leave(staffID: Int)          // notice period over: gone
    case payAsk(staffID: Int)
    case fixedSalaryAsk(staffID: Int)
    case problem(staffID: Int, trait: String)
}

/// Weekly staff dynamics: tiredness, sickness, quitting, trait problems. Original: `staffWeek`, `tireWeek`, `quitOdds`.
public enum StaffWeek {
    /// Median years with the same employer by trade family (BLS, January 2024). Original: `TENURE_Y`.
    static let tenureYears: [String: Double] = ["venue": 2.1, "retail": 3.1, "svc": 3.5, "logi": 3.7, "project": 4.2, "fin": 4.7,
                                                "prod": 4.9, "energy": 5.7, "rent": 4.2, "club": 3, "hold": 4.7]
    static let personalityFactor: [String: Double] = ["loyal": 0.5, "steady": 0.75, "driven": 1.1, "restless": 1.8, "arrogant": 1.2, "lazy": 1]

    /// Per person and trade: some stay for years, some move on fast. Stable. Original: `staffFit`.
    public static func fit(staff s: StaffMember, tradeID: String) -> Double {
        if let f = s.raw["fit"], !f.isNull { return f.double }
        let u = HashedRandom.first("fit:\(s.id):\(tradeID)")
        return u < 0.15 ? 0.25 : u < 0.8 ? 0.7 + (u - 0.15) * 0.6 : 2
    }

    /// Weekly chance a person quits. Original: `quitOdds`.
    public static func quitOdds(family: String, tradeID: String, staff s: StaffMember, person n: Person, payGap gap: Double, tenure ten: Double,
                                week: Int, hasHRManager: Bool, hasTeamLead: Bool) -> Double {
        let T = tenureYears[family] ?? 3.5
        let h0 = M_LN2 / (52 * T)
        let tenF = ten < 13 ? 1.6 : ten < 104 ? 1 : ten < 260 ? 0.7 : 0.5
        let persF = personalityFactor[n.str("pers")] ?? 1
        let denied = s.raw["denied"].map { !$0.isNull && $0.double != 0 && Double(week) - $0.double < 26 } ?? false
        let payF = 1 + max(0, gap) * 2.5 + (denied ? 0.8 : 0)
        let happy = s.happyUntilWeek != 0 && week < s.happyUntilWeek ? 0.4 : 1.0
        return h0 * tenF * fit(staff: s, tradeID: tradeID) * persF * payF * (hasHRManager ? 0.75 : 1) * (hasTeamLead ? 0.8 : 1) * happy
            * (1 + max(0, s.tiredness - 50) / 25)
    }

    /// A week of work: tiredness up or down; a worn-out person may fall sick for a week. Original: `tireWeek`.
    /// `hoursWorked` is the person's hours, stretched when the place ran over capacity.
    /// Tiredness grows with hours over `from` (the standard week of the country, 40 at most) and falls below it.
    public static func tire(_ s: inout StaffMember, hoursWorked h: Double, from t: Double = 40, week: Int, random r: inout DeterministicRandom) -> Bool {
        if s.isOffSeason { s.tiredness = max(0, s.tiredness - 20); return false }
        if StaffModel.isSick(s, week: week) { return false }
        let t0 = s.tiredness
        let stamina = StaffModel.staminaFactor[StaffModel.staminaType(s)] ?? 1
        s.tiredness = h > t ? min(100, t0 + (h - t) * 1.2 * stamina) : max(0, t0 - (t - h) * 0.6 - 6)
        s.set("hw", jsRound(h))
        if s.tiredness > 60 && r.chance((s.tiredness - 60) / 400) {
            s.sickUntilWeek = week + 1
            s.tiredness = max(0, s.tiredness - 35)
            return true
        }
        return false
    }

    /// Hours someone really worked last week: their hours, stretched when the place ran over capacity.
    /// People only work overtime when people are what limits the business. Original: `workedHours`.
    public static func hoursWorked(_ s: StaffMember, utilisation u: Double, limitedByPeople: Bool) -> Double {
        let contracted = s.weeklyHours ?? s.num("wh", StaffModel.fullWeekHours)
        return limitedByPeople ? contracted * max(1, min(1.25, u)) : contracted
    }
}
