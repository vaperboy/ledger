import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum MonthEnd {
    public static func taxRate(_ co: Company, _ bd: Trade, _ country: Country) -> Double {
        if bd.hasTrait("oil") { return Taxes.specialRate("oil", in: country, fallback: min(0.5, country.corporateTax + 0.2)) }
        if bd.id == "salmon" { return Taxes.specialRate("salmon", in: country, fallback: country.corporateTax) }
        if bd.hasTrait("power") { return EnergyModel.sourceIndex(co) == 1 ? Taxes.specialRate("hydro", in: country, fallback: country.corporateTax) : country.corporateTax }
        return country.corporateTax
    }

    static func accrueTax(_ s: inout GameState, companyIndex i: Int, _ bd: Trade, data: GameData) {
        var co = s.companies[i]
        let w = World(state: s, data: data)
        let rate = taxRate(co, bd, w.country(co))
        let lc0 = co.lossCarryAtYearStart ?? 0
        let ev = co.value("evade")
        let kept = ev["y"].int == GameCalendar.year(week: s.week) ? ev["c"].double + ev["l"].double : 0
        let country = w.country(co)
        let profitBeforeLosses = co.yearProfitSoFar - kept
        let used = min(lc0, Taxes.lossOffsetLimit(profit: profitBeforeLosses, in: country))
        let target = max(0, profitBeforeLosses - used) * rate
        let delta = target - co.taxAccrued
        co.taxAccrued = target
        let covered = co.yearProfitSoFar
        co.lossCarryForward = max(0, lc0 + max(0, -covered) - min(lc0, Taxes.lossOffsetLimit(profit: covered, in: country)))
        s.companies[i] = co
        if delta > 0 {
            s.companies[i].addPayable("tax", delta)
            Payments.book(&s, companyID: co.id, category: "tax", amount: delta)
        } else if delta < 0 {
            let unpaid = min(-delta, s.companies[i].payables["tax"] ?? 0)
            s.companies[i].addPayable("tax", -unpaid)
            Payments.book(&s, companyID: co.id, category: "tax", amount: delta)
            let refund = jsRound(-delta - unpaid)
            if refund > 0 {
                AccountingLedger.note(category: "tax", label: "Corporate tax refund")
                Ledger.moveRaw(&s, .company(co.id), refund)
                s.companies[i].addTransaction(week: s.week, amount: refund, label: "Corporate tax refund")
                s.stats.taxPaid -= refund
            }
        }
    }

    static func rollLossLots(_ co: inout Company, country: Country, closingYear: Int) {
        let lc0 = co.lossCarryAtYearStart ?? 0
        let carry = co.lossCarryForward
        let covered = co.yearProfitSoFar
        let newLoss = max(0, -covered)
        var remaining = max(0, lc0 + newLoss - carry)
        var lots: [(year: Int, amount: Double)] = co.value("lossLots").array.map { ($0[0].int, $0[1].double) }
        if abs(lots.reduce(0) { $0 + $1.amount } - lc0) > 0.5 { lots = lc0 > 0 ? [(closingYear - 1, lc0)] : [] }
        lots.sort { $0.year < $1.year }
        for i in lots.indices where remaining > 0 {
            let take = min(remaining, lots[i].amount)
            lots[i].amount -= take; remaining -= take
        }
        if newLoss > 0 { lots.append((closingYear, newLoss)) }
        lots = lots.filter { $0.amount > 0.005 && (country.lossYears == 0 || closingYear - $0.year < country.lossYears) }
        co.lossCarryForward = lots.reduce(0) { $0 + $1.amount }
        co.set("lossLots", .array(lots.map { .array([.number(Double($0.year)), .number($0.amount)]) }))
    }

    @discardableResult
    static func settleTax(_ s: inout GameState, companyIndex i: Int, context: FinanceContext) -> Double {
        var co = s.companies[i]
        let owed = co.payables["tax"] ?? 0
        let paid = max(0, min(owed, max(0, co.cash + context.overdraftRoom(co, s))))
        if paid > 0 {
            AccountingLedger.note(category: "tax", label: "Corporate tax")
            Ledger.moveRaw(&s, .company(co.id), -paid)
            co = s.companies[i]
            co.payables["tax"] = max(0, owed - paid)
            co.addTransaction(week: s.week, amount: -jsRound(paid), label: "Corporate tax")
            s.stats.taxPaid += paid
        }
        co.taxPrevYear = min(co.taxPrevYear, co.payables["tax"] ?? 0)
        if co.taxPrevYear < 1 { co.taxDue = false }
        s.companies[i] = co
        return owed - paid
    }

    public static func closeMonth(_ s: inout GameState, companyIndex i: Int, data: GameData, context: FinanceContext) {
        let co0 = s.companies[i]
        guard let bd = data.catalog[co0.type] else { return }
        var w = World(state: s, data: data)
        let country = w.country(co0)
        if co0.managerID != nil, co0.managerProfitBonus > 0, s.people[co0.managerID!] != nil, co0.status == .open {
            let b = co0.books.month
            let p0 = (b["rev"] ?? 0) - Books.expenses(b)
            if p0 > 0 {
                let x = p0 * co0.managerProfitBonus * country.payrollFactor(monthlyWage: co0.managerMonthlyWage)
                s.companies[i].addPayable("wages", x)
                Payments.book(&s, companyID: co0.id, category: "wages", amount: x)
                s.companies[i].set("mgrBonusLast", jsRound(x))
            } else { s.companies[i].set("mgrBonusLast", 0) }
        }
        var co = s.companies[i]
        let month = co.books.month
        let profit = (month["rev"] ?? 0) - Books.expenses(month)
        if co.status != .setup {
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
        w = World(state: s, data: data)
        s.companies[i] = co
        let unpaidTax = settleTax(&s, companyIndex: i, context: context)
        co = s.companies[i]
        let freq = max(1, country.vatFilingMonths == 0 ? 2 : country.vatFilingMonths)
        var vatUnpaid = 0.0
        let filing = GameCalendar.monthIndex(week: s.week) % freq == freq - 1
        let vatRoom = max(0, s.companies[i].cash + context.overdraftRoom(s.companies[i], s))
        if filing {
            let v = jsRound(co.vatBalance)
            if v > 0 {
                let pay = min(v, vatRoom)
                if pay > 0 {
                    AccountingLedger.note(category: "tax", label: "VAT settlement")
                    Ledger.moveRaw(&s, .company(co.id), -pay)
                    s.companies[i].addTransaction(week: s.week, amount: -pay, label: "VAT settlement")
                    s.stats.taxPaid += pay
                }
                var rest = v - pay
                if rest > 1 {
                    let carried = min(s.companies[i].num("vatOver"), v)
                    let penalty = jsRound(min(rest, max(0, v - carried)) * 0.05)
                    Payments.book(&s, companyID: co.id, category: "fine", amount: penalty)
                    rest += penalty
                    s.companies[i].set("vatOver", rest)
                    s.addDeskNotice("finance", company: co, data: data, title: "VAT return not paid at \(co.name)",
                                    body: "\(w.currency(co).display(v - pay)) of VAT could not be paid on time. A penalty of \(w.currency(co).display(penalty)) was added and interest runs until it is paid.")
                    vatUnpaid = rest
                } else { rest = 0; s.companies[i].set("vatOver", 0) }
                s.companies[i].vatBalance = rest
            } else {
                if v < 0 { Payments.companyReceives(&s, companyID: co.id, amount: -v, category: nil, label: "VAT refund") }
                s.companies[i].vatBalance = 0
                s.companies[i].set("vatOver", 0)
            }
        } else if s.companies[i].num("vatOver") > 1 {
            var over = s.companies[i].num("vatOver")
            let interest = jsRound(over * 0.01)
            Payments.book(&s, companyID: co.id, category: "int", amount: interest)
            over += interest
            s.companies[i].vatBalance += interest
            let pay = min(over, max(0, s.companies[i].vatBalance), vatRoom)
            if pay > 0 {
                AccountingLedger.note(category: "tax", label: "VAT settlement (overdue)")
                Ledger.moveRaw(&s, .company(co.id), -pay)
                s.companies[i].addTransaction(week: s.week, amount: -pay, label: "VAT settlement (overdue)")
                s.stats.taxPaid += pay
                s.companies[i].vatBalance -= pay
                over -= pay
            }
            if over < 1 {
                s.companies[i].set("vatOver", 0)
                s.addDeskNotice("finance", company: co, data: data, title: "VAT paid up at \(co.name)", body: "The overdue VAT is paid. Interest stops.", tone: "good", sev: 1)
            } else { s.companies[i].set("vatOver", over); vatUnpaid = over }
        }
        co = s.companies[i]
        if unpaidTax + vatUnpaid > w.currency(co).scaledPrice(1500) {
            co.unpaidMonths += 1
            s.companies[i] = co
            if co.unpaidMonths == 1 {
                s.addDeskNotice("finance", company: co, data: data, title: "Could not pay all bills at \(co.name)",
                                body: "Missing \(w.currency(co).display(unpaidTax + vatUnpaid)) this month. Put money in or cut costs.")
            }
        } else { co.unpaidMonths = 0; s.companies[i] = co }
        co = s.companies[i]
        if co.status != .bust {
            var hist = co.monthlyHistory
            hist.append(MonthRecord(monthIndex: GameCalendar.monthIndex(week: s.week), revenue: month["rev"] ?? 0, profit: profit, cash: co.cash))
            if hist.count > 60 { hist.removeFirst() }
            co.monthlyHistory = hist
            var h = co.monthlyHistory
            if var last = h.last {
                last.set("bk", .object(month.mapValues { .number($0) }))
                ClawBack.mark(&last, co, loans: s.loans)
                h[h.count - 1] = last; co.monthlyHistory = h
            }
        }
        if co.managerID != nil {
            let mood = co.value("mood").isNull ? 60 : co.num("mood")
            co.set("mood", clamp(mood + (profit > 0 ? 1.5 : -2) + (60 - mood) * 0.05, 0, 100))
        }
        var b = co.books; b.month = [:]; co.books = b
        s.companies[i] = co
    }

    public static func closeMonth(_ s: inout GameState, data: GameData, context: FinanceContext) {
        for i in s.companies.indices where s.companies[i].status.isLive { closeMonth(&s, companyIndex: i, data: data, context: context) }
        FootballModel.monthly(&s)
        PersonalFinance.monthly(&s, context: context)
        PersonalFinance.withholdNow(&s, context: context)
        TaxSettlement.withholdWealthTax(&s, data: data, context: context)
        var rates = ExchangeRates(drift: s.exchangeRates.values)
        rates.monthlyDrift(book: data.countries, homeCode: s.homeCountryCode, random: &s.random)
        let euro = data.countries.countries.filter { $0.currencyCode == "EUR" }.map { $0.code }
        let homeIsEuro = euro.contains(s.homeCountryCode)
        let v: Double = homeIsEuro ? 1 : (euro.compactMap { rates.drift[$0] }.first(where: { $0 != 0 }) ?? 1)
        for k in euro { rates.drift[k] = v }
        s.exchangeRates = GameState.ExchangeDrift(rates.drift)
        Abroad.regulationMonth(&s, data: data)
    }

    public static func closeYear(_ s: inout GameState, data: GameData, context: FinanceContext) {
        let world = World(state: s, data: data)
        let closingYear = GameCalendar.year(week: s.week)
        for i in s.companies.indices where s.companies[i].status.isLive {
            var co = s.companies[i]
            var flags = co.value("flags"); flags["fraud"] = 0; co.set("flags", flags)
            do {
                let country = world.country(co)
                rollLossLots(&co, country: country, closingYear: closingYear)
                co.taxPrevYear = co.payables["tax"] ?? 0
                co.taxDue = co.taxPrevYear >= 1
                co.taxDueWeek = s.week
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
