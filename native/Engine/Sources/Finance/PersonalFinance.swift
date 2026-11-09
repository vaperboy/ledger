import Foundation
import GameCore
import Countries

/// The player's own money: the account's overdraft, loans and tax. The only personal income is owner salary (tax withheld on every payroll),
/// dividends, gains and deposit interest (tax paid as they arise); company profit is taxed in the company. Original: `personalMonth`, `yearEndPersonal`.
public enum PersonalFinance {
    /// Tax still to settle if the year ended now: income tax minus what was withheld or paid in advance, plus the other taxes minus what was
    /// already paid as they arose. Original: `personalTaxEstimate`.
    public static func taxEstimate(_ s: GameState, context: FinanceContext) -> Double {
        let c = context.homeCountry(s)
        let wage = s.tax.salary
        let tax1 = Taxes.personalIncomeTax(wage, kind: .wage, in: c)
        let t = s.tax
        return max(0, max(0, tax1 - t.withheld) + (Taxes.capitalGainsTax(t.gains, in: c) - t.paidGains)
            + (Taxes.dividendTax(t.dividends, shield: t.dividendShield, in: c) - t.paidDividend) + (Taxes.savingsInterestTax(t.interest, in: c) - t.paidInterest))
    }

    /// Monthly personal processes: overdraft interest, loan instalments, credit score drift.
    /// Original: `personalMonth`.
    public static func monthly(_ s: inout GameState, context: FinanceContext) {
        if s.cash < 0 {
            let home = context.homeCountry(s)
            let interest = -s.cash * Banking.overdraftRate(state: s, country: home, home: home, personal: true) / 12
            Ledger.move(&s, .me, -interest, why: "Overdraft interest")
            s.credit = clamp(s.credit - 0.4, 0, 100)
        }
        Banking.collectMonthlyInstalments(state: &s, context: context)
        if s.cash >= 0 && Banking.totalDebt(s) > 0 { s.credit = clamp(s.credit + 0.35, 0, 100) }
        if s.loans.isEmpty { s.credit = clamp(s.credit + 0.1, 0, 100) }
    }

    // MARK: Tax paid as it arises

    /// Pay what the year's dividends, gains and interest owe so far, less what was already paid: dividend tax after the shield, tax on gains,
    /// tax on interest. One statement line per tax. Never refunds mid-year (a loss or a larger shield is trued up at the year end).
    /// Called at each taxable event and as a weekly sweep for events that have no call of their own.
    public static func withholdNow(_ s: inout GameState, context: FinanceContext) {
        let c = context.homeCountry(s)
        let t = s.tax
        let dividend = withhold(&s, owed: Taxes.dividendTax(t.dividends, shield: t.dividendShield, in: c), paid: t.paidDividend, label: "Dividend tax")
        let gains = withhold(&s, owed: Taxes.capitalGainsTax(t.gains, in: c), paid: t.paidGains, label: "Tax on gains")
        let interest = withhold(&s, owed: Taxes.savingsInterestTax(t.interest, in: c), paid: t.paidInterest, label: "Tax on interest")
        s.tax.paidDividend += dividend
        s.tax.paidGains += gains
        s.tax.paidInterest += interest
    }

    /// Wealth tax is paid monthly: the share of the year's amount (on today's net worth) that the months so far call for, less what was paid.
    public static func withholdWealthTax(_ s: inout GameState, context: FinanceContext, netWorth: Double, ownedCompanyValue: Double) {
        guard context.homeCountry(s).wealthRate > 0 else { return }
        let annual = breakdown(s, context: context, netWorth: netWorth, ownedCompanyValue: ownedCompanyValue).wealthTax
        let months = Double(GameCalendar.monthIndex(week: s.week) % 12 + 1)
        let paid = withhold(&s, owed: annual * months / 12, paid: s.tax.paidWealth, label: "Wealth tax")
        s.tax.paidWealth += paid
    }

    /// Pay `owed - paid` from the account. Returns what was paid (rounded), 0 when nothing is due.
    private static func withhold(_ s: inout GameState, owed: Double, paid: Double, label: String) -> Double {
        let pay = jsRound(owed - paid)
        guard pay > 0 else { return 0 }
        Payments.playerPays(&s, pay, label: label)
        s.stats.taxPaid += pay
        return pay
    }

    // MARK: Full assessment

