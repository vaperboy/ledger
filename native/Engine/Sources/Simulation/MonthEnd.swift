import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Month end and year end for companies. Original: `monthEndCoCore`, `taxAccrue`, `settle`, `monthEnd`, `yearEnd`
/// (engine/core/week.js).
///
/// Order at a month end (documented so cash never moves by surprise):
///  1. each company: manager bonus, corporate tax accrual (profit minus losses carried forward), VAT registration
///     reminder, tax paid when due, VAT settled when the return is due, bills that could not be paid counted,
///     monthly history line written, month's books closed;
///  2. the player: overdraft and savings interest, loan instalments, credit score; advance tax each quarter;
///  3. the currencies drift.
/// Payroll and supplier bills are NOT paid here: they have their own days (see `Payday`).
public enum MonthEnd {
    /// Corporate tax rate of a company: some industries pay more. Original: `coTaxRate`.
    public static func taxRate(_ co: Company, _ bd: Trade, _ country: Country) -> Double {
        if bd.hasTrait("oil") { return Taxes.specialRate("oil", in: country, fallback: min(0.5, country.corporateTax + 0.2)) }
        if bd.id == "salmon" { return Taxes.specialRate("salmon", in: country, fallback: country.corporateTax) }
        if bd.hasTrait("power") { return co.value("srcKind").string == "hydro" ? Taxes.specialRate("hydro", in: country, fallback: country.corporateTax) : country.corporateTax }
        return country.corporateTax
    }

    /// Tax a limited company owes so far this year, with losses carried forward. Original: `taxAccrue`.
    static func accrueTax(_ s: inout GameState, companyIndex i: Int, _ bd: Trade, data: GameData) {
        var co = s.companies[i]
        let w = World(state: s, data: data)
        let rate = taxRate(co, bd, w.country(co))
        let lc0 = co.lossCarryAtYearStart ?? 0
        let target = max(0, co.yearProfitSoFar - lc0) * rate
        let delta = target - co.taxAccrued
        co.taxAccrued = target
        co.lossCarryForward = max(0, lc0 - co.yearProfitSoFar)
        s.companies[i] = co
        if delta > 0 {
            s.companies[i].addPayable("tax", delta)
            Payments.book(&s, companyID: co.id, category: "tax", amount: delta)
        } else if delta < 0 {
            let back = min(-delta, s.companies[i].payables["tax"] ?? 0)
            s.companies[i].addPayable("tax", -back)
            Payments.book(&s, companyID: co.id, category: "tax", amount: -back)
        }
    }

    /// Pay corporate tax once it is due (half a year after year end). Returns what could not be paid.
    /// In day mode wages, rent and suppliers are settled on their own days, so only tax is settled here.
    /// Original: `settle` under R29.
    @discardableResult
    static func settleTax(_ s: inout GameState, companyIndex i: Int, context: FinanceContext) -> Double {
        var co = s.companies[i]
        guard co.taxDue, s.week >= co.taxDueWeek else { return 0 }
        let room = context.overdraftRoom(co, s)
        let left = max(0, co.cash + room)
        let due = min(co.payables["tax"] ?? 0, co.taxPrevYear)
        if due <= 0 { return 0 }
        let paid = min(due, left)
        Ledger.moveRaw(&s, .company(co.id), -paid)
        co = s.companies[i]
        co.payables["tax"] = max(0, (co.payables["tax"] ?? 0) - paid)
        if paid > 0 { co.addTransaction(week: s.week, amount: -jsRound(paid), label: "Corporate tax") }
        s.stats.taxPaid += paid
        co.taxPrevYear = max(0, co.taxPrevYear - paid)
        if co.taxPrevYear < 1 { co.taxDue = false }
        s.companies[i] = co
        return due - paid
    }

