import Foundation
import GameCore

public enum Difficulty: String, CaseIterable, Sendable, Identifiable {
    case classic, sandbox, hard

    public var id: String { rawValue }
    public static let restKey = "difficulty"

    public var name: String {
        switch self { case .classic: return "Classic"; case .sandbox: return "Sandbox"; case .hard: return "Hard" }
    }
    public var blurb: String {
        switch self {
        case .classic: return "The game as designed: safety nets for the first months, then the real thing."
        case .sandbox: return "No bankruptcy, a long overdraft cushion and gentler events, for building at ease."
        case .hard: return "No safety nets from day one, sharper rivals and bad luck that arrives early."
        }
    }

    public static func of(_ s: GameState) -> Difficulty { Difficulty(rawValue: s.rest[restKey]?.string ?? "") ?? .classic }

    public var threatScale: Double {
        switch self { case .classic: return 1; case .sandbox: return 0.35; case .hard: return 1.6 }
    }
    public var rivalSharpness: Double {
        switch self { case .classic: return 1; case .sandbox: return 0.5; case .hard: return 1.7 }
    }
    public var badEventCapWeeks: Int {
        switch self { case .classic: return 12; case .sandbox: return 26; case .hard: return 6 }
    }
    public func eventRamp(_ balance: Balance, week: Int) -> Double {
        switch self {
        case .classic: return balance.eventRampMultiplier(week: week)
        case .sandbox: return balance.eventRampMultiplier(week: week * 2 / 3) * 0.7
        case .hard: return balance.eventRampMultiplier(week: week * 2)
        }
    }
    public var marketWarningWeeks: Int { self == .hard ? 1 : 2 }
}

public extension FirstYear {
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
    static func effective(_ s: GameState, base: FirstYear) -> FirstYear { base.applying(Difficulty.of(s)) }
    static func effective(_ s: GameState, balance: Balance) -> FirstYear { effective(s, base: balance.firstYear) }
}
