import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Investments

/// Personal tax around the year-end true-up: the monthly estimate of what is still to settle with its warning, monthly wealth tax,
/// the overdraft line that grows with wealth, and the player's answer when the true-up is more than the accounts hold.
public enum TaxSettlement {
    /// Weeks before year end from which a bill larger than liquid funds is warned about.
    static let warnWeeks = 13
    /// Weeks between estimate refreshes (about a month).
    static let refreshWeeks = 4

    /// The player's share of what their companies are worth.
    static func ownedCompanyValue(_ s: GameState, data: GameData) -> Double {
        s.companies.filter { $0.status != .sold }.reduce(0) { $0 + Valuation.companyValue($1, state: s, trades: data.catalog) * $1.ownership / 100 }
    }

    /// Pay this month's wealth tax (one twelfth of the year's amount, caught up for the months so far).
    static func withholdWealthTax(_ s: inout GameState, data: GameData, context: FinanceContext) {
        guard context.homeCountry(s).wealthRate > 0 else { return }
        let nw = Valuation.netWorth(s, trades: data.catalog).total
        PersonalFinance.withholdWealthTax(&s, context: context, netWorth: nw, ownedCompanyValue: ownedCompanyValue(s, data: data))
    }

    /// Refresh the stored estimate (`rest["taxEst"]`) and the overdraft line about monthly; warn once a year when the coming true-up
    /// (tax still to settle after what was paid as it arose) is more than cash plus savings.
    static func refresh(_ s: inout GameState, data: GameData, context: FinanceContext) {
        if let last = s.rest["taxEst"], !last.isNull, s.week - last["week"].int < refreshWeeks, s.week >= last["week"].int { return }
        let nw = Valuation.netWorth(s, trades: data.catalog).total
        let owned = ownedCompanyValue(s, data: data)
        let b = PersonalFinance.breakdown(s, context: context, netWorth: nw, ownedCompanyValue: owned)
        s.rest["taxEst"] = b.json

        let base = context.homeCurrency(s).scaledPrice(25000)
        var line = PersonalFinance.creditLine(s, base: base, netWorth: nw)
        if line < s.overdraftLimit { line = max(line, min(s.overdraftLimit, -s.cash)) }   // the bank does not pull a line that is in use
        s.overdraftLimit = line

        let year = GameCalendar.year(week: s.week)
        let liquid = max(0, s.cash) + max(0, s.savings)
        guard b.total > liquid, PersonalFinance.weeksToYearEnd(week: s.week) <= warnWeeks, s.rest["taxWarn"]?.int != year else { return }
        s.rest["taxWarn"] = .number(Double(year))
        let cur = context.homeCurrency(s)
        s.addMessage(from: "Tax office", title: "Your year-end tax settlement may be more than your cash",
                     body: "About \(cur.display(b.total)) of personal tax is still to settle at year end, and cash plus savings come to \(cur.display(liquid)). "
                         + "Take dividends or a salary, sell investments or arrange a loan before then.",
                     tone: "bad", sev: 2)
    }

    /// The end-of-week hook: a decision nobody answered in time is collected from the account.
    static func collectIfRefused(_ s: inout GameState, context: FinanceContext) {
        guard s.tax.pending > 0 else { return }
        if s.inbox.contains(where: { $0.status == "open" && $0.actionID == PersonalFinance.dueAction }) { return }
        PersonalFinance.collectDeferred(&s, context: context)
    }

