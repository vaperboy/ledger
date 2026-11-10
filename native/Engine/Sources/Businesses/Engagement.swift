import Foundation
import GameCore
import Countries
import Finance

public enum Engagement {
    public static func weekly(_ s: inout GameState, data: GameData) {
        WeeklyFocus.weekly(&s, data: data)
        RivalStories.weekly(&s, data: data)
        TradeAssociations.weekly(&s, data: data)
    }

    public static func runDay(_ s: inout GameState, data: GameData) {
        DeskStories.runDay(&s, data: data)
    }

    static func addModifier(_ s: inout GameState, _ i: Int, key: String, multiplier m: Double, weeks: Int) {
        var mods = s.companies[i].value("mods").array
        mods.append(.object(["k": .string(key), "m": .number(m), "w": .number(Double(weeks))]))
        s.companies[i].set("mods", .array(mods))
    }

    static func lastWeekRevenue(_ co: Company) -> Double { max(0, co.value("lastW")["rev"].double) }

    static func spend(_ s: GameState, _ co: Company, share: Double, data: GameData) -> Double {
        let floor = World(state: s, data: data).currency(co).scaledPrice(minimumSpend)
        return jsRound(max(floor, lastWeekRevenue(co) * share))
    }
    static let minimumSpend = 200.0

    static func mainCompany(_ s: GameState) -> Company? {
        s.companies.filter { $0.status == .open && $0.type != "hold" && $0.type != "club" }
            .max { (a: Company, b: Company) -> Bool in
                let ra = lastWeekRevenue(a), rb = lastWeekRevenue(b)
                return ra != rb ? ra < rb : a.id > b.id
            }
    }

    static func percentText(_ share: Double) -> String {
        let n = Int(jsRound(share * 100))
        return n > 0 ? "+\(n)%" : n < 0 ? "\(n)%" : "0%"
    }
}
