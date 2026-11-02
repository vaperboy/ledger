import Foundation
import GameCore
import Businesses

/// Reads for the app's market animations; the log itself is written by `MarketEvents` hooks in the weekly code.
public extension GameEngine {
    /// The latest market events, newest first.
    func marketEvents(limit: Int) -> [MarketEvent] { MarketEvents.events(state, limit: limit) }

    /// The single largest customer payment booked today (one company, or all when nil), or nil when none was booked today.
    func largestPaymentToday(companyID: Int?) -> (amount: Double, from: String, companyID: Int)? { MarketEvents.largestPayment(state, companyID: companyID) }

    /// The trade's market price index over the last 30 days.
    func marketTrend(companyID: Int) -> MarketTrend { MarketEvents.trend(state, companyID: companyID) }
}
