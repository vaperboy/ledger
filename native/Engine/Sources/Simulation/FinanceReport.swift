import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// A line in a money summary.
public struct FinanceLine: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var amount: Double
    public var detail: String = ""
    /// Share of the group total, 0...1, when the line is part of a breakdown.
    public var share: Double = 0
}

/// One rule of the country a company works in, as a label and a value ("Corporate tax", "25%").
public struct RuleLine: Identifiable, Equatable, Sendable {
    public var id: String { label }
    public var label: String
    public var value: String
}

/// A payment that is coming. `essential` ones (wages, tax, loans, rent) cannot be skipped without consequences.
public struct Obligation: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var amount: Double
    public var dayNumber: Int
    public var dateText: String
    public var daysAway: Int
    public var essential: Bool
    public var companyID: Int
}

/// Everything the Finance & Taxes screen shows, derived from the books, payables, loans and calendar. Nothing here is stored.
public struct FinanceOverview: Equatable, Sendable {
    public var monthRevenue = 0.0, monthProfit = 0.0, yearRevenue = 0.0, yearProfit = 0.0, lastYearProfit = 0.0
    /// What is owed in tax and VAT now, and what has been set aside this year.
    public var taxes: [FinanceLine] = []
    public var taxesOwed = 0.0
    public var upcoming: [Obligation] = []
    /// Cash in all companies and the personal account, against what falls due in the next 30 days.
    public var cashAvailable = 0.0
    public var dueWithin30Days = 0.0
    public var costsThisMonth: [FinanceLine] = []
    public var costTotalThisMonth = 0.0
    public var costsThisYear: [FinanceLine] = []
    public var costTotalThisYear = 0.0
    /// The tax rules of the country (the company's, or the home country's), and how far to trust them.
    public var countryName = ""
    public var rules: [RuleLine] = []
    public var basis = ""
    /// Licences, registrations and permits the companies need, with the fee for each (amount) and what keeping it costs (detail).
    public var licences: [FinanceLine] = []
    /// Plain-language findings about how the books look.
    public var notes: [String] = []
    public var shortfall: Double { max(0, dueWithin30Days - cashAvailable) }
}

public extension GameEngine {
    static let costLabels: [(key: String, label: String)] = [
        ("cogs", "Materials and goods"), ("wages", "Wages and employer contributions"), ("rent", "Rent and premises"), ("mkt", "Marketing"),
        ("ins", "Insurance"), ("oth", "Running costs and fees"), ("dep", "Depreciation of equipment"), ("int", "Interest"), ("acc", "Accounting"),
        ("fine", "Fines"), ("loss", "Refunds and losses"), ("tax", "Corporate tax"),
    ]

    private func dateText(_ day: Int) -> String {
        let c = GameCalendar.civilFromDays(day)
        return "\(c.day) \(GameCalendar.monthNames[c.month - 1]) \(c.year)"
    }

    private func breakdown(_ books: [[String: Double]]) -> ([FinanceLine], Double) {
        var sums: [String: Double] = [:]
        for b in books { for (k, v) in b { sums[k, default: 0] += v } }
        let total = Self.costLabels.reduce(0) { $0 + max(0, sums[$1.key] ?? 0) }
        let lines = Self.costLabels.compactMap { c -> FinanceLine? in
            let v = sums[c.key] ?? 0
            return v > 0 ? FinanceLine(id: c.key, label: c.label, amount: v, share: total > 0 ? v / total : 0) : nil
        }.sorted { $0.amount > $1.amount }
        return (lines, total)
    }

