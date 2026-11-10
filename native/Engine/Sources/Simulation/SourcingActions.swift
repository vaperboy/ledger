import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {
    func sourcingSummary(companyID: Int) -> Sourcing.Summary? {
        state.company(companyID).flatMap { Sourcing.summary(state, company: $0, data: data, classes: marketing.goodsClasses) }
    }
    func sourcingOffers(companyID: Int, goodsClass: Int? = nil) -> [Sourcing.Offer] {
        state.company(companyID).map { Sourcing.offers(state, company: $0, goodsClass: goodsClass, data: data, classes: marketing.goodsClasses) } ?? []
    }
    func isSuppliedFromInside(companyID: Int) -> Bool { Sourcing.suppliedFromInside(state, companyID: companyID) }
}
