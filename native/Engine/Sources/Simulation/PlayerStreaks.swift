import Foundation
import GameCore
import Finance
import Businesses

extension PlayerGoals {

    static let streakPerkList: [(days: Int, credit: Double, token: Bool, title: String)] = [
        (3, 1, false, "Regular"), (7, 0, true, "Week Keeper"), (14, 1, false, "Fortnight Operator"), (30, 0, true, "Month Master")]

    static func grantStreakPerks(_ s: inout GameState, _ d: inout JSONValue, streak n: Int) {
        var claimed: [Int] = d["ms"].array.map { $0.int }
        for p in streakPerkList where n >= p.days && !claimed.contains(p.days) {
            claimed.append(p.days)
            if p.credit > 0 { s.credit = min(100, s.credit + p.credit) }
            if p.token { d["prot"] = .number(1) }
            d["title"] = .string(p.title)
            var gift: [String] = ["the title \"\(p.title)\""]
            if p.credit > 0 { gift.append("a slightly better credit score") }
            if p.token { gift.append("a streak protection token: miss a day and simply come back the next one") }
            s.note("\(p.days) days in a row: you earn \(gift.joined(separator: ", ")).", tone: "good")
        }
        d["ms"] = .array(claimed.map { .number(Double($0)) })
    }

    public struct StreakInfo: Equatable, Sendable {
        public var count: Int
        public var best: Int
        public var protectionTokens: Int
        public var title: String
        public var nextMilestone: Int?
        public var nextPerk: String
        public var doneToday: Bool
        public var savedByProtection: Bool
    }

    public static func streakInfo(_ s: GameState, now: Date = Date()) -> StreakInfo {
        let d = s.rest["dy59"] ?? .object([:])
        let secondsPerDay: Double = 24 * 60 * 60
        let today = dayKey(now), yesterday = dayKey(now.addingTimeInterval(-secondsPerDay))
        let live = streakNow(d, today: today, yesterday: yesterday)
        let next = streakPerkList.first { $0.days > live.count }
        return StreakInfo(count: live.count, best: max(d["best"].int, live.count), protectionTokens: d["prot"].int, title: d["title"].string,
                          nextMilestone: next?.days, nextPerk: "", doneToday: d["last"].string == today,
                          savedByProtection: live.protected)
    }

    static let advancedList: [(id: String, title: String, body: String, button: String, link: String, past: String)] = [
        ("A1", "Turn a business into a chain", "Two or more stores under one name, ideally within a year of finishing the ladder.", "Open company", "company", "You built a chain."),
        ("A2", "A profitable franchise quarter", "Franchise a proven concept and see its first quarter in profit.", "Open company", "company", "Your franchise made its first profitable quarter.")]

    static func advancedCondition(_ id: String, _ s: GameState) -> Bool {
        switch id {
        case "A1": return Chains.all(s).contains { Chains.stores(s, $0).count >= 2 }
        case "A2":
            return s.companies.contains { co in
                guard co.status.isLive, co.value("fr")["on"].bool, !co.value("fr")["units"].array.isEmpty else { return false }
                let q = co.monthlyHistory.suffix(3)
                return q.count == 3 && q.reduce(0.0) { $0 + $1.profit } > 0
            }
        default: return false
        }
    }

    public static func advancedGoals(_ s: GameState) -> [LadderGoal] {
        guard let l = s.rest["ldr"], !l["done"]["M10"].isNull else { return [] }
        return advancedList.map { LadderGoal(id: $0.id, title: $0.title, body: $0.body, button: $0.button, link: $0.link, pastTense: $0.past, reward: "", done: !l["adv"][$0.id].isNull, advanced: true) }
    }

    static func advancedSweep(_ s: inout GameState) {
        guard let l0 = s.rest["ldr"], !l0["done"]["M10"].isNull else { return }
        let finished = l0["done"]["M10"]["w"].int
        for g in advancedList where (s.rest["ldr"]?["adv"][g.id].isNull ?? true) && advancedCondition(g.id, s) {
            var l = s.rest["ldr"] ?? .object([:])
            var adv = l["adv"].isNull ? JSONValue.object([:]) : l["adv"]
            adv[g.id] = .object(["w": .number(Double(s.week))])
            l["adv"] = adv
            s.rest["ldr"] = l
            let quick = g.id == "A1" && s.week - finished <= 52
            s.note(g.past + (quick ? " That is within a year of finishing the ladder." : ""), tone: "good")
        }
    }
}