    /// Money overview for the whole group, or for one company.
    func financeOverview(companyID: Int? = nil) -> FinanceOverview {
        var o = FinanceOverview()
        let s = state
        let today = Payday.dayNumber(week: s.week, day: s.day)
        let cos = s.liveCompanies.filter { $0.type != "hold" && (companyID == nil || $0.id == companyID) }
        for co in cos {
            let b = co.books
            o.monthRevenue += b.month["rev"] ?? 0; o.monthProfit += Books.profit(b.month)
            o.yearRevenue += b.year["rev"] ?? 0; o.yearProfit += Books.profit(b.year)
            o.lastYearProfit += Books.profit(b.lastYear)
            o.cashAvailable += max(0, co.cash)
        }
        if companyID == nil { o.cashAvailable += max(0, s.cash) + s.savings }
        (o.costsThisMonth, o.costTotalThisMonth) = breakdown(cos.map { $0.books.month })
        (o.costsThisYear, o.costTotalThisYear) = breakdown(cos.map { $0.books.year })

        // Taxes and VAT
        for co in cos {
            let country = context.country(of: co, s)
            let bd = data.catalog[co.type]
            if co.form == .limited {
                let rate = bd.map { MonthEnd.taxRate(co, $0, country) } ?? country.corporateTax
                let owed = co.payables["tax"] ?? 0
                o.taxes.append(FinanceLine(id: "ct\(co.id)", label: "Corporate tax · \(co.name)", amount: owed,
                                           detail: "\(Currency.percent(rate, decimals: 1)) of taxable profit; \(currency(for: co).display(co.taxAccrued)) set aside for this year"))
                o.taxesOwed += owed
            }
            if abs(co.vatBalance) > 1 {
                o.taxes.append(FinanceLine(id: "vat\(co.id)", label: (co.vatBalance > 0 ? "VAT to pay · " : "VAT to reclaim · ") + co.name, amount: abs(co.vatBalance),
                                           detail: "Collected from customers, not income. Filed every \(max(1, country.vatFilingMonths == 0 ? 2 : country.vatFilingMonths)) months."))
                if co.vatBalance > 0 { o.taxesOwed += co.vatBalance }
            }
        }
        if companyID == nil {
            let est = PersonalFinance.taxEstimate(s, context: context)
            if est > 0 || s.tax.pending > 0 {
                o.taxes.append(FinanceLine(id: "personal", label: "Your personal income tax", amount: max(est, s.tax.pending), detail: "Estimated for this year; settled after year end"))
                o.taxesOwed += s.tax.pending
            }
        }

        // What falls due
        func add(_ id: String, _ title: String, _ detail: String, _ amount: Double, _ day: Int, essential: Bool, company: Int) {
            guard amount > 1 else { return }
            let day = max(day, today)   // anything already due is shown as due today
            o.upcoming.append(Obligation(id: id, title: title, detail: detail, amount: amount, dayNumber: day, dateText: dateText(day), daysAway: day - today, essential: essential, companyID: company))
        }
        let c = GameCalendar.civilFromDays(today)
        let monthEnd = Payday.billDate(year: c.year, month: c.month - 1)
        for co in cos {
            guard let bd = data.catalog[co.type] else { continue }
            let cfg = Payday.config(co, today: today)
            let country = context.country(of: co, s)
            if Payday.hasPayroll(co) {
                let np = Payday.nextPay(co, config: cfg, today: today)
                let est = (co.payables["wages"] ?? 0) + Payday.weeklyWageCost(co, country: country) * Double(max(0, (np - today) / 7))
                let mode = Payday.mode(of: co, trade: bd, config: cfg)
                add("pay\(co.id)", "Payroll · \(co.name)", mode == .manual && !s.policy.autoPayroll ? "Needs your approval" : "Runs by itself", est, np, essential: true, company: co.id)
            }
            let bills = (co.payables["rent"] ?? 0) + (co.payables["other"] ?? 0)
            add("bills\(co.id)", "Rent and supplier bills · \(co.name)", "Paid on the last day of the month", bills, monthEnd, essential: true, company: co.id)
            // Supplier invoices on terms (`SupplyTerms`): one line for each week something falls due and each supplier; overdue ones are due today.
            let weekStart = Payday.dayNumber(week: s.week, day: 0)
            var groups: [String: (name: String, day: Int, amount: Double, late: Bool)] = [:]
            for inv in SupplyTerms.invoices(s, buyer: co.id) {
                let key = "\(inv.providerName)|\(inv.dueWeek)"
                var g = groups[key] ?? (inv.providerName, weekStart + max(0, inv.dueWeek - s.week) * 7, 0, false)
                g.amount += inv.amount; g.late = g.late || inv.dueWeek < s.week || inv.lateWeeks > 0
                groups[key] = g
            }
            for (key, g) in groups.sorted(by: { $0.value.day != $1.value.day ? $0.value.day < $1.value.day : $0.key < $1.key }) {
                add("inv\(co.id)|\(key)", "Invoice · \(g.name) · \(co.name)", g.late ? "Overdue: carries late interest until paid" : "Paid in full on the due date if the account can cover it", g.amount, g.day, essential: true, company: co.id)
            }
            let taxOwed = co.payables["tax"] ?? 0
            if co.taxDue, taxOwed > 1 {
                let due = Payday.dayNumber(week: co.taxDueWeek, day: 0)
                add("ctax\(co.id)", "Corporate tax · \(co.name)", "For last year", min(taxOwed, co.taxPrevYear), max(due, today), essential: true, company: co.id)
            }
            if co.vatBalance > 1 {
                let freq = max(1, country.vatFilingMonths == 0 ? 2 : country.vatFilingMonths)
                var m = GameCalendar.monthIndex(week: s.week)
                while m % freq != freq - 1 { m += 1 }
                let y = m / 12, mo = m % 12
                add("vat\(co.id)", "VAT return · \(co.name)", "Filed every \(freq) months", co.vatBalance, Payday.billDate(year: y, month: mo), essential: true, company: co.id)
            }
        }
        for l in s.loans where l.kind != "start" && l.balance > 1 && (companyID == nil || l.companyID == companyID) {
            add("loan\(l.id)", "Loan instalment · \(l.name)", "Interest and repayment, at month end", l.monthlyPayment, monthEnd, essential: true, company: l.companyID)
        }
        if companyID == nil, let start = s.loans.first(where: { $0.kind == "start" && $0.balance > 1 }) {
            add("loan\(start.id)", "Loan instalment · \(start.name)", "Interest and repayment, at month end", start.monthlyPayment, monthEnd, essential: true, company: 0)
        }
        o.upcoming.sort { $0.dayNumber < $1.dayNumber }
        o.dueWithin30Days = o.upcoming.filter { $0.daysAway <= 30 }.reduce(0) { $0 + $1.amount }

        // Plain-language notes
        if o.shortfall > 0 { o.notes.append("The next 30 days of payments are larger than the cash in your companies and accounts. Move money in, borrow, or delay what can wait.") }
        if o.costTotalThisMonth > 0, let top = o.costsThisMonth.first, top.share > 0.5 { o.notes.append("\(top.label) is \(Int((top.share * 100).rounded()))% of this month's costs.") }
        if o.monthRevenue > 0, o.monthProfit < 0 { o.notes.append("This month costs more than the company earns so far.") }
        let country = companyID.flatMap { state.company($0) }.map { context.country(of: $0, state) } ?? homeCountry
        let w = World(state: s, data: data)
        for co in cos {
            guard let bd = data.catalog[co.type] else { continue }
            let held = co.value("docs")
            for id in Documents.needed(co, bd, w) {
                guard let def = Documents.definition(id, country: w.country(co), tables: data.catalog.tables) else { continue }
                let fee = Documents.cost(id, company: co, bd, w), renewal = Documents.renewalCost(id, company: co, w)
                if fee <= 0 && renewal <= 0 { continue }
                let status = held[id]["st"].string
                var detail = localized(def.issuer, companyID: co.id) + (def.weeks > 0 ? " · \(def.weeks) week\(def.weeks == 1 ? "" : "s") to process" : "")
                if renewal > 0 { detail += " · renewal \(Int(renewal.rounded()))" }
                o.licences.append(FinanceLine(id: "\(co.id)-\(id)", label: (cos.count > 1 ? co.name + ": " : "") + localized(def.name, companyID: co.id) + (status == "ok" ? " ✓" : ""), amount: fee, detail: detail))
            }
        }
        o.countryName = country.name
        func pct(_ v: Double) -> String { let p = v * 100; return p == p.rounded() ? "\(Int(p))%" : String(format: "%.1f%%", p) }
        o.rules = [
            RuleLine(label: "Company profit tax", value: pct(country.corporateTax)),
            RuleLine(label: "Tax on dividends", value: pct(country.dividendTax)),
            RuleLine(label: "Tax on investment gains", value: pct(country.capitalGainsTax)),
            RuleLine(label: "Tax on savings interest", value: pct(country.savingsInterestTax)),
            RuleLine(label: "Employer contributions", value: pct(country.employerSocial + country.employerPension + country.employerInjury)),
            RuleLine(label: "Employee contributions", value: pct(country.employeeSocial)),
            RuleLine(label: country.usesSalesTax ? "Sales tax" : "VAT, standard rate", value: pct(country.vat.standard)),
            RuleLine(label: "VAT, reduced rate", value: pct(country.vat.low)),
            RuleLine(label: "VAT return", value: country.vatFilingMonths == 1 ? "every month" : "every \(country.vatFilingMonths) months"),
        ]
        let b = country.pack["dataBasis"]
        o.basis = b["status"].string == "verified" ? (b["taxes"].string) : "Estimate. " + (b["taxes"].isNull ? "Rates are rounded for play and not checked against current law." : b["taxes"].string)
        o.notes.append("Tax rates and fees are game estimates for each country, not legal advice.")
        return o
    }
}
