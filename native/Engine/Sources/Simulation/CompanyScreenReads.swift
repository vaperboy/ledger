import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {
    func companyLoanPayment(amount: Double, termMonths: Int, companyID: Int) -> Double {
        let off = loanOffer(kind: "biz", amount: amount, companyID: companyID)
        let rate = state.economy.policyRate + Banking.countryRateShift(companyID: companyID, state: state, context: context) + off.margin
        return Loans.annuity(principal: amount, yearlyRate: rate, months: Double(max(1, termMonths)))
    }

    func closeNoticeTerms(companyID: Int) -> (notice: Double, depositBack: Double)? {
        guard let co = state.company(companyID) else { return nil }
        let prem = co.value("prem")
        guard prem["m2"].double > 0, !prem["owned"].bool else { return nil }
        return (prem["rent"].double * prem["m2"].double / 12 * 3, prem["dep"].double)
    }
}
