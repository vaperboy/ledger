import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The balance sheet of one company, line by line, using exactly the definitions of `CompanyFigures.assets` and `.debts`
/// so the totals agree with the company value, the bank's lending limit and winding up.
public struct CompanyBalanceSheet: Equatable, Sendable {
    public var assets: [FinanceLine]
    public var debts: [FinanceLine]
    public var totalAssets: Double
    public var totalDebts: Double
    public var equity: Double { totalAssets - totalDebts }
    /// Share capital paid in, money the owner has put in over time, and what has been paid out as dividends.
    public var shareCapital: Double
    public var injected: Double
    public var distributed: Double
}

/// One closed month of a company: its profit against what its cash actually did. The difference is money that moved without
/// being profit or loss: the owner putting in or taking out, loans drawn or repaid, equipment bought, stock and unpaid bills.
public struct CompanyCashMonth: Identifiable, Equatable, Sendable {
    public var id: Int { monthIndex }
    public var monthIndex: Int
    public var label: String
    public var profit: Double
    public var cashAtEnd: Double
    /// nil for the first month on record (no earlier month-end cash to compare with).
    public var cashChange: Double?
    public var otherMovements: Double? { cashChange.map { $0 - profit } }
}

/// Read-only figures for the company screens (Finances, loans and the company's settings). Nothing here changes the game.
public extension GameEngine {
    func companyBalanceSheet(companyID: Int) -> CompanyBalanceSheet? {
        guard let co = state.company(companyID) else { return nil }
        let prem = co.value("prem"), fm = co.value("fm"), p = co.payables
        func line(_ id: String, _ label: String, _ v: Double, _ detail: String = "") -> FinanceLine? {
            abs(v) < 0.5 ? nil : FinanceLine(id: id, label: label, amount: v, detail: detail)
        }
        let assets: [FinanceLine?] = [
            line("cash", "Cash", co.cash),
            line("recv", "Customers still to pay", co.receivables.reduce(0) { $0 + $1.amount }),
            line("vatback", "VAT to get back", max(0, -co.vatBalance)),
            line("stock", "Stock", co.inventory),
            line("dep", "Lease deposit", prem["dep"].double),
            line("eq", "Equipment and vehicles", CompanyFigures.equipmentBookValue(co), "book value after depreciation"),
            line("prem", "Premises you own", prem["owned"].bool ? prem["val"].double : 0),
            line("props", "Property", co.value("props").array.reduce(0) { $0 + $1["val"].double }),
            line("lux", "Other assets", co.num("luxBV")),
            line("fm", "Financial assets", fm["assets"].isNull ? 0 : fm["assets"].double),
        ]
        let loanSum = state.loans.filter { $0.companyID == co.id }.reduce(0) { $0 + $1.balance }
        let debts: [FinanceLine?] = [
            line("loans", "Loans", loanSum),
            line("wages", "Wages not yet paid", p["wages"] ?? 0),
            line("bills", "Supplier and other bills", p["other"] ?? 0),
            line("inv", "Supplier invoices", p["inv"] ?? 0),
            line("rent", "Rent owed", p["rent"] ?? 0),
            line("vat", "VAT owed", max(0, co.vatBalance)),
            line("tax", "Tax owed", p["tax"] ?? 0),
            line("liab", "Financial liabilities", fm["liab"].isNull ? 0 : fm["liab"].double),
        ]
        return CompanyBalanceSheet(assets: assets.compactMap { $0 }, debts: debts.compactMap { $0 },
                                   totalAssets: CompanyFigures.assets(co), totalDebts: CompanyFigures.debts(co, loans: state.loans),
                                   shareCapital: co.shareCapital, injected: co.injectedCapital, distributed: co.distributed)
    }

    /// The closed months on record, oldest first, with month-end cash compared month to month.
    func companyCashFlow(companyID: Int, months: Int = 12) -> [CompanyCashMonth] {
        guard let co = state.company(companyID) else { return [] }
        let hist = co.monthlyHistory
        var out: [CompanyCashMonth] = []
        for (k, h) in hist.enumerated() {
            let prev: Double? = k > 0 ? hist[k - 1].cash : nil
            let mi = h.monthIndex
            out.append(CompanyCashMonth(monthIndex: mi, label: "\(GameCalendar.monthNames[((mi % 12) + 12) % 12]) \(mi / 12)", profit: h.profit, cashAtEnd: h.cash,
                                        cashChange: prev.map { h.cash - $0 }))
        }
        return Array(out.suffix(max(1, months)))
    }

    /// What `convertToLimited` takes from your own account: the registration fee and the minimum share capital (which goes into the company).
    func convertToLimitedCost(companyID: Int) -> (registrationFee: Double, shareCapital: Double)? {
        guard let co = state.company(companyID), co.form != .limited, let country = data.countries[co.countryCode] else { return nil }
        return (country.registrationFee, country.shareCapitalMinimum)
    }

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
