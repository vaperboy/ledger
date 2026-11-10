import Foundation
import GameCore
import Countries

extension Rivals {
    static let undercutGap = 0.08
    static let undercutWeeks = 2
    static let reactionCooldown = 8

    static func lowestOwnPrice(_ co: Company, myP: Double, bd: Trade) -> Double {
        let items = SalesItems.items(co, bd).filter { $0.unitShare >= 0.1 }
        let low = items.map { $0.effectiveMultiplier }.min() ?? 1
        return myP * min(1, low)
    }

    static func reactionScore(_ r: JSONValue, aggression: Double) -> Double {
        let bonus: Double = { switch strategyOf(r) { case "cheap": return 0.15; case "expander": return 0.1; case "premium": return -0.15; case "quality": return -0.1; default: return 0 } }()
        return 0.5 * r["size"].double + 0.6 * aggression + bonus
    }

    static func priceReaction(_ s: inout GameState, idx: [Int], riv: inout [JSONValue], market m: JSONValue, bd: Trade, cityName: String, world w: World) {
        guard !riv.isEmpty else { return }
        let week = s.week
        let pi = m["pi"].isNull ? 1 : m["pi"].double
        let aggr = m["aggr"].isNull ? 1 : m["aggr"].double
        for ci in idx {
            let co = s.companies[ci]
            let myP = Pricing.priceIndex(co, w) / max(0.01, co.num("ig", 1))
            let own = lowestOwnPrice(co, myP: myP, bd: bd)
            let ref = min(pi, 1)
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
                        let weeks = 4 + Int(saturating: (aggr * 4).rounded())
                        let amount = (0.04 + 0.5 * min(0.08, beyond)) * sizeF
                        let target = max(own * 1.03, 0.7)
                        let eff = effectivePrice(r, week: week)
                        r["pm16"] = .number(clamp(r["pm16"].double * target / max(0.01, eff), 0.7, 1.6))
                        remember(&r, week: week, text: "Cut prices to answer \(co.name).", change: -4)
                        MarketPressure.add(&s, ci, kind: .response, amount: amount, weeks: weeks, rivalID: id)
                        PriceMoves.addModifier(&s, ci, key: "cogsup", multiplier: 1.02, weeks: Double(weeks))
                        MarketEvents.log(&s, .priceResponse, title: "\(name) cuts prices to match \(co.name)",
                                         detail: "You have been \(Int(saturating: ((1 - own / ref) * 100).rounded()))% under the \(bd.name.lowercased()) market in \(cityName).",
                                         companyID: co.id, amount: amount, tone: "bad",
                                         consequence: "Price war for \(weeks) weeks: demand about \(Int(saturating: (amount * 100).rounded()))% lower, fading; costs 2% higher.")
                    } else {
                        let amount = 0.02 * sizeF
                        if r["mkt16"].isNull { r["mkt16"] = .number(Double(week + 6)) }
                        MarketPressure.add(&s, ci, kind: .response, amount: amount, weeks: 6, rivalID: id)
                        MarketEvents.log(&s, .priceResponse, title: "\(name) pushes back with marketing",
                                         detail: "It answers \(co.name)'s low prices in \(cityName) with a campaign.", companyID: co.id, amount: amount, tone: "bad",
                                         consequence: "Demand about \(max(1, Int(saturating: (amount * 100).rounded())))% lower for 6 weeks, fading.")
                    }
                }
                riv[j] = r
            }
        }
    }
}
