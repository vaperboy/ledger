import Foundation

public protocol TradeFacts: Sendable {
    var id: String { get }
    var family: String { get }
    var fixedWeekly: Double { get }
    var margin: Double { get }
    var ownerFTE: Double { get }
}

public protocol TradeCatalogProviding: Sendable {
    func facts(for tradeID: String) -> TradeFacts?
}