    /// Every part of the personal tax bill, for the estimate during the year and for the assessment at its end.
    public struct TaxBreakdown: Equatable, Sendable {
        public var week = 0
        /// Taxable income: owner salary.
        public var taxableIncome = 0.0
        /// Income tax before what was withheld.
        public var incomeTax = 0.0
        public var withheld = 0.0
        /// Income tax still to pay (negative: tax withheld on salary comes back).
        public var incomeDue = 0.0
        public var dividends = 0.0
        public var shield = 0.0
        public var dividendTax = 0.0
        public var gainsTax = 0.0
        public var interestTax = 0.0
        public var wealthTax = 0.0
        /// Dividend, gains, interest and wealth tax already paid this year as they arose.
        public var paidDividend = 0.0
        public var paidGains = 0.0
        public var paidInterest = 0.0
        public var paidWealth = 0.0
        /// The whole year's tax if it ended now, before anything was paid.
        public var annual: Double { incomeTax + dividendTax + gainsTax + interestTax + wealthTax }
        /// Paid so far: income tax withheld or paid in advance, and the other taxes paid as they arose.
        public var paidSoFar: Double { withheld + paidDividend + paidGains + paidInterest + paidWealth }
        /// Still to settle (the year-end true-up): the annual tax less what was paid; negative means a refund.
        public var total: Double { incomeDue + (dividendTax - paidDividend) + (gainsTax - paidGains) + (interestTax - paidInterest) + (wealthTax - paidWealth) }

        public init() {}

        /// The stored form: income = income tax before withholding, so income - withheld + the rest = total.
        public var json: JSONValue {
            .object(["week": .number(Double(week)), "income": .number(incomeTax), "dividend": .number(dividendTax), "gains": .number(gainsTax),
                     "interest": .number(interestTax), "wealth": .number(wealthTax), "withheld": .number(withheld), "total": .number(total),
                     "due": .number(incomeDue), "taxable": .number(taxableIncome), "dividends": .number(dividends), "shield": .number(shield),
                     "pDiv": .number(paidDividend), "pGain": .number(paidGains), "pInt": .number(paidInterest), "pWealth": .number(paidWealth)])
        }
        public init?(json j: JSONValue?) {
            guard let j, !j.isNull else { return nil }
            week = j["week"].int; incomeTax = j["income"].double; dividendTax = j["dividend"].double; gainsTax = j["gains"].double
            interestTax = j["interest"].double; wealthTax = j["wealth"].double; withheld = j["withheld"].double; incomeDue = j["due"].double
            taxableIncome = j["taxable"].double; dividends = j["dividends"].double; shield = j["shield"].double
            paidDividend = j["pDiv"].double; paidGains = j["pGain"].double; paidInterest = j["pInt"].double; paidWealth = j["pWealth"].double
        }
    }

