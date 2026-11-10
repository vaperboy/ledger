import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum Ventures {
    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        Startups.weekly(&s, data: data, context: fc)
        PrivateEquity.weekly(&s, context: fc)
        BigMeeting.weekly(&s, data: data, context: fc)
        Shareholders.weekly(&s, data: data, context: fc)
        JointVenture.weekly(&s, data: data, context: fc)
    }

    public static func handlesAnswer(_ action: String) -> Bool {
        action == "round" || action == "bridge" || action == Shareholders.action
    }

    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData, context fc: FinanceContext) -> Bool {
        switch m.actionID {
        case "round", "bridge": return Startups.answer(&s, message: m, option: idx)
        case Shareholders.action: Shareholders.answer(&s, message: m, option: idx, data: data, context: fc); return true
        default: return true
        }
    }
}
