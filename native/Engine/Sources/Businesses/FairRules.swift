import Foundation
import GameCore

/// The one rule set every career plays under. Older saves may still carry a "difficulty" key; it is ignored.
public enum FairRules {
    public static let threatScale = 1.0
    public static let rivalSharpness = 1.0
    /// Until this week at most one bad event lands per week.
    public static let badEventCapWeeks = 12

    public static func eventRamp(_ balance: Balance, week: Int) -> Double { balance.eventRampMultiplier(week: week) }
}
