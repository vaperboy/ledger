import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Sourcing read models for the Suppliers tab. The choosing itself is in `SupplierActions` (`srcv`, `srcc`, `fixv`); these show what a
/// choice does (cost of the goods, quality shift, repair discount, protection of supply from inside).
public extension GameEngine {
    /// The Suppliers tab of a company: who supplies goods and repairs now, what the goods cost, the board's agreements.
    func sourcingSummary(companyID: Int) -> Sourcing.Summary? {
        state.company(companyID).flatMap { Sourcing.summary(state, company: $0, data: data, classes: marketing.goodsClasses) }
    }
    /// The suppliers on offer for a quality class (nil = the company's own class), cheapest first, each with its cost and quality effect.
    func sourcingOffers(companyID: Int, goodsClass: Int? = nil) -> [Sourcing.Offer] {
        state.company(companyID).map { Sourcing.offers(state, company: $0, goodsClass: goodsClass, data: data, classes: marketing.goodsClasses) } ?? []
    }
    /// Is this company protected from outside supplier events because one of your own companies supplies its goods?
    func isSuppliedFromInside(companyID: Int) -> Bool { Sourcing.suppliedFromInside(state, companyID: companyID) }
}