    /// The bill if the year ended now. `netWorth` and `ownedCompanyValue` (the player's share of companies) come from the caller.
    public static func breakdown(_ s: GameState, context: FinanceContext, netWorth: Double, ownedCompanyValue: Double) -> TaxBreakdown {
        let c = context.homeCountry(s)
        let t = s.tax
        let wage = t.salary
        var b = TaxBreakdown()
        b.week = s.week
        b.taxableIncome = wage
        b.incomeTax = Taxes.personalIncomeTax(wage, kind: .wage, in: c)
        b.withheld = t.withheld
        b.incomeDue = b.incomeTax - t.withheld
        b.dividends = t.dividends
        b.shield = t.dividendShield
        b.dividendTax = Taxes.dividendTax(t.dividends, shield: t.dividendShield, in: c)
        b.gainsTax = Taxes.capitalGainsTax(t.gains, in: c)
        b.interestTax = Taxes.savingsInterestTax(t.interest, in: c)
        let wealthBase = netWorth - ownedCompanyValue * (1 - c.wealthCompanyShare) - c.wealthThreshold
        b.wealthTax = max(0, wealthBase) * c.wealthRate
        b.paidDividend = t.paidDividend; b.paidGains = t.paidGains; b.paidInterest = t.paidInterest; b.paidWealth = t.paidWealth
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

    /// The year-end true-up of personal tax (income, gains, dividends, interest, wealth). Original: `yearEndPersonal`.
    /// Dividend, gains, interest and wealth tax were paid as they arose and salary tax withheld, so only the difference between
    /// the correct annual total and what was paid is settled here: a small bill or a refund, one statement line per part. What the overdraft
    /// cannot comfortably carry stays owed as `tax.pending` and the player is asked how to settle it. `netWorth` and `ownedCompanyValue`
    /// (the player's share in companies) are supplied by the caller.
    public static func yearEnd(_ s: inout GameState, context: FinanceContext, netWorth: Double, ownedCompanyValue: Double) {
        let b = breakdown(s, context: context, netWorth: netWorth, ownedCompanyValue: ownedCompanyValue)
        let carried = s.tax.pending
        let total = b.total
        let cur = context.homeCurrency(s)
        let room = max(0, s.overdraftLimit + min(0, s.cash))
        let short = max(0, total - max(0, s.cash))
        let deferred = max(0, short - room * overdraftShare)
        let lines: [(name: String, amount: Double, early: Double)] = [
            ("income tax", b.incomeDue, 0), ("dividend tax", b.dividendTax - b.paidDividend, b.paidDividend), ("tax on gains", b.gainsTax - b.paidGains, b.paidGains),
            ("tax on interest", b.interestTax - b.paidInterest, b.paidInterest), ("wealth tax", b.wealthTax - b.paidWealth, b.paidWealth)]
        var budget = max(0, lines.reduce(0) { $0 + max(0, $1.amount) } - deferred)
        // Each line is rounded on the running total, so the lines add up to the rounded bill.
        var paid = 0.0, booked = 0.0
        for l in lines where l.amount != 0 {
            let part = l.amount < 0 ? l.amount : min(l.amount, budget)
            if part == 0 { continue }
            if part > 0 { budget -= part }
            paid += part
            let line = jsRound(paid) - booked
            booked += line
            if line != 0 { Payments.playerPays(&s, line, label: (l.early > 0 ? "Annual tax true-up: " : "Annual tax: ") + l.name) }
        }
        s.stats.taxPaid += paid + b.withheld
        s.rest["taxLast"] = b.json
        s.note(assessmentNote(annual: b.annual, paidEarlier: b.paidSoFar, due: total, income: b.taxableIncome, incomeTax: b.incomeTax, withheld: b.withheld, gains: b.gainsTax,
                              dividends: b.dividends, shield: b.shield, dividendTax: b.dividendTax, interest: b.interestTax, wealth: b.wealthTax, currency: cur), tone: "n")
        s.tax = PersonalTaxYear(raw: ["wage": 0, "ytdDiv": 0, "withheld": 0, "gain": 0, "int": 0, "shield": 0])
        s.stats.yearsPlayed += 1
        if deferred + carried > 0 { askHowToPay(&s, owed: deferred + carried, currency: cur) }
    }

    /// The accounts cannot carry the bill: record what is owed and ask the player how to settle it before the bank acts.
    static func askHowToPay(_ s: inout GameState, owed: Double, currency cur: Currency) {
        s.tax.pending = owed
        s.addMessage(kind: "ask", from: "Tax office", title: "Tax bill of \(cur.display(owed)) is more than your accounts hold",
                     body: "Your account did not cover the year's personal tax, and \(cur.display(owed)) is still owed. Choose how to settle it within \(decisionWeeks) weeks. "
                         + "Otherwise it is taken from your account and the bank's overdraft rules apply.",
                     tone: "bad", status: "open",
                     options: [.option("Sell investments", "Funds, shares and crypto are sold for as much as it takes. The tax on the gains is paid at once."),
                               .option("Loan against your companies", "A bank loan secured on your share of the companies you own, over 5 years."),
                               .option("Payment plan", "The tax office lets you pay in 12 monthly instalments, with interest."),
                               .option("Take it from the account", "The balance is charged now and the account may go overdrawn.")],
                     action: dueAction, data: .object(["owed": .number(owed)]), expiresWeek: s.week + decisionWeeks)
    }

    /// The tax office takes what is still owed from the account: the player refused or did not answer.
    public static func collectDeferred(_ s: inout GameState, context: FinanceContext) {
        let owed = s.tax.pending
        guard owed > 0 else { return }
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

    /// The year-end message: the year's total, what was paid as it arose, the balance settled now, then every part, so the player sees what made it up.
    static func assessmentNote(annual: Double, paidEarlier: Double, due: Double, income: Double, incomeTax: Double, withheld: Double, gains: Double, dividends: Double, shield: Double,
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
        let settle = due < 0 ? "refund of \(cur.display(-due))" : "balance of \(cur.display(due))"
        return "Personal tax for the year: \(cur.display(annual)), of which \(cur.display(paidEarlier)) was paid as it arose, so a \(settle) is settled now"
            + (parts.isEmpty ? "" : ". " + parts.joined(separator: ", ")) + "."
    }
}
