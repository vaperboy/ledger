import Foundation
import GameCore

/// The three ways to play. The mode is chosen at game start and kept in the save (`rest["difficulty"]`); it only moves existing knobs:
/// the first-year protections (`FirstYear`), the bad-event ramp (`Balance.eventRamp`) and how hard the threats of `Threat` push.
public enum Difficulty: String, CaseIterable, Sendable, Identifiable {
    case classic, sandbox, hard

    public var id: String { rawValue }
    public static let restKey = "difficulty"

    public var name: String {
        switch self { case .classic: return "Classic"; case .sandbox: return "Sandbox"; case .hard: return "Hard" }
    }
    /// One sentence for the start screen.
    public var blurb: String {
        switch self {
        case .classic: return "The game as designed: safety nets for the first months, then the real thing."
        case .sandbox: return "No bankruptcy, a long overdraft cushion and gentler events, for building at ease."
        case .hard: return "No safety nets from day one, sharper rivals and bad luck that arrives early."
        }
    }

    /// The mode a save is in; a save without one is Classic.
    public static func of(_ s: GameState) -> Difficulty { Difficulty(rawValue: s.rest[restKey]?.string ?? "") ?? .classic }

    /// Multiplier on every success-scaled threat (rival bids, creditor drift, reputation loss).
    public var threatScale: Double {
        switch self { case .classic: return 1; case .sandbox: return 0.35; case .hard: return 1.6 }
    }
    /// Multiplier on how often rivals open next door, run offers and phone the owner.
    public var rivalSharpness: Double {
        switch self { case .classic: return 1; case .sandbox: return 0.5; case .hard: return 1.7 }
    }
    /// Last game week of the one-bad-event-a-week rule.
    public var badEventCapWeeks: Int {
        switch self { case .classic: return 12; case .sandbox: return 26; case .hard: return 6 }
    }
    /// Weight on bad events: the balance table's ramp, stretched for Sandbox (and kept lower once it is over), compressed for Hard.
    public func eventRamp(_ balance: Balance, week: Int) -> Double {
        switch self {
        case .classic: return balance.eventRampMultiplier(week: week)
        case .sandbox: return balance.eventRampMultiplier(week: week * 2 / 3) * 0.7
        case .hard: return balance.eventRampMultiplier(week: week * 2)
        }
    }
    /// Weeks of warning before a market crash or bear market.
    public var marketWarningWeeks: Int { self == .hard ? 1 : 2 }
}

public extension FirstYear {
    /// The first-year table as this mode plays it. Sandbox switches bankruptcy and supplier cut-off off for good and stretches the overdraft
    /// protection; Hard applies the week-27 rules from the first day and keeps only a short overdraft protection.
    func applying(_ d: Difficulty) -> FirstYear {
        var f = self
        switch d {
        case .classic: break
        case .sandbox:
            f.bankruptcyEnabled = false; f.bankruptcyWeek = Int.max / 4
            f.supplierCutoffEnabled = false; f.supplierCutoffWeek = Int.max / 4
            f.noOverdraftWeeks = 52
        case .hard:
            f.bankruptcyEnabled = true
            f.supplierCutoffEnabled = true
            f.noOverdraftWeeks = 4
        }
        return f
    }
    /// The table in force for this game: the base table in the game's mode.
    static func effective(_ s: GameState, base: FirstYear) -> FirstYear { base.applying(Difficulty.of(s)) }
    static func effective(_ s: GameState, balance: Balance) -> FirstYear { effective(s, base: balance.firstYear) }
}
