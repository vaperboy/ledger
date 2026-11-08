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
        return max(0, tax1 - s.tax.withheld) + Taxes.capitalGainsTax(s.tax.gains, in: c)
            + Taxes.dividendTax(s.tax.dividends, shield: s.tax.dividendShield, in: c) + Taxes.savingsInterestTax(s.tax.interest, in: c)
    }

    /// Yearly interest the savings account pays: the policy rate less a margin, never below 0.5%.
    public static func savingsRate(_ s: GameState) -> Double { max(0.005, s.economy.policyRate - 0.012) }

    /// Monthly personal processes: overdraft interest, savings interest, loan instalments, credit score drift.
    /// Original: `personalMonth`.
    public static func monthly(_ s: inout GameState, context: FinanceContext) {
        if s.cash < 0 {
            let home = context.homeCountry(s)
            let interest = -s.cash * Banking.overdraftRate(state: s, country: home, home: home, personal: true) / 12
            Ledger.move(&s, .me, -interest, why: "Overdraft interest")
            s.credit = clamp(s.credit - 0.4, 0, 100)
        }
        if s.savings > 0 {
            let i = s.savings * savingsRate(s) / 12
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

    // MARK: Full assessment

    /// Every part of the personal tax bill, for the estimate during the year and for the assessment at its end.
    public struct TaxBreakdown: Equatable, Sendable {
        public var week = 0
        /// Taxable income: sole-trader profit after carried losses, plus wages.
        public var taxableIncome = 0.0
        /// Income tax before what was withheld.
        public var incomeTax = 0.0
        public var withheld = 0.0
        /// Income tax still to pay (negative: advance payments come back).
        public var incomeDue = 0.0
        public var dividends = 0.0
        public var shield = 0.0
        public var dividendTax = 0.0
        public var gainsTax = 0.0
        public var interestTax = 0.0
        public var wealthTax = 0.0
        public var total: Double { incomeDue + dividendTax + gainsTax + interestTax + wealthTax }

        public init() {}

        /// The stored form: income = income tax before withholding, so income - withheld + the rest = total.
        public var json: JSONValue {
            .object(["week": .number(Double(week)), "income": .number(incomeTax), "dividend": .number(dividendTax), "gains": .number(gainsTax),
                     "interest": .number(interestTax), "wealth": .number(wealthTax), "withheld": .number(withheld), "total": .number(total),
                     "due": .number(incomeDue), "taxable": .number(taxableIncome), "dividends": .number(dividends), "shield": .number(shield)])
        }
        public init?(json j: JSONValue?) {
            guard let j, !j.isNull else { return nil }
            week = j["week"].int; incomeTax = j["income"].double; dividendTax = j["dividend"].double; gainsTax = j["gains"].double
            interestTax = j["interest"].double; wealthTax = j["wealth"].double; withheld = j["withheld"].double; incomeDue = j["due"].double
            taxableIncome = j["taxable"].double; dividends = j["dividends"].double; shield = j["shield"].double
        }
    }

    /// The bill if the year ended now. `netWorth` and `ownedCompanyValue` (the player's share of companies) come from the caller.
    public static func breakdown(_ s: GameState, context: FinanceContext, netWorth: Double, ownedCompanyValue: Double) -> TaxBreakdown {
        let c = context.homeCountry(s)
        let t = s.tax
        let enk = max(0, soleTraderIncome(s) - s.enkLoss)
        let wage = t.salary
        var b = TaxBreakdown()
        b.week = s.week
        b.taxableIncome = enk + wage
        b.incomeTax = Taxes.personalIncomeTax(enk + wage, kind: wage > enk ? .wage : .selfEmployed, in: c)
        b.withheld = t.withheld
        b.incomeDue = max(-t.advancePaid, b.incomeTax - t.withheld)
        b.dividends = t.dividends
        b.shield = t.dividendShield
        b.dividendTax = Taxes.dividendTax(t.dividends, shield: t.dividendShield, in: c)
        b.gainsTax = Taxes.capitalGainsTax(t.gains, in: c)
        b.interestTax = Taxes.savingsInterestTax(t.interest, in: c)
        let wealthBase = netWorth - ownedCompanyValue * (1 - c.wealthCompanyShare) - c.wealthThreshold
        b.wealthTax = max(0, wealthBase) * c.wealthRate
        return b
    }

    /// The monthly estimate stored by `Failure.checkOver`, if one has been made.
    public static func storedEstimate(_ s: GameState) -> TaxBreakdown? { TaxBreakdown(json: s.rest["taxEst"]) }
    /// The last year-end assessment.
    public static func lastAssessment(_ s: GameState) -> TaxBreakdown? { TaxBreakdown(json: s.rest["taxLast"]) }

    /// Weeks left in the calendar year (0 in its last week).
    public static func weeksToYearEnd(week: Int) -> Int {
        var n = 0
        while n < 54, !GameCalendar.isYearEnd(week: week + n) { n += 1 }
        return n
    }

    /// Message action of the decision raised when the bill is more than the accounts can carry.
    public static let dueAction = "taxdue"
    /// Weeks the player has to answer before the tax office collects from the account.
    static let decisionWeeks = 4
    /// Share of the free overdraft room a tax bill may use before the player is asked how to pay.
    static let overdraftShare = 0.4

    /// The annual personal tax assessment (income, gains, dividends, interest, wealth). Original: `yearEndPersonal`.
    /// Paid from cash, then savings, one statement line per part. What the overdraft cannot comfortably carry stays owed as `tax.pending`
    /// and the player is asked how to settle it. `netWorth` and `ownedCompanyValue` (the player's share in companies) are supplied by the caller.
    public static func yearEnd(_ s: inout GameState, context: FinanceContext, netWorth: Double, ownedCompanyValue: Double) {
        let rawE = soleTraderIncome(s), lc0 = s.enkLoss
        let b = breakdown(s, context: context, netWorth: netWorth, ownedCompanyValue: ownedCompanyValue)
        s.enkLoss = max(0, lc0 - rawE)
        let carried = s.tax.pending
        let total = b.total
        let cur = context.homeCurrency(s)
        let room = max(0, s.overdraftLimit + min(0, s.cash))
        let short = max(0, total - max(0, s.cash) - max(0, s.savings))
        let deferred = max(0, short - room * overdraftShare)
        var payable = total - deferred
        if payable > 0 { Payments.transferFromSavings(&s, need: payable) }
        let lines: [(String, Double)] = [("income tax", b.incomeDue), ("dividend tax", b.dividendTax), ("tax on gains", b.gainsTax),
                                         ("tax on interest", b.interestTax), ("wealth tax", b.wealthTax)]
        // Each line is rounded on the running total, so the lines add up to the rounded bill.
        var paid = 0.0, booked = 0.0
        for (name, amount) in lines where amount != 0 {
            let part = amount < 0 ? amount : min(amount, max(0, payable))
            if part == 0 { continue }
            payable -= part
            paid += part
            let line = jsRound(paid) - booked
            booked += line
            if line != 0 { Payments.playerPays(&s, line, label: "Annual tax: \(name)") }
        }
        s.stats.taxPaid += paid + b.withheld
        s.rest["taxLast"] = b.json
        s.note(assessmentNote(due: total, income: b.taxableIncome, incomeTax: b.incomeTax, withheld: b.withheld, gains: b.gainsTax, dividends: b.dividends, shield: b.shield,
                              dividendTax: b.dividendTax, interest: b.interestTax, wealth: b.wealthTax, currency: cur), tone: "n")
        s.tax = PersonalTaxYear(raw: ["ytd": 0, "paid": 0, "enkIncome": 0, "wage": 0, "div": 0, "ytdDiv": 0, "withheld": 0, "gain": 0, "int": 0, "shield": 0])
        s.stats.yearsPlayed += 1
        if deferred + carried > 0 { askHowToPay(&s, owed: deferred + carried, currency: cur) }
    }

    /// The accounts cannot carry the bill: record what is owed and ask the player how to settle it before the bank acts.
    static func askHowToPay(_ s: inout GameState, owed: Double, currency cur: Currency) {
        s.tax.pending = owed
        s.addMessage(kind: "ask", from: "Tax office", title: "Tax bill of \(cur.display(owed)) is more than your accounts hold",
                     body: "Your cash and savings did not cover the year's personal tax, and \(cur.display(owed)) is still owed. Choose how to settle it within \(decisionWeeks) weeks. "
                         + "Otherwise it is taken from your account and the bank's overdraft rules apply.",
                     tone: "bad", status: "open",
                     options: [.option("Sell investments", "Funds, shares and crypto are sold for as much as it takes. Gains are taxed next year."),
                               .option("Loan against your companies", "A bank loan secured on your share of the companies you own, over 5 years."),
                               .option("Payment plan", "The tax office lets you pay in 12 monthly instalments, with interest."),
                               .option("Take it from the account", "The balance is charged now and the account may go overdrawn.")],
                     action: dueAction, data: .object(["owed": .number(owed)]), expiresWeek: s.week + decisionWeeks)
    }

    /// The tax office takes what is still owed from the account: the player refused or did not answer.
    public static func collectDeferred(_ s: inout GameState, context: FinanceContext) {
        let owed = s.tax.pending
        guard owed > 0 else { return }
        Payments.transferFromSavings(&s, need: owed)
        Payments.playerPays(&s, owed, label: "Annual tax: balance collected")
        s.stats.taxPaid += owed
        s.tax.pending = 0
        s.note("The tax office collected the unpaid \(context.homeCurrency(s).display(owed)) from your account.", tone: "bad")
    }

    /// An overdraft line that grows with wealth and the credit score, never below the starting line `base`.
    public static func creditLine(_ s: GameState, base: Double, netWorth: Double) -> Double {
        let f: Double = s.credit >= 80 ? 0.05 : s.credit >= 65 ? 0.04 : s.credit >= 50 ? 0.025 : s.credit >= 35 ? 0.01 : 0
        return max(base, jsRound(max(0, netWorth) * f))
    }

    /// The year-end message: the total, then every part that was charged, so the player sees what made it up.
    static func assessmentNote(due: Double, income: Double, incomeTax: Double, withheld: Double, gains: Double, dividends: Double, shield: Double,
                               dividendTax: Double, interest: Double, wealth: Double, currency cur: Currency) -> String {
        var parts: [String] = []
        if incomeTax > 0 || withheld > 0 {
            parts.append("income tax \(cur.display(incomeTax)) on \(cur.display(income))" + (withheld != 0 ? " (\(cur.display(withheld)) already withheld)" : ""))
        }
        if dividendTax > 0 {
            parts.append("dividend tax \(cur.display(dividendTax)) on \(cur.display(dividends))" + (shield > 0 ? " (\(cur.display(shield)) tax-free)" : ""))
        }
        if gains > 0 { parts.append("tax on gains \(cur.display(gains))") }
        if interest > 0 { parts.append("tax on interest \(cur.display(interest))") }
        if wealth > 0 { parts.append("wealth tax \(cur.display(wealth))") }
        return "Annual personal tax: \(cur.display(due))" + (parts.isEmpty ? "" : ". " + parts.joined(separator: ", ")) + "."
    }
}

extension GameState {
    /// Losses of sole-trader businesses carried forward. Original: `S.enkLoss`.
    public var enkLoss: Double {
        get { rest["enkLoss"]?.double ?? 0 }
        set { rest["enkLoss"] = .number(newValue) }
    }
}
