import Foundation
import GameCore
import Countries
import Finance

/// Named systems the app checks. Each one is either core (open from the start) or opens with a level feature.
public enum Gate: String, CaseIterable, Sendable {
    case hiring, marketing, bank, newCompany, management, accounting, insurance, suppliers, property
    case group, rivals, ventures, luxury, atlas
    case weather, airstay, techpro, marketplace, reviews
    case ownerHours

    /// The level feature that opens this system; nil means it is part of the core game.
    public var feature: LevelFeature? {
        switch self {
        case .hiring, .bank, .accounting, .suppliers, .property, .weather, .airstay, .ownerHours: return nil
        case .marketing, .reviews: return .marketing
        case .newCompany, .group: return .newCompany
        case .management: return .management
        case .insurance, .atlas: return .insurance
        case .rivals: return .rivals
        case .ventures: return .ventures
        case .luxury: return .luxury
        case .techpro: return .techpro
        case .marketplace: return .marketplace
        }
    }

    public var lockText: String? { feature.map { (f: LevelFeature) -> String in FeatureUnlocks.lockLine(f) } }
}

public enum GateVisibility: Equatable, Sendable {
    case open
    case locked(String)
    case hidden
}

public struct UnlockRoadmapItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var condition: String
    public var progress: Double
    public var detail: String
    public var companyID: Int?
}

public enum Gates {
    public static let richMultiple = 50.0
    public static let earlyHoursCap = 45.0
    /// Locked systems this many levels away or closer show their lock; further ones stay hidden.
    public static let nearLevels = 2
    static let openKey = "gateG"

    static let coreTitles: [Gate: String] = [.hiring: "Hiring", .bank: "Bank", .accounting: "Accounting", .suppliers: "Suppliers", .property: "Property",
                                             .weather: "Weather", .airstay: "AirStay", .ownerHours: "Owner hours", .group: "Group", .atlas: "Atlas", .reviews: "Reviews"]

    public static func title(_ g: Gate) -> String {
        if let t = coreTitles[g] { return t }
        return g.feature.map { (f: LevelFeature) -> String in FeatureUnlocks.row(f).title } ?? g.rawValue
    }

    public static func ladderOn(_ s: GameState) -> Bool { s.rest["ldr"] != nil }

    public static func goalsDone(_ s: GameState) -> Int { s.rest["ldr"]?["done"].object.count ?? 0 }

    public static func goalDone(_ s: GameState, _ n: Int) -> Bool { !(s.rest["ldr"]?["done"]["M\(n)"] ?? .null).isNull }

    public static func companiesOwned(_ s: GameState) -> Int { s.companies.filter { $0.status.isLive }.count }

    public static func profitableYears(_ s: GameState) -> Int {
        let cs = s.companies
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

    public static func reviewOpen(_ s: GameState) -> Bool { s.week >= 52 }

    public static func isOpen(_ g: Gate, _ s: GameState, data: GameData) -> Bool {
        guard let f = g.feature else { return true }
        return FeatureUnlocks.isUnlocked(f, s)
    }

    public static func visibility(_ g: Gate, _ s: GameState, data: GameData) -> GateVisibility {
        guard let f = g.feature, !FeatureUnlocks.isUnlocked(f, s) else { return .open }
        return FeatureUnlocks.unlockLevel(f) - LevelCurve.level(s) <= nearLevels ? .locked(FeatureUnlocks.lockLine(f)) : .hidden
    }

    public static func ownerHoursCap(_ s: GameState) -> Double {
        ladderOn(s) && s.week < 13 ? earlyHoursCap : OwnerHours.weeklyCap
    }

    /// Locked features in the order they open, with XP progress toward each.
    public static func roadmap(_ s: GameState, data: GameData, context: FinanceContext) -> [UnlockRoadmapItem] {
        let xp: Int = LevelCurve.xp(s)
        return FeatureUnlocks.table.filter { (r: FeatureUnlocks.Row) -> Bool in !FeatureUnlocks.isUnlocked(r.feature, s) }.map { (r: FeatureUnlocks.Row) -> UnlockRoadmapItem in
            let need: Int = LevelCurve.threshold(r.level)
            let fraction: Double = need > 0 ? min(1, Double(xp) / Double(need)) : 1
            return UnlockRoadmapItem(id: "gate." + r.feature.rawValue, title: r.title, condition: FeatureUnlocks.lockLine(r.feature),
                                     progress: fraction, detail: "\(max(0, need - xp)) XP to go", companyID: nil)
        }
    }
}
