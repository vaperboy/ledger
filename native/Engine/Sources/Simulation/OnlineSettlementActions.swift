import Foundation
import GameCore
import Countries
import Businesses
import Events

public extension GameEngine {
    @discardableResult
    mutating func bookOnlineSettlements(_ items: [OnlineSettlement]) -> [String] {
        var done: [String] = []
        update { s, d, _ in
            done = OnlineSettlements.book(&s, items, data: d, handler: { (st: inout GameState, item: OnlineSettlement, amount: Double) -> Bool in
                JointVentureSettlements.book(&st, item, amount: amount)
            })
        }
        return done
    }
}
