import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

/// Stage 2 item 6 and 7: net worth with the estimate kept apart from the money, and the Company Overview / Stats figures (cash first).

public struct CompanyStake: Equatable, Sendable, Identifiable {
    public var id: Int { companyID }
    public var companyID: Int
    public var name: String
    /// The estimated value of the whole company (assets less debts, plus goodwill): an estimate, never spendable money.
    public var estimatedValue: Double
    public var ownershipPercent: Double
    /// Your share of the estimate. Counted once: a company inside a holding shows 0 here and is counted in the holding's value.
    public var attributableEquity: Double
    /// Name of the holding that carries it, if any.
    public var heldThrough: String?
    /// Loans of the company you have guaranteed personally: a memo, not subtracted until the guarantee is called.
    public var guaranteedDebt: Double
}

public struct NetWorthBreakdown: Equatable, Sendable {
    /// Money you can spend: current account plus savings.
    public var liquid: Double
    public var currentAccount: Double
    public var savings: Double
    public var investments: Double
    public var luxury: Double
    /// Your share of the estimated value of private companies and startups (not cash).
    public var estimatedCompanyEquity: Double
    public var stakes: [CompanyStake]
    /// Startups, stakes in others' companies and funds that are not your own companies.
    public var otherEstimatedHoldings: Double
    public var personalDebt: Double
    public var pendingTax: Double
    public var guaranteedCompanyDebt: Double
    public var total: Double
    public var note: String
}

public struct ExpenseLine: Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var amount: Double
    public var share: Double
}

public struct CompanyReserves: Equatable, Sendable {
    /// Display only, computed from what is owed (owner decision, Oct 2026): no real sub-accounts.
    public var payroll: Double
    public var tax: Double
    /// What is left of the company's cash after the reserves (can be negative).
    public var free: Double
}

public struct CompanyOverviewStats: Equatable, Sendable {
    public var companyID: Int
    public var name: String
    /// The first figure of the screen.
    public var cash: Double
    public var runwayWeeks: Double?
    public var reserves: CompanyReserves
    public var period: String
    public var revenue: Double
    public var operatingExpenses: Double
    public var profit: Double
    /// Profit as a share of revenue (nil without revenue).
    public var margin: Double?
    /// Corporate tax booked in the period, shown apart: it is not in the profit above.
    public var taxBooked: Double
    /// Costs from the real books, same categories as the profit.
    public var expenses: [ExpenseLine]
    public var loansOwed: Double
    public var guaranteedLoans: Double
    public var legalForm: String
    public var legalFormShort: String
    public var incorporatedSince: String?
    public var ownershipPercent: Double
    public var otherShareholders: [String]
    public var shareCount: Double?
    public var shareCapital: Double
    public var accountant: String?
    public var equity: Double
    public var estimatedValue: Double
}

public extension GameEngine {
    func netWorthBreakdown() -> NetWorthBreakdown {
        let s = state
        let nw = Valuation.netWorth(s, trades: data.catalog)
        var stakes: [CompanyStake] = []
        var directSum = 0.0, guaranteed = 0.0
        for co in s.companies where co.status.isLive {
            let value = Valuation.companyValue(co, state: s, trades: data.catalog)
            let held = co.holdingID != 0 ? s.company(co.holdingID) : nil
            let attributable = co.holdingID == 0 ? value * co.ownership / 100 : 0
            directSum += attributable
            let g = s.loans.filter { $0.companyID == co.id && $0.isGuaranteed }.reduce(0) { $0 + $1.balance }
            if co.holdingID == 0 { guaranteed += g }
            stakes.append(CompanyStake(companyID: co.id, name: co.name, estimatedValue: value, ownershipPercent: co.ownership, attributableEquity: attributable,
                                       heldThrough: held?.name, guaranteedDebt: g))
        }
        return NetWorthBreakdown(liquid: s.cash + s.savings, currentAccount: s.cash, savings: s.savings, investments: nw.investments, luxury: nw.luxury,
                                 estimatedCompanyEquity: nw.companies, stakes: stakes, otherEstimatedHoldings: max(0, nw.companies - directSum), personalDebt: nw.debt,
                                 pendingTax: nw.pendingTax, guaranteedCompanyDebt: guaranteed, total: nw.total,
                                 note: "Companies are an estimate of what your share would fetch, not money you can spend. Loans you guaranteed for a company count against you only if the company fails.")
    }

