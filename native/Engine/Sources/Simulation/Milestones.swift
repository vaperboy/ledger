import Foundation
import GameCore
import Countries
import Businesses

public struct MilestoneProgress: Equatable, Sendable {
    public struct Reached: Equatable, Sendable { public var amount: Double; public var day: Int }
    public var reached: [Reached]
    public var next: Double
    public var profitStreak: Int
    public var bestStreak: Int
    public var bestWeek: Double
}

public enum Milestones {
    static let streakSteps = [4, 8, 13, 26, 52]
    static func threshold(_ i: Int, _ cur: Currency) -> Double { cur.scaledPrice([1.0, 2.5, 5.0][i % 3] * 100_000 * pow(10, Double(i / 3))) }

    static func check(_ s: inout GameState, data: GameData, currency cur: Currency, weekClosed: Bool) {
        let firstCheck = s.rest["miles"] == nil && s.rest["start"] != nil
        // The start money is no achievement: on the first look every step it reaches counts as already passed.
        let startMoney: Double = firstCheck ? (s.rest["start"]?["cash"].double ?? 0) : 0
        let nw = Valuation.netWorth(s, trades: data.catalog, forGoals: true).total
        let reach = max(nw, startMoney)
        var m = s.rest["miles"] ?? .object(["w": .number(nw)])
        let today = s.week * 7 + s.day
        var reached = m["r"].array ?? []
        var top = -1
        var i = reached.count
        while i < 80, threshold(i, cur) <= reach { reached.append(.number(Double(today))); top = i; i += 1 }
        if top >= 0 {
            m["r"] = .array(reached)
            if !firstCheck { Celebrations.add(&s, kind: "milestone", title: "Net worth passed \(cur.display(threshold(top, cur)))", detail: "Reached on day \(today + 1) of your game", art: "milestone.networth", tier: 2) }
        }
        if weekClosed {
            let gain = nw - m["w"].double
            m["w"] = .number(nw)
            if gain > 0 {
                let streak = m["s"].int + 1
                m["s"] = .number(Double(streak))
                if streak > m["bs"].int { m["bs"] = .number(Double(streak)) }
                if gain > m["bw"].double { m["bw"] = .number(gain) }
                if streakSteps.contains(streak) {
                    Celebrations.add(&s, kind: "milestone", title: "\(streak) profitable weeks in a row", detail: "Your net worth has risen every week for \(streak) weeks", art: "milestone.streak", tier: 2)
                }
            } else {
                m["s"] = .number(0)
            }
        }
        s.rest["miles"] = m
    }
}

public extension GameEngine {
    var milestoneProgress: MilestoneProgress {
        let m = state.rest["miles"] ?? .null
        let cur = homeCurrency
        let r = m["r"].array ?? []
        let reached = r.enumerated().map { MilestoneProgress.Reached(amount: Milestones.threshold($0.offset, cur), day: $0.element.int) }
        return MilestoneProgress(reached: reached, next: Milestones.threshold(r.count, cur), profitStreak: m["s"].int, bestStreak: m["bs"].int, bestWeek: m["bw"].double)
    }

    internal mutating func checkMilestones(weekClosed: Bool) {
        update { s, d, ctx in Milestones.check(&s, data: d, currency: ctx.homeCurrency(s), weekClosed: weekClosed) }
    }

    mutating func markCelebrationShown(_ id: String) {
        guard let n = Int(id) else { return }
        update { s, _, _ in
            let rest = (s.rest["cele"]?.array ?? []).filter { $0["id"].int != n }
            s.rest["cele"] = rest.isEmpty ? nil : .array(rest)
        }
    }
}