    /// A company's month. Original: `monthEndCoCore`.
    public static func closeMonth(_ s: inout GameState, companyIndex i: Int, data: GameData, context: FinanceContext) {
        let co0 = s.companies[i]
        guard let bd = data.catalog[co0.type] else { return }
        var w = World(state: s, data: data)
        let country = w.country(co0)
        // Manager's profit bonus: a share of the month's profit on top of salary, booked as wages, paid with the next payroll.
        if co0.managerID != nil, co0.managerProfitBonus > 0, s.people[co0.managerID!] != nil, co0.status == .open {
            let b = co0.books.month
            let p0 = (b["rev"] ?? 0) - Books.expenses(b)
            if p0 > 0 {
                let x = p0 * co0.managerProfitBonus * country.employerCostFactor
                s.companies[i].addPayable("wages", x)
                Payments.book(&s, companyID: co0.id, category: "wages", amount: x)
                s.companies[i].set("mgrBonusLast", jsRound(x))
            } else { s.companies[i].set("mgrBonusLast", 0) }
        }
        var co = s.companies[i]
        let month = co.books.month
        let profit = (month["rev"] ?? 0) - Books.expenses(month)
        if co.form == .limited && co.status != .setup {
            if co.lossCarryAtYearStart == nil {
                co.lossCarryAtYearStart = co.lossCarryForward
                co.yearProfitSoFar = 0
                co.taxAccrued = 0
            }
            co.yearProfitSoFar += profit
            s.companies[i] = co
            accrueTax(&s, companyIndex: i, bd, data: data)
            co = s.companies[i]
        }
        // VAT registration reminder
        w = World(state: s, data: data)
        let threshold = country.vatThreshold
        if threshold > 0 && co.status == .open && !co.value("flags")["vatAsk"].bool && !Knobs.documentOK(co, "vat")
            && co.monthlyHistory.suffix(12).reduce(0, { $0 + $1.revenue }) >= threshold {
            var flags = co.value("flags"); flags["vatAsk"] = 1; co.set("flags", flags)
            s.companies[i] = co
            s.addMessage(from: co.value("acc")["name"].isNull ? co.name : co.value("acc")["name"].string,
                         title: "VAT registration needed at \(co.name)",
                         body: "Your sales have passed the VAT threshold. You now have to register and charge VAT. Apply under Documents.",
                         companyID: co.id, tone: "bad")
        }
        s.companies[i] = co
        let unpaidTax = settleTax(&s, companyIndex: i, context: context)
        // VAT return, when it is due
        co = s.companies[i]
        let freq = max(1, country.vatFilingMonths == 0 ? 2 : country.vatFilingMonths)
        if GameCalendar.monthIndex(week: s.week) % freq == freq - 1 {
            let v = jsRound(co.vatBalance)
            if v > 0 {
                Ledger.moveRaw(&s, .company(co.id), -v)
                s.companies[i].addTransaction(week: s.week, amount: -v, label: "VAT settlement")
                s.stats.taxPaid += v
            } else if v < 0 {
                Payments.companyReceives(&s, companyID: co.id, amount: -v, category: nil, label: "VAT refund")
            }
            s.companies[i].vatBalance = 0
        }
        co = s.companies[i]
        // Unpaid tax counts as unpaid bills
        if unpaidTax > 1500 {
            co.unpaidMonths += 1
            s.companies[i] = co
            if co.unpaidMonths == 1 {
                s.addMessage(from: co.name, title: "Could not pay all bills at \(co.name)",
                             body: "Missing \(w.currency(co).display(unpaidTax)) this month. Put money in or cut costs.", companyID: co.id, tone: "bad")
            }
        } else { co.unpaidMonths = 0; s.companies[i] = co }
        co = s.companies[i]
        if co.status != .bust {
            var hist = co.monthlyHistory
            hist.append(MonthRecord(monthIndex: GameCalendar.monthIndex(week: s.week), revenue: month["rev"] ?? 0, profit: profit, cash: co.cash))
            if hist.count > 60 { hist.removeFirst() }
            co.monthlyHistory = hist
            var h = co.monthlyHistory
            if var last = h.last { last.set("bk", .object(month.mapValues { .number($0) })); h[h.count - 1] = last; co.monthlyHistory = h }
        }
        if co.managerID != nil {
            let mood = co.value("mood").isNull ? 60 : co.num("mood")
            co.set("mood", clamp(mood + (profit > 0 ? 1.5 : -2) + (60 - mood) * 0.05, 0, 100))
        }
        var b = co.books; b.month = [:]; co.books = b
        s.companies[i] = co
    }

    /// All month-end processing. Original: `monthEnd`.
    /// The owner's standing instruction (`ManagementPolicy.autoDividendWeeks`): a limited company with more spare cash than
    /// that many weeks of costs pays out the surplus, keeping that buffer.
    static func autoDividends(_ s: inout GameState, context: FinanceContext) {
        let weeks = s.policy.autoDividendWeeks
        guard weeks > 0 else { return }
        for co in s.companies where co.status == .open && co.form == .limited {
            let buffer = context.weeklyCost(co, s) * weeks
            let surplus = (Payments.maximumDividend(co, state: s, context: context) - buffer).rounded(.down)
            if surplus > 0 { _ = Payments.payDividend(&s, companyID: co.id, amount: surplus, context: context) }
        }
    }

    public static func closeMonth(_ s: inout GameState, data: GameData, context: FinanceContext) {
        for i in s.companies.indices where s.companies[i].status.isLive { closeMonth(&s, companyIndex: i, data: data, context: context) }
        autoDividends(&s, context: context)
        PersonalFinance.monthly(&s, context: context)
        PersonalFinance.advanceTaxMonthly(&s, context: context)
        var rates = ExchangeRates(drift: s.exchangeRates.values)
        rates.monthlyDrift(book: data.countries, homeCode: s.homeCountryCode, random: &s.random)
        // Euro countries move together. Original: 'euro countries move together'.
        let euro = data.countries.countries.filter { $0.currencyCode == "EUR" }.map { $0.code }
        let homeIsEuro = euro.contains(s.homeCountryCode)
        let v: Double = homeIsEuro ? 1 : (euro.compactMap { rates.drift[$0] }.first(where: { $0 != 0 }) ?? 1)
        for k in euro { rates.drift[k] = v }
        s.exchangeRates = GameState.ExchangeDrift(rates.drift)
    }

    /// Year end. Original: `yearEnd`.
    public static func closeYear(_ s: inout GameState, data: GameData, context: FinanceContext) {
        for i in s.companies.indices where s.companies[i].status.isLive {
            var co = s.companies[i]
            var flags = co.value("flags"); flags["fraud"] = 0; co.set("flags", flags)
            if co.form == .limited {
                co.taxDue = true
                co.taxPrevYear = co.payables["tax"] ?? 0
                co.taxDueWeek = s.week + 26
                co.lossCarryAtYearStart = co.lossCarryForward
                co.yearProfitSoFar = 0
                co.taxAccrued = 0
            }
            s.companies[i] = co
        }
        let nw = Valuation.netWorth(s, trades: data.catalog)
        let owned = s.companies.filter { $0.status != .sold }.reduce(0) { $0 + Valuation.companyValue($1, state: s, trades: data.catalog) * $1.ownership / 100 }
        PersonalFinance.yearEnd(&s, context: context, netWorth: nw.total, ownedCompanyValue: owned)
        for i in s.companies.indices where s.companies[i].status.isLive {
            var b = s.companies[i].books
            b.lastYear = b.year; b.year = [:]
            s.companies[i].books = b
            settleTax(&s, companyIndex: i, context: context)
        }
        s.note("New year. Annual accounts closed for all companies.", tone: "n")
        s.news("A new year begins.", tone: "n")
    }
}
