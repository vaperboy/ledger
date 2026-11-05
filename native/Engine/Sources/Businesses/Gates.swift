import Foundation
import GameCore
import Countries
import Finance

/// Gate table. A surface of the app that stays hidden (not greyed)
/// until its gate. Views ask `Gates.visibility`; no screen decides this itself.
/// Systems that only serve another system share its gate: reviews follow marketing, the weather app follows insurance, AirStay follows
/// property, TechPro follows management, the marketplace follows suppliers and the ventures feed follows ventures.
public enum Gate: String, CaseIterable, Sendable {
    case hiring, marketing, ownerMoney, bank, newCompany, management, accounting, insurance, suppliers, property
    case group, rivals, ventures, luxury, atlas
    case weather, airstay, techpro, marketplace, reviews, venturesFeed
    case ownerHours

    /// What a gate waits for: a game week, a ladder goal (1 to 10), a number of companies, profitable closed years, or wealth.
    enum Rule: Equatable { case week(Int), goal(Int), companies(Int), profitableYears(Int), rich }

    var rule: Rule {
        switch self {
        case .hiring: return .week(3)
        case .marketing, .reviews: return .goal(3)
        case .ownerMoney: return .goal(4)
        case .bank, .newCompany, .management, .accounting, .techpro: return .goal(7)
        case .insurance, .suppliers, .weather, .marketplace: return .goal(8)
        case .property, .rivals, .airstay: return .goal(9)
        case .group, .atlas: return .companies(3)
        case .ventures, .venturesFeed: return .profitableYears(2)
        case .luxury: return .rich
        case .ownerHours: return .week(13)
        }
    }

    /// The line shown when the gate is near; nil for owner hours (silent).
    public var lockText: String? {
        switch rule {
        case .week(let w): return self == .ownerHours ? nil : "Unlocks in week \(w)"
        case .goal(3): return "Unlocks after your first hire"
        case .goal(4): return "Unlocks after your first decision"
        case .goal(7): return self == .accounting ? "Opens with your first profitable month" : "Unlocks after your first profitable month"
        case .goal(8): return "Unlocks when a manager runs the company"
        case .goal(9): return "Unlocks with your second company"
        case .goal: return nil
        case .companies: return "Unlocks with three companies"
        case .profitableYears: return "Unlocks after two profitable years"
        case .rich: return "Unlocks when you are rich"
        }
    }
}

public enum GateVisibility: Equatable, Sendable {
    case open
    /// Closed but near: show the surface dimmed with this line.
    case locked(String)
    /// Closed and far: not on Home, not in the grid, no Inbox items, no menu entries.
    case hidden
}

public enum Gates {
    /// Net worth above this many median monthly wages opens the luxury surfaces.
    public static let richMultiple = 50.0
    /// Owner hours are capped at this until week 13 (silently).
    public static let earlyHoursCap = 45.0
    /// A week gate is "near" within this many weeks; a goal gate within one goal.
    static let nearWeeks = 2

    /// The ladder is on for games started with it (`rest["ldr"]`); an older save has no ladder and nothing is gated.
    public static func ladderOn(_ s: GameState) -> Bool { s.rest["ldr"] != nil }

    /// Goals finished on the ladder (it is linear, so also the number of the open goal minus one, 0 to 10).
    public static func goalsDone(_ s: GameState) -> Int { s.rest["ldr"]?["done"].object.count ?? 0 }

    /// Goal `n` (1 to 10) is finished.
    public static func goalDone(_ s: GameState, _ n: Int) -> Bool { !(s.rest["ldr"]?["done"]["M\(n)"] ?? .null).isNull }

    /// Companies the player owns (a holding is not counted).
    public static func companiesOwned(_ s: GameState) -> Int { s.companies.filter { $0.status.isLive && $0.type != "hold" }.count }

    /// Closed years in which the group's companies together made a profit, counted back from the latest twelve closed months.
    public static func profitableYears(_ s: GameState) -> Int {
        let cs = s.companies.filter { $0.type != "hold" }
        let years = (cs.map { $0.monthlyHistory.count }.max() ?? 0) / 12
        var n = 0
        for b in 0..<years {
            let total = cs.reduce(0.0) { acc, c in
                let h = c.monthlyHistory
                let hi = h.count - 12 * b, lo = hi - 12
                return lo < 0 ? acc : acc + h[lo..<hi].reduce(0.0) { $0 + $1.profit }
            }
            if total > 0 { n += 1 }
        }
        return n
    }

    public static func netWorthLimit(_ s: GameState, data: GameData) -> Double {
        data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode).medianMonthlyWage * richMultiple
    }

    public static func isOpen(_ g: Gate, _ s: GameState, data: GameData) -> Bool {
        guard ladderOn(s) else { return true }
        switch g.rule {
        case .week(let w): return s.week >= w
        case .goal(let n): return goalDone(s, n)
        case .companies(let n): return companiesOwned(s) >= n
        case .profitableYears(let n): return profitableYears(s) >= n
        case .rich: return Valuation.netWorth(s, trades: data.catalog).total > netWorthLimit(s, data: data)
        }
    }

    /// Open, locked-and-near (one goal or two weeks away) or hidden.
    public static func visibility(_ g: Gate, _ s: GameState, data: GameData) -> GateVisibility {
        if isOpen(g, s, data: data) { return .open }
        guard let text = g.lockText else { return .hidden }
        switch g.rule {
        case .week(let w): return w - s.week <= nearWeeks ? .locked(text) : .hidden
        case .goal(let n): return n - goalsDone(s) <= 1 ? .locked(text) : .hidden
        case .companies(let n): return companiesOwned(s) + 1 >= n ? .locked(text) : .hidden
        case .profitableYears(let n): return profitableYears(s) + 1 >= n ? .locked(text) : .hidden
        case .rich: return .hidden
        }
    }

    /// Hours cap for the owner this week: 45 before week 13 in a game with the ladder, else the usual cap.
    public static func ownerHoursCap(_ s: GameState) -> Double {
        ladderOn(s) && s.week < 13 ? earlyHoursCap : OwnerHours.weeklyCap
    }
}
