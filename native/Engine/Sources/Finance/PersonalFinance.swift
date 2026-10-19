import Foundation
import GameCore
import Countries

/// The player's own money: savings interest, overdraft, tax. Original: `personalMonth`, `advTaxMonth`,
/// `yearEndPersonal`, `enkIncome` in engine/money/money.js.
public enum PersonalFinance {
    /// Profit of sole-trader businesses this year, less head-office costs. Original: `enkIncome`.
    public static func soleTraderIncome(_ s: GameState) -> Double {
        var t = s.tax.soleTraderFrozenProfit
        for c in s.companies where c.form == .soleTrader && c.status != .sold {
            let y = c.books.year
            t += (y["rev"] ?? 0) - Books.expenses(y)
        }
        return t - s.tax.headOfficeDeduction
    }

    /// Income tax this year if the year ended now, minus tax already withheld. Original: `personalTaxEstimate`.
    public static func taxEstimate(_ s: GameState, context: FinanceContext) -> Double {
        let c = context.homeCountry(s)
        let enk = max(0, soleTraderIncome(s) - s.enkLoss)
        let wage = s.tax.salary
        let tax1 = Taxes.personalIncomeTax(enk + wage, kind: wage > enk ? .wage : .selfEmployed, in: c)
        return max(0, tax1 - s.tax.withheld) + max(0, s.tax.gains) * c.dividendTax
            + Taxes.dividendTax(s.tax.dividends, shield: s.tax.dividendShield, in: c) + s.tax.interest * c.dividendTax
    }

    /// Monthly personal processes: overdraft interest, savings interest, loan instalments, credit score drift.
    /// Original: `personalMonth`.
    public static func monthly(_ s: inout GameState, context: FinanceContext) {
        if s.cash < 0 {
            let interest = -s.cash * 0.16 / 12
            Ledger.move(&s, .me, -interest, why: "Overdraft interest")
            s.credit = clamp(s.credit - 0.4, 0, 100)
        }
        if s.savings > 0 {
            let i = s.savings * max(0.005, s.economy.policyRate - 0.012) / 12
            s.savings += i
            s.tax.interest += i
        }
        Banking.collectMonthlyInstalments(state: &s, context: context)
        if s.cash >= 0 && Banking.totalDebt(s) > 0 { s.credit = clamp(s.credit + 0.35, 0, 100) }
        if s.loans.isEmpty { s.credit = clamp(s.credit + 0.1, 0, 100) }
        let age = Double(s.player.age) + Double(s.week) / 52
        if age > 60 { s.credit = clamp(s.credit - 0.02, 0, 100) }
    }

    /// Sole traders pay advance tax each quarter; it counts as withheld at the yearly assessment.
    /// Original: `advTaxMonth`.
    public static func advanceTaxMonthly(_ s: inout GameState, context: FinanceContext) {
        let mi = GameCalendar.monthIndex(week: s.week) % 12
        if mi % 3 != 2 { return }
        let q = Double(mi / 3)
        let enk = max(0, soleTraderIncome(s) - s.enkLoss)
        if enk <= 0 { return }
        let c = context.homeCountry(s)
        let target = 0.9 * Taxes.personalIncomeTax(enk * 4 / (q + 1), kind: .selfEmployed, in: c) * (q + 1) / 4
        let paid = s.tax.advancePaid
        let pay = jsRound(target - paid)
        if pay < 100 { return }
        s.tax.advancePaid = paid + pay
        s.tax.withheld += pay
        Payments.playerPays(&s, pay, label: "Advance tax (sole trader)")
    }

    /// The annual personal tax assessment (income, gains, dividends, interest, wealth). Original: `yearEndPersonal`.
    /// `netWorth` and `companyShareValue` (value of the player's share in companies) are supplied by the caller.
    public static func yearEnd(_ s: inout GameState, context: FinanceContext, netWorth: Double, ownedCompanyValue: Double) {
        let c = context.homeCountry(s)
        let t = s.tax
        let rawE = soleTraderIncome(s), lc0 = s.enkLoss
        let enk = max(0, rawE - lc0)
        s.enkLoss = max(0, lc0 - rawE)
        let wage = t.salary
        let income = enk + wage
        let tax1 = Taxes.personalIncomeTax(income, kind: wage > enk ? .wage : .selfEmployed, in: c)
        let withheld = t.withheld
        let gain = max(0, t.gains)
        let taxGain = gain * c.dividendTax
        let divT = Taxes.dividendTax(t.dividends, shield: t.dividendShield, in: c)
        let intT = t.interest * c.dividendTax
        let wealthBase = netWorth - ownedCompanyValue * (1 - c.wealthCompanyShare) - c.wealthThreshold
        let wealth = max(0, wealthBase) * c.wealthRate
        let due = max(-t.advancePaid, tax1 - withheld) + taxGain + divT + intT + wealth
        Payments.playerPays(&s, due, label: "Annual tax assessment (income, gains, wealth)")
        s.stats.taxPaid += due + withheld
        let cur = context.homeCurrency(s)
        s.note("Annual personal tax: \(cur.display(due))" + (withheld != 0 ? " (after \(cur.display(withheld)) withheld)" : "") + (wealth != 0 ? ", including wealth tax \(cur.display(wealth))" : "") + ".", tone: "n")
        s.tax = PersonalTaxYear(raw: ["ytd": 0, "paid": 0, "enkIncome": 0, "wage": 0, "div": 0, "ytdDiv": 0, "withheld": 0, "gain": 0, "int": 0, "shield": 0])
        s.stats.yearsPlayed += 1
    }
}

extension GameState {
    /// Losses of sole-trader businesses carried forward. Original: `S.enkLoss`.
    public var enkLoss: Double {
        get { rest["enkLoss"]?.double ?? 0 }
        set { rest["enkLoss"] = .number(newValue) }
    }
}
