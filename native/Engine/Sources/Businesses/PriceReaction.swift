import Foundation
import GameCore
import Countries

/// Rivals answering low prices. When your price (company-wide, or your cheapest main item) stays more than 8 percent under the market price
/// for 2 weeks in a row, each rival in the same trade and city that charges more than you looks at what to do. No random draws: the answer
/// follows the rival's size, the market's aggression and the rival's strategy and health.
///   score = 0.5 x size + 0.6 x aggression + strategy (cheap +0.15, expander +0.1, premium -0.15, quality -0.1)
///   in trouble (fortune below 0): ignores you; score >= 0.75: cuts its price to just above yours and fights (a price war of 5 to 8 weeks);
///   score >= 0.5: a marketing push (6 weeks); lower: ignores you.
/// A fight takes demand from your companies there (fading to nothing) and raises their cost of sales 2 percent while it lasts. A rival answers at most
/// once in 8 weeks. A company within 8 percent of the market never starts the count, so nothing changes for it.
extension Rivals {
    static let undercutGap = 0.08
    static let undercutWeeks = 2
    static let reactionCooldown = 8

    /// The lowest price a company effectively charges against the market's scale: its going price, or its cheapest main item (10 percent of customers or more).
    static func lowestOwnPrice(_ co: Company, myP: Double, bd: Trade) -> Double {
        let items = SalesItems.items(co, bd).filter { $0.unitShare >= 0.1 }
        let low = items.map { $0.effectiveMultiplier }.min() ?? 1
        return myP * min(1, low)
    }

    /// 0...1 aggressiveness score of a rival towards an undercutting player.
    static func reactionScore(_ r: JSONValue, aggression: Double) -> Double {
        let bonus: Double = { switch strategyOf(r) { case "cheap": return 0.15; case "expander": return 0.1; case "premium": return -0.15; case "quality": return -0.1; default: return 0 } }()
        return 0.5 * r["size"].double + 0.6 * aggression + bonus
    }

    /// Called from `behave` after the rivals' own weekly moves. Changes `riv` (a rival's price or campaign) and the player companies' demand pressure.
    static func priceReaction(_ s: inout GameState, idx: [Int], riv: inout [JSONValue], market m: JSONValue, bd: Trade, cityName: String, world w: World) {
        guard !riv.isEmpty else { return }
        let week = s.week
        let pi = m["pi"].isNull ? 1 : m["pi"].double
        let aggr = m["aggr"].isNull ? 1 : m["aggr"].double
        for ci in idx {
            let co = s.companies[ci]
            let myP = Pricing.priceIndex(co, w) / max(0.01, co.num("ig", 1))
            let own = lowestOwnPrice(co, myP: myP, bd: bd)
            let ref = min(pi, 1)   // the going price is 1: a company at it never counts as undercutting, however dear its rivals are
            let under = own < ref * (1 - undercutGap)
            let count = co.value("ucw").int
            if !under {
                if count != 0 { s.companies[ci].set("ucw", .null) }
                continue
            }
            s.companies[ci].set("ucw", count + 1)
            guard count + 1 >= undercutWeeks else { continue }
            let beyond = max(0, (1 - own / max(0.01, ref)) - undercutGap)
            for j in riv.indices {
                var r = riv[j]
                guard effectivePrice(r, week: week) > own, Double(week) >= r["rx27"].double else { continue }
                let id = r["id"].int, name = r["name"].string
                let score = reactionScore(r, aggression: aggr)
                let sizeF = clamp(r["size"].double, 0.6, 1.4)
                r["rx27"] = .number(Double(week + reactionCooldown))
                if fortuneOf(r) >= 0, score >= 0.5 {
                    if score >= 0.75 {
                        let weeks = 4 + Int((aggr * 4).rounded())
                        let amount = (0.04 + 0.5 * min(0.08, beyond)) * sizeF
                        let target = max(own * 1.03, 0.7)
                        let eff = effectivePrice(r, week: week)
                        r["pm16"] = .number(clamp(r["pm16"].double * target / max(0.01, eff), 0.7, 1.6))
                        remember(&r, week: week, text: "Cut prices to answer \(co.name).", change: -4)
                        MarketPressure.add(&s, ci, kind: .response, amount: amount, weeks: weeks, rivalID: id)
                        PriceMoves.addModifier(&s, ci, key: "cogsup", multiplier: 1.02, weeks: Double(weeks))
                        MarketEvents.log(&s, .priceResponse, title: "\(name) cuts prices to match \(co.name)",
                                         detail: "You have been \(Int(((1 - own / ref) * 100).rounded()))% under the \(bd.name.lowercased()) market in \(cityName).",
                                         companyID: co.id, amount: amount, tone: "bad",
                                         consequence: "Price war for \(weeks) weeks: demand about \(Int((amount * 100).rounded()))% lower, fading; costs 2% higher.")
                    } else {
                        let amount = 0.02 * sizeF
                        if r["mkt16"].isNull { r["mkt16"] = .number(Double(week + 6)) }
                        MarketPressure.add(&s, ci, kind: .response, amount: amount, weeks: 6, rivalID: id)
                        MarketEvents.log(&s, .priceResponse, title: "\(name) pushes back with marketing",
                                         detail: "It answers \(co.name)'s low prices in \(cityName) with a campaign.", companyID: co.id, amount: amount, tone: "bad",
                                         consequence: "Demand about \(max(1, Int((amount * 100).rounded())))% lower for 6 weeks, fading.")
                    }
                }
                riv[j] = r
            }
        }
    }
}
