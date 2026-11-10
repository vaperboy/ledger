import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

public struct ExpenseLine: Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var amount: Double
    public var share: Double
}

public struct CompanyOverviewStats: Equatable, Sendable {
    public var companyID: Int
    public var name: String
    public var cash: Double
    public var runwayWeeks: Double?
    public var period: String
    public var revenue: Double
    public var operatingExpenses: Double
    public var profit: Double
    public var margin: Double?
    public var taxBooked: Double
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
    }

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
            return pct > 0 ? "\(h["name"].string.isEmpty ? "Shareholder" : h["name"].string) \(Int(saturating: pct.rounded()))%" : nil
        }
        let acc = co.value("acc")
        let periodName: String
        switch period { case .month: periodName = "This month"; case .year: periodName = "This year"; case .week: periodName = "This week" }
        return CompanyOverviewStats(companyID: companyID, name: co.name, cash: co.cash, runwayWeeks: weekly > 0 && co.cash > 0 ? co.cash / weekly : nil,
                                    period: periodName, revenue: revenue,
                                    operatingExpenses: total, profit: profit, margin: revenue > 0 ? profit / revenue : nil, taxBooked: b["tax"] ?? 0, expenses: lines,
                                    loansOwed: loans.reduce(0) { $0 + $1.balance }, guaranteedLoans: loans.filter(\.isGuaranteed).reduce(0) { $0 + $1.balance },
                                    legalForm: forms["limited"] ?? "Limited company",
                                    legalFormShort: forms["limitedShort"] ?? "",
                                    incorporatedSince: legal["since"].isNull ? nil : GameCalendar.dateString(week: legal["since"].int), ownershipPercent: co.ownership,
                                    otherShareholders: holders, shareCount: legal["shares"]["count"].isNull ? nil : legal["shares"]["count"].double, shareCapital: co.shareCapital,
                                    accountant: acc["name"].isNull ? nil : acc["name"].string, equity: CompanyFigures.assets(co) - CompanyFigures.debts(co, loans: state.loans),
                                    estimatedValue: Valuation.companyValue(co, state: state, trades: data.catalog))
    }
}

public enum ReportPeriodKind: Sendable { case week, month, year }

public extension Books {
    static let expensesKeys: [String] = ["cogs", "wages", "rent", "mkt", "ins", "oth", "dep", "int", "fine", "loss", "acc", "fin"]
}
