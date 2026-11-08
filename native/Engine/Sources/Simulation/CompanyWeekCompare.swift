import Foundation
import GameCore
import Finance

/// A company's main figures for one stretch of time.
public struct CompanyWeekFigures: Equatable, Sendable {
    public var sales: Double
    public var wages: Double
    /// Every cost, wages included.
    public var costs: Double
    public var profit: Double
}

/// What a company page needs to show the main figures moving: the week running now (it grows as each day plays), and the last closed
/// week beside the one before it.
public struct CompanyWeekCompare: Equatable, Sendable {
    /// The week so far, from the live books.
    public var soFar: CompanyWeekFigures
    /// The last closed week and its title ("Week 31"); nil before the first one closes.
    public var last: CompanyWeekFigures?
    public var lastTitle: String?
    /// The week before that one.
    public var before: CompanyWeekFigures?
}

public extension GameEngine {
    func companyWeekCompare(companyID: Int) -> CompanyWeekCompare? {
        guard let co = state.company(companyID) else { return nil }
        let b: [String: Double] = co.books.week
        let costs: Double = Books.expensesKeys.reduce(0) { $0 + max(0, b[$1] ?? 0) }
        let soFar = CompanyWeekFigures(sales: b["rev"] ?? 0, wages: max(0, b["wages"] ?? 0), costs: costs, profit: Books.profit(b))
        func figures(_ p: ReportPnL) -> CompanyWeekFigures { CompanyWeekFigures(sales: p.revenue, wages: p.wages, costs: p.costs, profit: p.netProfit) }
        guard let r = reports(.week).last, let c = r.company(companyID) else { return CompanyWeekCompare(soFar: soFar) }
        let prev: CompanyWeekFigures? = r.previous?.companies.first { $0.id == companyID }.map { figures($0.pnl) }
        return CompanyWeekCompare(soFar: soFar, last: figures(c.pnl), lastTitle: r.title, before: prev)
    }
}
