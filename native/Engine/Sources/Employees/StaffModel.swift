import Foundation
import GameCore

/// How staff behave: learning, tiredness, sickness, skill, FTE. Original: engine/people/people.js.
public enum StaffModel {
    public static let fullWeekHours = 37.5
    /// Weeks to get up to speed by learning type. Original: `LEARN_W`.
    static let learnWeeks: [String: Double] = ["quick": 3, "normal": 6, "slow": 12]
    /// How fast people tire. Original: `STAM_F`.
    static let staminaFactor: [String: Double] = ["never": 0, "normal": 1, "quick": 2]

    /// Learning speed, stable per person (from their id). Original: `learnOf`.
    public static func learningType(_ s: StaffMember) -> String {
        if let l = s.raw["learn"]?.string, !l.isEmpty { return l }
        let r = HashedRandom.first("learn:\(s.id)")
        return r < 0.25 ? "quick" : r < 0.75 ? "normal" : "slow"
    }

    /// Stamina, stable per person. Original: `stamOf`.
    public static func staminaType(_ s: StaffMember) -> String {
        if let l = s.raw["stam"]?.string, !l.isEmpty { return l }
        let r = HashedRandom.first("stam:\(s.id)")
        return r < 0.2 ? "never" : r < 0.8 ? "normal" : "quick"
    }

    /// Share of full speed while learning the job (1 once learned). Original: `rampF`.
    public static func rampFactor(_ s: StaffMember, week: Int, person: Person?) -> Double {
        if s.raw["w0"] == nil || s.raw["w0"]!.isNull { return 1 }
        let tenure = Double(week - s.hiredWeek)
        let learn = learnWeeks[learningType(s)] ?? 6
        if tenure >= learn { return 1 }
        let st = clamp(0.4 + (person?.skill ?? 40) / 250, 0.45, 0.8)
        return st + (1 - st) * max(0, tenure) / learn
    }

    /// Tiredness slows people down: from 40 on, down to 70% speed when worn out. Original: `tiredF`.
    public static func tirednessFactor(_ s: StaffMember) -> Double {
        let t = s.tiredness
        return t > 40 ? 1 - (t - 40) / 200 : 1
    }

    public static func isSick(_ s: StaffMember, week: Int) -> Bool {
        if let until = s.sickUntilWeek { return week < until }
        return false
    }

    /// A person's skill 0-100 including what they have learned and their pay plan. Original: `staffSkill`.
    public static func skill(_ s: StaffMember, person: Person?, salesRoles: Set<String>) -> Double {
        guard let p = person else { return 40 }
        var v = p.skill + s.skillGain - (s.num("nr") > 0 ? 10 : 0)
        if let mode = s.commissionMode, salesRoles.contains(s.role) { v += mode == "com" ? 9 : mode == "mix" ? 4 : 0 }
        return clamp(v, 0, 100)
    }

    /// People working a role, in full-time equivalents. Original: `staffFTE`.
    public static func fullTimeEquivalents(role: String, staff: [StaffMember], people: [Int: Person], week: Int, salesRoles: Set<String>) -> Double {
        var t = 0.0
        for s in staff where s.role == role && !s.isOffSeason && !isSick(s, week: week) {
            let skill = StaffModel.skill(s, person: people[s.id], salesRoles: salesRoles)
            var pay = 1.0
            if s.commissionMode != nil && salesRoles.contains(s.role) {
                pay = s.commissionMode == "mix" ? 1.06 : s.commissionMode == "com" ? 1.12 : 1
            }
            let lazy = s.str("flag") == "lazy" ? 0.82 : 1
            t += rampFactor(s, week: week, person: people[s.id]) * tirednessFactor(s) * s.partTimeShare * 0.92 * (0.75 + 0.5 * skill / 100) * lazy * pay
        }
        return t
    }
}