    /// The answer to the "tax bill too large" decision. False leaves it open (nothing was sold or borrowed).
    @discardableResult
    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData, context: FinanceContext) -> Bool {
        let owed = s.tax.pending
        guard owed > 0 else { return true }
        let cur = context.homeCurrency(s)
        let need = max(0, owed - max(0, s.cash))
        switch idx {
        case 0:
            let holdings = marketHoldings(s)
            let worth = holdings.reduce(0) { $0 + $1.value }
            guard worth >= need * 1.02 else {
                s.note("Your investments are worth \(cur.display(worth)), not enough for the \(cur.display(owed)) owed. Choose another way.", tone: "bad")
                return false
            }
            var left = need * 1.02
            for h in holdings where left > 0 {
                let f = min(1, left / max(1, h.value))
                Brokerage.sell(&s, h.kind, h.symbol, fraction: f, currency: cur)
                left -= h.value * f
            }
            PersonalFinance.withholdNow(&s, context: context)   // the tax on the gains of these sales is paid at once
            Payments.transferFromSavings(&s, need: owed)
            Payments.playerPays(&s, owed, label: "Annual tax: balance paid from investments")
        case 1:
            let nw = Valuation.netWorth(s, trades: data.catalog).total
            let collateral = ownedCompanyValue(s, data: data) * 0.5
            let off = Banking.offer(kind: "lomb", amount: need, company: nil, state: s, netWorth: nw, collateral: collateral, context: context)
            let amount = need.rounded(.up)
            guard amount <= off.maximum else {
                s.note("The bank would lend \(cur.display(off.maximum)) against your companies, less than the \(cur.display(amount)) needed. Choose another way.", tone: "bad")
                return false
            }
            if amount > 0 {
                guard case .ok(let loan) = Banking.take(kind: "lomb", amount: max(amount, cur.scaledPrice(5000)), termMonths: 60, company: nil, state: &s, netWorth: nw,
                                                        collateral: collateral, context: context) else {
                    s.note("The bank declined the loan. Choose another way.", tone: "bad")
                    return false
                }
                if let li = s.loans.firstIndex(where: { $0.id == loan.id }) { s.loans[li].name = "Tax loan (secured on your companies)" }
            }
            Payments.transferFromSavings(&s, need: owed)
            Payments.playerPays(&s, owed, label: "Annual tax: balance paid with a bank loan")
        case 2:
            var plan = Loan(raw: [:])
            plan.id = s.makeID()
            plan.kind = "cons"
            plan.name = "Tax payment plan"
            plan.balance = owed
            plan.originalAmount = owed
            plan.margin = planMargin
            plan.termMonths = planMonths
            plan.companyID = 0
            plan.startWeek = s.week
            plan.monthlyPayment = Loans.annuity(principal: owed, yearlyRate: s.economy.policyRate + planMargin, months: Double(planMonths))
            s.loans.append(plan)
            s.note("The tax office agreed a payment plan: \(cur.display(plan.monthlyPayment)) a month for \(planMonths) months.", tone: "n")
        default:
            PersonalFinance.collectDeferred(&s, context: context)
            return true
        }
        s.stats.taxPaid += owed
        s.tax.pending = 0
        return true
    }

    /// The tax office's interest on an instalment arrangement, over the policy rate.
    static let planMargin = 0.02
    static let planMonths = 12

    struct Holding { var kind: Brokerage.Kind; var symbol: String; var value: Double }

    /// Funds, shares and crypto the player holds, in the order they would be sold.
    static func marketHoldings(_ s: GameState) -> [Holding] {
        var out: [Holding] = []
        let kinds: [(Brokerage.Kind, String)] = [(.fund, "funds"), (.stock, "stocks"), (.crypto, "crypto")]
        for (kind, key) in kinds {
            for sym in (s.rest["inv"]?[key].object.keys.sorted() ?? []) {
                let v = Brokerage.positionValue(s, kind, sym)
                if v > 0 { out.append(Holding(kind: kind, symbol: sym, value: v)) }
            }
        }
        return out
    }
}

public extension GameEngine {
    /// What the year's personal tax would be now (`annual`, `paidSoFar`, and `total` still to settle): the monthly stored estimate, or one worked out on the spot before the first refresh.
    func taxEstimate() -> PersonalFinance.TaxBreakdown {
        if let b = PersonalFinance.storedEstimate(state) { return b }
        let nw = Valuation.netWorth(state, trades: data.catalog).total
        return PersonalFinance.breakdown(state, context: context, netWorth: nw, ownedCompanyValue: TaxSettlement.ownedCompanyValue(state, data: data))
    }

    /// The last year-end assessment, nil before the first.
    func lastTaxAssessment() -> PersonalFinance.TaxBreakdown? { PersonalFinance.lastAssessment(state) }
}
