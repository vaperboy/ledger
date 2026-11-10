import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum GoalClaims {
    public enum Kind: String, Sendable { case ladder, career, daily }

    public struct Claimable: Equatable, Sendable, Identifiable {
        public var kind: Kind
        public var goalID: String
        public var title: String
        public var reward: String
        public var cash: Double
        public var id: String { kind.rawValue + ":" + goalID }
    }

    public enum Result: Equatable, Sendable {
        case claimed(title: String, reward: String, cash: Double)
        case notReady
    }

    static let ladderCash: [String: Double] = ["M1": 500, "M2": 250, "M3": 500, "M4": 250, "M5": 250, "M6": 250, "M7": 1_000, "M8": 1_000, "M9": 1_000, "M10": 500]
    static let dailyCash: Double = 250
    static let structuralCareerIDs: Set<String> = ["k6", "k8", "k11", "k12", "k13", "k15", "k17"]
    static let structuralCareerCash: Double = 500
    static let structuralCareerXP = 150
    static func careerCash(_ h: Career.Horizon) -> Double { h == .short ? 1_000 : h == .medium ? 3_000 : 10_000 }
    static func careerCash(id: String, _ h: Career.Horizon) -> Double { structuralCareerIDs.contains(id) ? structuralCareerCash : careerCash(h) }

    public static func rewardLabel(_ title: String) -> String { "Goal reward: " + title }

    public static func claimable(_ s: GameState, data: GameData, currency cur: Currency, today: String) -> [Claimable] {
        var out: [Claimable] = []
        for g in PlayerGoals.ladder(s) ?? [] where g.unclaimed {
            out.append(Claimable(kind: .ladder, goalID: g.id, title: g.title, reward: g.reward, cash: cur.scaledPrice(ladderCash[g.id] ?? 0)))
        }
        for g in Career.goals(s, data: data, currency: cur) where g.unclaimed {
            let h: Career.Horizon = Career.defs.first { $0.id == g.id }?.horizon ?? .short
            out.append(Claimable(kind: .career, goalID: g.id, title: g.title, reward: g.reward, cash: cur.scaledPrice(careerCash(id: g.id, h))))
        }
        if let d = dailyClaimable(s, today: today) {
            out.append(Claimable(kind: .daily, goalID: d.id, title: d.title, reward: "A small cash reward", cash: cur.scaledPrice(dailyCash)))
        }
        return out
    }

    static func dailyClaimable(_ s: GameState, today: String) -> PlayerGoals.DailyDef? {
        guard !PlayerGoals.dailyGoalsOff(s), let d = s.rest["dy59"], d["d"].string == today, d["got"].int != 0, d["cl"].string != today else { return nil }
        return PlayerGoals.dailyDefs.first { $0.id == d["k"].string } ?? PlayerGoals.dailyDefs.first { $0.id == "grow" }
    }

    @discardableResult
    public static func claim(_ s: inout GameState, kind: Kind, id: String, data: GameData, currency cur: Currency, today: String) -> Result {
        switch kind {
        case .ladder:
            guard let g = PlayerGoals.ladder(s)?.first(where: { $0.id == id }), g.unclaimed else { return .notReady }
            clear(&s, "ldr", id)
            let line: String = PlayerGoals.ladderReward(&s, id, cur)
            if !line.isEmpty { s.note(line, tone: "good") }
            let cash: Double = pay(&s, title: g.title, amount: cur.scaledPrice(ladderCash[id] ?? 0))
            return .claimed(title: g.title, reward: g.reward, cash: cash)
        case .career:
            guard let def = Career.defs.first(where: { $0.id == id }), (s.rest["car"]?["done"][id]["u"].int ?? 0) != 0 else { return .notReady }
            clear(&s, "car", id)
            if !def.cosmetic.isEmpty {
                var c = s.rest["car"] ?? .object([:])
                c["cos"] = .array((c["cos"].array ?? []) + [.string(def.cosmetic)])
                s.rest["car"] = c
            }
            def.grant(&s)
            let title: String = def.text(def.title, cur)
            if structuralCareerIDs.contains(id) { PlayerLevel.award(&s, structuralCareerXP) }
            let cash: Double = pay(&s, title: title, amount: cur.scaledPrice(careerCash(id: id, def.horizon)))
            return .claimed(title: title, reward: def.reward, cash: cash)
        case .daily:
            guard let def = dailyClaimable(s, today: today) else { return .notReady }
            var d = s.rest["dy59"] ?? .object([:])
            d["cl"] = .string(today)
            s.rest["dy59"] = d
            let cash: Double = pay(&s, title: def.title, amount: cur.scaledPrice(dailyCash))
            return .claimed(title: def.title, reward: "A small cash reward", cash: cash)
        }
    }

    private static func clear(_ s: inout GameState, _ key: String, _ id: String) {
        var root = s.rest[key] ?? .object([:])
        var done = root["done"]
        var entry = done[id]
        entry["u"] = .number(0)
        done[id] = entry
        root["done"] = done
        s.rest[key] = root
    }

    private static func pay(_ s: inout GameState, title: String, amount: Double) -> Double {
        let cash: Double = jsRound(amount)
        guard cash > 0 else { return 0 }
        Ledger.move(&s, .me, cash, why: rewardLabel(title))
        return cash
    }
}

public extension GameEngine {
    func claimableGoals(now: Date = Date()) -> [GoalClaims.Claimable] {
        GoalClaims.claimable(state, data: data, currency: homeCurrency, today: Self.dayString(now))
    }

    @discardableResult
    mutating func claimGoal(kind: GoalClaims.Kind, id: String, now: Date = Date()) -> GoalClaims.Result {
        var r: GoalClaims.Result = .notReady
        let today: String = Self.dayString(now)
        update { s, d, ctx in
            r = GoalClaims.claim(&s, kind: kind, id: id, data: d, currency: ctx.homeCurrency(s), today: today)
            if case .claimed = r { Tutorial.advance(&s, from: .claimGoal) }
        }
        return r
    }
}