    func companyReserves(companyID: Int) -> CompanyReserves? {
        guard let co = state.company(companyID) else { return nil }
        let payroll = (co.payables["wages"] ?? 0) + Payroll.weeklyCost(co, country: context.country(of: co, state)) * 4.33
        let tax = (co.payables["tax"] ?? 0) + max(0, co.vatBalance)
        return CompanyReserves(payroll: payroll, tax: tax, free: co.cash - payroll - tax)
    }

    /// The Company Overview and Stats figures: cash first, then the result of the period with costs from the real books, then legal and ownership facts.
    func companyOverviewStats(companyID: Int, period: ReportPeriodKind = .year) -> CompanyOverviewStats? {
        guard let co = state.company(companyID) else { return nil }
        let b: [String: Double]
        switch period { case .month: b = co.books.month; case .year: b = co.books.year; case .week: b = co.books.week }
        let costKeys = Books.expensesKeys
        let total = costKeys.reduce(0) { $0 + max(0, b[$1] ?? 0) }
        let lines = Self.costLabels.filter { costKeys.contains($0.key) }.compactMap { c -> ExpenseLine? in
            let v = b[c.key] ?? 0
            return v > 0 ? ExpenseLine(id: c.key, label: c.label, amount: v, share: total > 0 ? v / total : 0) : nil
        }.sorted { $0.amount > $1.amount }
        let revenue = b["rev"] ?? 0
        let profit = Books.profit(b)
        let country = data.countries[co.countryCode]
        let forms = country?.companyForms ?? [:]
        let weekly = context.weeklyCost(co, state)
        let loans = state.loans.filter { $0.companyID == companyID }
        let legal = co.value("legal")
        let holders = co.value("holders").array.compactMap { h -> String? in
            let pct = h["pct"].double
            return pct > 0 ? "\(h["name"].string.isEmpty ? "Shareholder" : h["name"].string) \(Int(pct.rounded()))%" : nil
        }
        let acc = co.value("acc")
        let periodName: String
        switch period { case .month: periodName = "This month"; case .year: periodName = "This year"; case .week: periodName = "This week" }
        return CompanyOverviewStats(companyID: companyID, name: co.name, cash: co.cash, runwayWeeks: weekly > 0 && co.cash > 0 ? co.cash / weekly : nil,
                                    reserves: companyReserves(companyID: companyID) ?? CompanyReserves(payroll: 0, tax: 0, free: co.cash), period: periodName, revenue: revenue,
                                    operatingExpenses: total, profit: profit, margin: revenue > 0 ? profit / revenue : nil, taxBooked: b["tax"] ?? 0, expenses: lines,
                                    loansOwed: loans.reduce(0) { $0 + $1.balance }, guaranteedLoans: loans.filter(\.isGuaranteed).reduce(0) { $0 + $1.balance },
                                    legalForm: (co.form == .limited ? forms["limited"] : forms["soleTrader"]) ?? (co.form == .limited ? "Limited company" : "Sole trader"),
                                    legalFormShort: (co.form == .limited ? forms["limitedShort"] : forms["soleTraderShort"]) ?? "",
                                    incorporatedSince: legal["since"].isNull ? nil : GameCalendar.dateString(week: legal["since"].int), ownershipPercent: co.ownership,
                                    otherShareholders: holders, shareCount: legal["shares"]["count"].isNull ? nil : legal["shares"]["count"].double, shareCapital: co.shareCapital,
                                    accountant: acc["name"].isNull ? nil : acc["name"].string, equity: CompanyFigures.assets(co) - CompanyFigures.debts(co, loans: state.loans),
                                    estimatedValue: Valuation.companyValue(co, state: state, trades: data.catalog))
    }
}

public enum ReportPeriodKind: Sendable { case week, month, year }

public extension Books {
    /// The categories that make up costs (and so profit): the same list `Books.expenses` adds up.
    static let expensesKeys: [String] = ["cogs", "wages", "rent", "mkt", "ins", "oth", "dep", "int", "fine", "loss", "acc", "fin"]
}
