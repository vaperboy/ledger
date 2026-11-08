import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// One way of paying yourself out of a limited company, with what it leaves in your hand and what tax it adds.
public struct OwnerPayOption: Equatable, Sendable, Identifiable {
    public enum Route: String, Sendable { case salary, dividend, retain }
    public var id: String { route.rawValue }
    public var route: Route
    public var title: String
    /// Cash that leaves the company (a salary includes the employer's contributions).
    public var cashFromCompany = 0.0
    /// Employer contributions on a salary.
    public var employerContributions = 0.0
    /// Change in the company's profit tax: negative when the pay is a deductible cost.
    public var companyTaxChange = 0.0
    /// Personal tax this adds (income tax on a salary, withheld from pay; dividend tax on a dividend, withheld on payout).
    public var personalTax = 0.0
    public var netInHand = 0.0
    /// Contributions plus personal tax plus the change in company tax.
    public var totalTax: Double { employerContributions + personalTax + companyTaxChange }
    /// What the company is really out of after its own tax effect.
    public var companyCostAfterTax: Double { cashFromCompany + companyTaxChange }
    /// Plain-language rule for this route in the player's country.
    public var explanation = ""
    public init(route: Route, title: String) { self.route = route; self.title = title }
}

public struct OwnerPayComparison: Equatable, Sendable {
    public var companyID: Int
    public var amount: Double
    public var corporateRate: Double
    public var dividendRate: Double
    /// Dividends still free of tax this year under the country's shield.
    public var dividendShieldLeft: Double
    public var options: [OwnerPayOption]
}

public extension GameEngine {
    /// Salary against dividend against keeping `amount` in a limited company: net in hand and the tax each adds on top of this year's
    /// income and dividends so far. Nil for a company that is not a limited company or does not exist.
    func ownerPayOptions(companyID: Int, amount: Double) -> OwnerPayComparison? {
        guard let co = state.company(companyID), co.form == .limited, amount > 0 else { return nil }
        let country = context.country(of: co, state)
        let home = context.homeCountry(state)
        let corp = data.catalog[co.type].map { MonthEnd.taxRate(co, $0, country) } ?? country.corporateTax
        let est = taxEstimate()

        // Salary: the amount is the gross pay; the company also pays contributions and deducts both.
        var salary = OwnerPayOption(route: .salary, title: "Salary")
        let factor = country.payrollFactor(monthlyWage: amount / 12)
        salary.employerContributions = amount * (factor - 1)
        salary.cashFromCompany = amount * factor
        salary.companyTaxChange = -salary.cashFromCompany * corp
        let base = est.taxableIncome
        salary.personalTax = Taxes.personalIncomeTax(base + amount, kind: .wage, in: home) - Taxes.personalIncomeTax(base, kind: .wage, in: home)
        salary.netInHand = amount - salary.personalTax
        salary.explanation = "A cost to the company, so its profit tax falls by \(Currency.percent(corp, decimals: 1)) of it. You pay income tax and social contributions on it, and the company pays employer contributions on top."

        // Dividend: paid from profit that has already borne company tax; only your share reaches you, a holding's share stays in the group.
        var dividend = OwnerPayOption(route: .dividend, title: "Dividend")
        dividend.cashFromCompany = amount
        let toYou = co.holdingID == 0 ? amount * co.ownership / 100 : 0
        dividend.personalTax = Taxes.dividendTax(est.dividends + toYou, shield: est.shield, in: home) - Taxes.dividendTax(est.dividends, shield: est.shield, in: home)
        dividend.netInHand = toYou - dividend.personalTax
        dividend.explanation = "Not a cost: the company's profit tax does not change. You pay \(Currency.percent(home.dividendTax, decimals: 1)) dividend tax, withheld when it is paid, on dividends above the tax-free shield."

        // Retain: nothing leaves and nothing is added now.
        var retain = OwnerPayOption(route: .retain, title: "Keep it in the company")
        retain.explanation = "No tax is added now. The company keeps the money, and a later dividend or salary is taxed when it is paid."

        return OwnerPayComparison(companyID: companyID, amount: amount, corporateRate: corp, dividendRate: home.dividendTax,
                                  dividendShieldLeft: max(0, est.shield - est.dividends), options: [salary, dividend, retain])
    }
}
