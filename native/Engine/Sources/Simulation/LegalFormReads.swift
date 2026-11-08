import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// One legal form's yearly result at the company's current profit.
public struct LegalFormColumn: Equatable, Sendable, Identifiable {
    public var id: String { form.rawValue }
    public var form: LegalForm
    public var formName: String
    /// Profit taxed under this form after its own running costs.
    public var taxableProfit = 0.0
    /// Company profit tax (limited only).
    public var companyTax = 0.0
    /// Income tax with social contributions (sole trader) or dividend tax on what is paid out (limited).
    public var personalTax = 0.0
    /// Yearly cost of the form (the accountant a limited company must have).
    public var runningCost = 0.0
    public var totalTax: Double { companyTax + personalTax }
    /// What reaches you in a year if all profit is taken out.
    public var keep = 0.0
    /// Limited only: what the company could keep inside instead, after its own tax.
    public var keepInCompany = 0.0
    public var liability = ""
    public var paperwork = ""
    public init(form: LegalForm, formName: String) { self.form = form; self.formName = formName }
}

public struct LegalFormComparison: Equatable, Sendable {
    public enum Better: String, Sendable { case soleTrader, limited, even }
    public var companyID: Int
    public var currentForm: LegalForm
    /// Yearly profit both columns are worked from: the last twelve closed months, else this year's books.
    public var profit: Double
    public var soleTrader: LegalFormColumn
    public var limited: LegalFormColumn
    public var better: Better
    /// What the better form leaves you over the other, per year.
    public var advantage = 0.0
    public var recommendation = ""
    public var currentColumn: LegalFormColumn { currentForm == .limited ? limited : soleTrader }
}

public extension GameEngine {
    /// Sole trader against limited company at the company's current yearly profit, from the engine's own tax functions: personal income tax and
    /// social contributions on one side; the country's corporate rate, dividend tax above the shield and the accountant's fee on the other.
    /// Nil when the company or its country is unknown.
    func legalFormCompare(companyID: Int) -> LegalFormComparison? {
        guard let co = state.company(companyID), let country = data.countries[co.countryCode] else { return nil }
        let home = context.homeCountry(state)
        let profit: Double = Unlocks.yearProfit(co) ?? Books.profit(co.books.year)
        let corp: Double = data.catalog[co.type].map { MonthEnd.taxRate(co, $0, country) } ?? country.corporateTax
        let forms = country.companyForms
        let plan = conversionPlan(companyID: companyID)
        let accountantYear: Double = (plan?.accountantMonthlyFee ?? 0) * 12
        // A limited company or a business with an accountant already carries the fee inside its profit.
        let accountantBorne: Bool = co.form == .limited || !co.value("acc")["id"].isNull
        let capital: Double = plan?.shareCapital ?? 0

        var sole = LegalFormColumn(form: .soleTrader, formName: forms["soleTrader"] ?? "Sole trader")
        sole.taxableProfit = profit
        sole.personalTax = Taxes.personalIncomeTax(profit, kind: .selfEmployed, in: home)
        sole.keep = profit - sole.personalTax
        sole.liability = "Unlimited: your own savings and property answer for the business's debts."
        sole.paperwork = "One personal tax return. No separate company accounts."

        var ltd = LegalFormColumn(form: .limited, formName: forms["limited"] ?? "Limited company")
        ltd.runningCost = accountantYear
        ltd.taxableProfit = profit - (accountantBorne ? 0 : accountantYear)
        ltd.companyTax = max(0, ltd.taxableProfit) * corp
        ltd.keepInCompany = ltd.taxableProfit - ltd.companyTax
        let toYou: Double = max(0, ltd.keepInCompany) * min(100, co.ownership) / 100
        let shield: Double = max(taxEstimate().shield, capital * home.dividendShield)
        ltd.personalTax = Taxes.dividendTax(toYou, shield: shield, in: home)
        ltd.keep = toYou - ltd.personalTax
        ltd.liability = "Limited to what the company holds; loans you have signed for still carry your personal guarantee."
        ltd.paperwork = "Company accounts and a company tax return every year, an accountant on the books, and salary or dividends instead of drawings."

        let gap: Double = ltd.keep - sole.keep
        let margin: Double = max(1, abs(profit)) * 0.02   // under 2% of profit counts as even
        var out = LegalFormComparison(companyID: companyID, currentForm: co.form, profit: profit, soleTrader: sole, limited: ltd, better: .even)
        if profit <= 0 {
            out.recommendation = "No profit to tax at the moment, so the form changes nothing yet. A limited company still protects your own assets."
        } else if abs(gap) <= margin {
            out.recommendation = "Both forms leave you about the same at this profit. Choose on risk: limited liability against less paperwork."
        } else if gap > 0 {
            out.better = .limited
            out.advantage = gap
            out.recommendation = "A limited company leaves you more at this profit, and protects your own assets."
        } else {
            out.better = .soleTrader
            out.advantage = -gap
            out.recommendation = "Staying a sole trader leaves you more at this profit and costs less paperwork; a limited company pays off as profit grows."
        }
        return out
    }
}
