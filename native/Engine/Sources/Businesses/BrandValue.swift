import Foundation
import GameCore

/// How much the name is worth, 0 to 100, from facts the game already keeps. The parts are the points each fact contributes, so they add up to the score:
///   reputation  up to 40  (70 percent reputation + 30 percent awareness, of 100)
///   yearsTrading up to 15  (15 points at ten years)
///   reach       up to 25  (stores and franchise units under the name: log2 of the count, full at 32)
///   awards      up to 20  (business awards count double, trophies and milestones once; full at 30 points)
/// A company's brand uses its own reputation, awareness, age and chain; the group's uses the size-weighted averages, the oldest company, every
/// outlet and the same awards. Used by the price of a company or licence sale, franchise fees and requirements, and the awareness of a new
/// store. All are modest: see `salePremium`, `feeFactor`, `requirementEase`, `openingAwareness`. DECISIONS.md "Brand value".
public struct BrandValue: Equatable, Sendable {
    public var score: Double
    public var reputation: Double
    public var yearsTrading: Double
    public var reach: Double
    public var awards: Double

    public init(reputation: Double, yearsTrading: Double, reach: Double, awards: Double) {
        self.reputation = reputation; self.yearsTrading = yearsTrading; self.reach = reach; self.awards = awards
        score = clamp(reputation + yearsTrading + reach + awards, 0, 100)
    }
}

public enum BrandValues {
    /// A sale of a company or a licence fetches up to 10 percent more at score 100 (no change at 0).
    public static func salePremium(_ score: Double) -> Double { 1 + 0.10 * clamp(score, 0, 100) / 100 }
    /// Franchise entry, renewal and master fees: up to 15 percent more at score 100.
    public static func feeFactor(_ score: Double) -> Double { 1 + 0.15 * clamp(score, 0, 100) / 100 }
    /// Points off the reputation a chain must have before it may franchise: up to 6 at score 100.
    public static func requirementEase(_ score: Double) -> Double { (6 * clamp(score, 0, 100) / 100).rounded() }
    /// Awareness a new store of a known brand opens with (never below the usual 10): 40 percent of the flagship's awareness plus 15 percent of the score, at most 45.
    public static func openingAwareness(flagshipAwareness: Double, score: Double) -> Double {
        clamp(max(10, flagshipAwareness * 0.4 + score * 0.15), 10, 45)
    }

    static func awardsPoints(_ s: GameState) -> Double {
        let won = Double(s.rest["aw56"]?["won"].array.count ?? 0)
        let trophies = Double(s.rest["ach28"]?.object.count ?? 0)
        return 20 * min(1, (2 * won + trophies) / 30)
    }

    static func yearsPoints(_ s: GameState, since week: Int) -> Double { 15 * min(1, max(0, Double(s.week - week)) / 52 / 10) }

    static func reachPoints(outlets n: Int) -> Double { n <= 1 ? 0 : 25 * min(1, log2(Double(n)) / 5) }

    static func standing(_ co: Company) -> Double { (0.7 * co.reputation + 0.3 * co.awareness) / 100 * 40 }

    /// Outlets under the company's trade: its own companies, franchise units and ready master-franchise units (as `Competition.chainOutlets`, without the franchisee clause).
    static func outlets(_ s: GameState, _ co: Company) -> Int {
        var n = 0
        for c in s.companies where c.type == co.type && c.status.isLive {
            n += 1
            let fr = c.value("fr")
            if fr["on"].bool {
                n += fr["units"].array.count
                for m in fr["masters"].array where Double(s.week) >= m["ready"].double { n += m["n"].int }
            }
        }
        let brandID = co.value("franchise")["brandId"]
        if !brandID.isNull { n += 4 }   // a franchisee carries its brand's name: a few units' worth of reach
        return max(1, n)
    }

    public static func company(_ s: GameState, _ co: Company) -> BrandValue {
        BrandValue(reputation: standing(co), yearsTrading: yearsPoints(s, since: co.openedWeek ?? co.foundedWeek),
                   reach: reachPoints(outlets: outlets(s, co)), awards: awardsPoints(s))
    }

    public static func group(_ s: GameState) -> BrandValue {
        let live = s.companies.filter { $0.status.isLive && $0.type != "hold" }
        guard !live.isEmpty else { return BrandValue(reputation: 0, yearsTrading: 0, reach: 0, awards: awardsPoints(s)) }
        let weights = live.map { max(0.01, $0.size) }
        let total = weights.reduce(0, +)
        let rep = zip(live, weights).reduce(0.0) { $0 + standing($1.0) * $1.1 } / total
        let oldest = live.map { $0.openedWeek ?? $0.foundedWeek }.min() ?? s.week
        var outlets = 0
        for c in live {
            outlets += 1
            let fr = c.value("fr")
            if fr["on"].bool { outlets += fr["units"].array.count }
        }
        return BrandValue(reputation: rep, yearsTrading: yearsPoints(s, since: oldest), reach: reachPoints(outlets: outlets), awards: awardsPoints(s))
    }
}
