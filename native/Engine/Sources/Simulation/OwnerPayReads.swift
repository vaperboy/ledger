import Foundation
import GameCore
import Countries
import Finance
import Businesses

public struct OwnerPayOption: Equatable, Sendable, Identifiable {
    public enum Route: String, Sendable { case salary, dividend, retain }
    public var id: String { route.rawValue }
    public var route: Route
    public var title: String
    public var cashFromCompany = 0.0
    public var employerContributions = 0.0
    public var companyTaxChange = 0.0
    public var personalTax = 0.0
    public var netInHand = 0.0
    public var totalTax: Double { employerContributions + personalTax + companyTaxChange }
    public var companyCostAfterTax: Double { cashFromCompany + companyTaxChange }
    public var explanation = ""
    public init(route: Route, title: String) { self.route = route; self.title = title }
}

public struct OwnerPayComparison: Equatable, Sendable {
    public var companyID: Int
    public var amount: Double
    public var corporateRate: Double
    public var dividendRate: Double
    public var dividendShieldLeft: Double
    public var options: [OwnerPayOption]
}

public extension GameEngine {
    func ownerPayOptions(companyID: Int, amount: Double) -> OwnerPayComparison? {
        guard let co = state.company(companyID), amount > 0 else { return nil }
        let country = context.country(of: co, state)
        let home = context.homeCountry(state)
        let corp = data.catalog[co.type].map { MonthEnd.taxRate(co, $0, country) } ?? country.corporateTax
        let est = taxEstimate()

        var salary = OwnerPayOption(route: .salary, title: "Salary")
        let factor = country.payrollFactor(monthlyWage: amount / 12)
        salary.employerContributions = amount * (factor - 1)
        salary.cashFromCompany = amount * factor
        salary.companyTaxChange = -salary.cashFromCompany * corp
        let base = est.taxableIncome
        salary.personalTax = Taxes.personalIncomeTax(base + amount, kind: .wage, in: home) - Taxes.personalIncomeTax(base, kind: .wage, in: home)
        salary.netInHand = amount - salary.personalTax
        salary.explanation = "A cost to the company, so its profit tax falls by \(Currency.percent(corp, decimals: 1)) of it. You pay income tax and social contributions on it, and the company pays employer contributions on top."

        var dividend = OwnerPayOption(route: .dividend, title: "Dividend")
        dividend.cashFromCompany = amount
        let toYou = co.holdingID == 0 ? amount * co.ownership / 100 : 0
        dividend.personalTax = Taxes.dividendTax(est.dividends + toYou, shield: est.shield, in: home) - Taxes.dividendTax(est.dividends, shield: est.shield, in: home)
        dividend.netInHand = toYou - dividend.personalTax
        dividend.explanation = "Not a cost: the company's profit tax does not change. You pay \(Currency.percent(home.dividendTax, decimals: 1)) dividend tax, withheld when it is paid, on dividends above the tax-free shield."

        var retain = OwnerPayOption(route: .retain, title: "Keep it in the company")
        retain.explanation = "No tax is added now. The company keeps the money, and a later dividend or salary is taxed when it is paid."

        return OwnerPayComparison(companyID: companyID, amount: amount, corporateRate: corp, dividendRate: home.dividendTax,
                                  dividendShieldLeft: max(0, est.shield - est.dividends), options: [salary, dividend, retain])
    }
}
