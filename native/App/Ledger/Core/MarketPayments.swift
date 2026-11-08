import SwiftUI
import GameCore
import Businesses
import Simulation

/// Which worker's profile popup to open (the engine's types are not made Identifiable).
struct WorkerPopupRef: Identifiable, Equatable {
    var id: Int
    var companyID: Int
}

extension GameStore {
    /// The day's largest customer payment when it is big enough: at least 1.5 percent of net worth or 5 percent of that company's weekly takings.
    func bigPayment(_ e: GameEngine) -> (amount: Double, from: String, company: Company)? {
        guard let p = e.largestPaymentToday(companyID: nil), let co = e.state.company(p.companyID) else { return nil }
        let nw: Double = max(1, e.dayHistory.netWorth.last ?? 0)
        let weekly: Double = co.lastWeekRevenue
        let bigVsWorth: Bool = p.amount >= nw * 0.015
        let bigVsWeek: Bool = weekly > 0 && p.amount >= weekly * 0.05
        guard bigVsWorth || bigVsWeek else { return nil }
        return (p.amount, p.from, co)
    }
}
