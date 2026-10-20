import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The weekly steps of the smaller systems (staff record, ambitions, giving, weather, cyber attacks, perks ...), in the order the
/// original runs them after the companies (`week.after` steps). One place, so GameEngine has a single line for all of them.
enum MiscWeekly {
    static func run(_ s: inout GameState, data: GameData, context: FinanceContext) {
        StaffProfile.trackWeek(&s)
        PremisesExtras.weekly(&s, data: data)
        if GameCalendar.isMonthEnd(week: s.week) { monthly(&s, data: data, context: context) }
    }

    /// Original: `regulationMonth` and the other month-end steps of these systems.
    static func monthly(_ s: inout GameState, data: GameData, context: FinanceContext) {
        Suppliers.monthly(&s)
    }
}
