import Foundation
import GameCore
import Countries
import Finance
import Businesses

public struct SetupFunding: Equatable, Sendable {
    public var missing: Double
    public var loanMaximum: Double
    public var shortfall: Double { max(0, missing - loanMaximum) }
    public var isCompletable: Bool { shortfall <= 0 }
}

public extension GameEngine {
    func setupFunding(companyID: Int) -> SetupFunding? {
        guard let co = state.company(companyID), co.status == .setup, let bd = data.catalog[co.type] else { return nil }
        let missing = OpeningChecklist.missingCash(co, bd, World(state: state, data: data))
        let loan = missing > 0 ? loanOffer(kind: "biz", amount: missing, companyID: companyID).maximum : 0
        return SetupFunding(missing: missing, loanMaximum: loan)
    }

    @discardableResult
    mutating func fundSetup(companyID: Int) -> SetupFunding? {
        guard let f = setupFunding(companyID: companyID), f.missing > 0 else { return setupFunding(companyID: companyID) }
        let amount = min(f.loanMaximum, (f.missing / 1000).rounded(.up) * 1000)
        if amount >= 1000 { _ = takeLoan(kind: "biz", amount: amount, termMonths: 60, companyID: companyID) }
        return setupFunding(companyID: companyID)
    }
}
