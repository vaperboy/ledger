import Foundation
import GameCore
import Countries
import Finance

/// The calm engagement pages that open a few weeks in: Rivals (`RivalStories`), the weekly plan (`WeeklyFocus`) and the Desk (`Desk`).
/// This file holds what they share: the order they run in and the small helpers that move a company through existing mechanisms.
public enum Engagement {
    /// After the weekly sweep of unlocks: the plan's outcome and next offer, then the rivals' moves.
    public static func weekly(_ s: inout GameState, data: GameData) {
        WeeklyFocus.weekly(&s, data: data)
        RivalStories.weekly(&s, data: data)
    }

    /// Every game morning: Desk choices that come due play out and are told in the Inbox.
    public static func runDay(_ s: inout GameState, data: GameData) {
        DeskStories.runDay(&s, data: data)
    }

    // MARK: Helpers

    /// A temporary multiplier on a company (key "dem" demand, "cogsup" cost of goods). A modifier is used from the next weekly run, so a
    /// one-week effect is added with `weeks` 2. Same record the event engine writes.
    static func addModifier(_ s: inout GameState, _ i: Int, key: String, multiplier m: Double, weeks: Int) {
        var mods = s.companies[i].value("mods").array
        mods.append(.object(["k": .string(key), "m": .number(m), "w": .number(Double(weeks))]))
        s.companies[i].set("mods", .array(mods))
    }

    /// What the company took last week, in its own money.
    static func lastWeekRevenue(_ co: Company) -> Double { max(0, co.value("lastW")["rev"].double) }

    /// A small spend sized to the business: `share` of a week's takings, never less than a few hundred in reference money.
    static func spend(_ s: GameState, _ co: Company, share: Double, data: GameData) -> Double {
        let floor = World(state: s, data: data).currency(co).scaledPrice(minimumSpend)
        return jsRound(max(floor, lastWeekRevenue(co) * share))
    }
    static let minimumSpend = 200.0

    /// The company a page speaks about: the open company with the biggest week; ties by id.
    static func mainCompany(_ s: GameState) -> Company? {
        s.companies.filter { $0.status == .open && $0.type != "hold" && $0.type != "club" }
            .max { (a: Company, b: Company) -> Bool in
                let ra = lastWeekRevenue(a), rb = lastWeekRevenue(b)
                return ra != rb ? ra < rb : a.id > b.id
            }
    }

    /// "+4%" or "-3%" for a change of a share (0.04), rounded to a whole percent.
    static func percentText(_ share: Double) -> String {
        let n = Int(jsRound(share * 100))
        return n > 0 ? "+\(n)%" : n < 0 ? "\(n)%" : "0%"
    }
}
