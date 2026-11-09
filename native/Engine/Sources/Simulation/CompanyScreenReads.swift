import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Read-only figures for the company screens (Finances, loans and the company's settings). Nothing here changes the game.
public extension GameEngine {
    /// The monthly instalment `takeLoan` would set for a business loan of this amount and term (same rate and annuity as the bank uses).
    func companyLoanPayment(amount: Double, termMonths: Int, companyID: Int) -> Double {
        let off = loanOffer(kind: "biz", amount: amount, companyID: companyID)
        let rate = state.economy.policyRate + Banking.countryRateShift(companyID: companyID, state: state, context: context) + off.margin
        return Loans.annuity(principal: amount, yearlyRate: rate, months: Double(max(1, termMonths)))
    }

    /// Giving up a rented place when closing for a while: three months' rent as notice, and the deposit back. nil when there is no rented place.
    func closeNoticeTerms(companyID: Int) -> (notice: Double, depositBack: Double)? {
        guard let co = state.company(companyID) else { return nil }
        let prem = co.value("prem")
        guard prem["m2"].double > 0, !prem["owned"].bool else { return nil }
        return (prem["rent"].double * prem["m2"].double / 12 * 3, prem["dep"].double)
    }
}
