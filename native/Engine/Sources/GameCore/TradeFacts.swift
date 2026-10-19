import Foundation

/// The few facts about a type of business that the money code needs. The full definition is `Businesses.Trade`.
public protocol TradeFacts: Sendable {
    var id: String { get }
    /// "svc", "venue", "retail", "project", "prod", "logi", "rent", "fin", "energy", "hold", "club"
    var family: String { get }
    /// Fixed costs per week at size 1
    var fixedWeekly: Double { get }
    /// Profit margin used to judge what the business is worth
    var margin: Double { get }
}

public protocol TradeCatalogProviding: Sendable {
    func facts(for tradeID: String) -> TradeFacts?
}
