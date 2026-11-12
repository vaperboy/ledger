import Foundation
import GameCore
import Countries

public enum PersonalFinance {
    public static func taxEstimate(_ s: GameState, context: FinanceContext) -> Double {
        let c = context.homeCountry(s)
        let wage = s.tax.salary
        let tax1 = Taxes.personalIncomeTax(wage, in: c)
        let t = s.tax
        return max(0, max(0, tax1 - t.withheld) + (Taxes.capitalGainsTax(t.gains, in: c) - t.paidGains)
            + (Taxes.dividendTax(t.dividends, shield: t.dividendShield, in: c) - t.paidDividend) + (Taxes.savingsInterestTax(t.interest, in: c) - t.paidInterest))
    }

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

    public static func withholdWealthTax(_ s: inout GameState, context: FinanceContext, netWorth: Double, ownedCompanyValue: Double) {
        guard context.homeCountry(s).wealthRate > 0 else { return }
        let annual = breakdown(s, context: context, netWorth: netWorth, ownedCompanyValue: ownedCompanyValue).wealthTax
        let months = Double(GameCalendar.monthIndex(week: s.week) % 12 + 1)
        let paid = withhold(&s, owed: annual * months / 12, paid: s.tax.paidWealth, label: "Wealth tax")
        s.tax.paidWealth += paid
    }

    private static func withhold(_ s: inout GameState, owed: Double, paid: Double, label: String) -> Double {
        let pay = jsRound(owed - paid)
        guard pay > 0 else { return 0 }
        Payments.playerPays(&s, pay, label: label)
        s.stats.taxPaid += pay
        return pay
    }

    public struct TaxBreakdown: Equatable, Sendable {
        public var week = 0
        public var taxableIncome = 0.0
        public var incomeTax = 0.0
        public var withheld = 0.0
        public var incomeDue = 0.0
        public var dividends = 0.0
        public var shield = 0.0
        public var dividendTax = 0.0
        public var gainsTax = 0.0
        public var interestTax = 0.0
        public var wealthTax = 0.0
        public var paidDividend = 0.0
        public var paidGains = 0.0
        public var paidInterest = 0.0
        public var paidWealth = 0.0
        public var annual: Double { incomeTax + dividendTax + gainsTax + interestTax + wealthTax }
        public var paidSoFar: Double { withheld + paidDividend + paidGains + paidInterest + paidWealth }
        public var total: Double { incomeDue + (dividendTax - paidDividend) + (gainsTax - paidGains) + (interestTax - paidInterest) + (wealthTax - paidWealth) }

        public init() {}

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

    public static func breakdown(_ s: GameState, context: FinanceContext, netWorth: Double, ownedCompanyValue: Double) -> TaxBreakdown {
        let c = context.homeCountry(s)
        let t = s.tax
        let wage = t.salary
        var b = TaxBreakdown()
        b.week = s.week
        b.taxableIncome = wage
        b.incomeTax = Taxes.personalIncomeTax(wage, in: c)
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

    public static func storedEstimate(_ s: GameState) -> TaxBreakdown? { TaxBreakdown(json: s.rest["taxEst"]) }
    public static func lastAssessment(_ s: GameState) -> TaxBreakdown? { TaxBreakdown(json: s.rest["taxLast"]) }

    public static func weeksToYearEnd(week: Int) -> Int {
        var n = 0
        while n < 54, !GameCalendar.isYearEnd(week: week + n) { n += 1 }
        return n
    }

    public static let dueAction = "taxdue"
    static let decisionWeeks = 4
    static let overdraftShare = 0.4

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

    public static func collectDeferred(_ s: inout GameState, context: FinanceContext) {
        let owed = s.tax.pending
        guard owed > 0 else { return }
        Payments.playerPays(&s, owed, label: "Annual tax: balance collected")
        s.stats.taxPaid += owed
        s.tax.pending = 0
        s.note("The tax office collected the unpaid \(context.homeCurrency(s).display(owed)) from your account.", tone: "bad")
    }

    public static func creditLine(_ s: GameState, base: Double, netWorth: Double) -> Double {
        let f: Double = s.credit >= 80 ? 0.05 : s.credit >= 65 ? 0.04 : s.credit >= 50 ? 0.025 : s.credit >= 35 ? 0.01 : 0
        return max(base, jsRound(max(0, netWorth) * f))
    }

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
