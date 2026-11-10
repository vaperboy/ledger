import Foundation
import GameCore
import Countries
import Businesses

public extension GameEngine {
    @discardableResult
    mutating func bookOnlineSettlements(_ items: [OnlineSettlement]) -> [String] {
        var done: [String] = []
        update { s, d, _ in done = OnlineSettlements.book(&s, items, data: d) }
        return done
    }
}
