import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Investments

/// Read-only figures for the money and projects screens: what a loan would cost over a chosen term, what a fixed deposit pays,
/// how long a running loan still has to go, and what each way of buying a rival needs in cash. Nothing here changes the game; every
/// figure repeats the rule of the action it describes (`Banking.take`, `Brokerage.openDeposit`, `Rivals.acquire`, `RivalAbsorb`), and the
/// tests in `MoneyProjectsReadModelTests` check each against the real action.
public struct LoanQuote: Equatable, Sendable {
    public var amount: Double
    public var termMonths: Int
    /// What the bank would lend at most.
    public var maximum: Double
    public var yearlyRate: Double
    public var monthlyPayment: Double
    public var totalInterest: Double
    public var totalRepaid: Double
    public var creditBand: String
    /// Funded by your own bank.
    public var fromOwnBank: Bool
    /// Below the bank's smallest loan.
    public var tooSmall: Bool
    public var withinLimit: Bool { amount <= maximum }
}

public struct DepositQuote: Equatable, Sendable {
    public var weeks: Int
    public var yearlyRate: Double
    public var interest: Double
}

public struct LoanPayoff: Equatable, Sendable {
    /// Instalments still to pay at the current monthly payment (nil when the payment does not cover the interest).
    public var monthsLeft: Int?
    /// Interest still to pay at today's rate if the loan runs to the end.
    public var interestLeft: Double
    public var yearlyRate: Double
}

/// What buying a rival at an agreed price needs, for each thing it can become.
public struct AcquisitionPlan: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case own, branch, merge, shut, franchiseOldOwner, franchiseNewOwner, ownBank }
    public struct Choice: Identifiable, Equatable, Sendable {
        public var id: String { kind.rawValue }
        public var kind: Kind
        /// Cash you must have for the purchase to go through (for the franchise office with a new franchisee: the most it can need).
        public var cashNeeded: Double
        /// Money that the purchase moves on top of the price: set-up money for a new company, the merge or closing costs.
        public var extraCost: Double
        /// A loan from your own bank that pays part of it.
        public var loan: Double
        public var loanMonthly: Double
        public var loanRate: Double
        public var affordable: Bool
    }
    public var price: Double
    /// The new company's own start-up money (own company, branch).
    public var startupMoney: Double
    /// The reserve a bank wants you to keep after buying a business as its own company.
    public var reserve: Double
    /// What you have: cash plus savings (own company, branch, own bank) or the current account (merge, close, franchise).
    public var liquid: Double
    public var cash: Double
    /// The rival is in money trouble: unpaid bills may surface after the purchase.
    public var hiddenBillRisk: Bool
    public var choices: [Choice]
}

public extension GameEngine {
    /// The loan terms a screen offers.
    static let loanTermChoices = [12, 24, 36, 60, 84, 120]
    /// The fixed-deposit locks a screen offers.
    static let depositTermChoices = [13, 26, 52]

    /// What a loan of `amount` over `termMonths` would cost: the rate the bank offers today, the instalment, the interest over the whole term.
    func loanQuote(kind: String, amount: Double, termMonths: Int, companyID: Int?) -> LoanQuote {
        let off = loanOffer(kind: kind, amount: amount, companyID: companyID)
        let co = companyID.flatMap { state.company($0) }
        let rate = state.economy.policyRate + Banking.countryRateShift(companyID: co?.id ?? 0, state: state, context: context) + off.margin
        let months = max(1, termMonths)
        let monthly = amount > 0 ? Loans.annuity(principal: amount, yearlyRate: rate, months: Double(months)) : 0
        let total = monthly * Double(months)
        let cur = context.currency(co?.countryCode ?? state.homeCountryCode, state)
        return LoanQuote(amount: amount, termMonths: months, maximum: off.maximum, yearlyRate: rate, monthlyPayment: monthly,
                         totalInterest: max(0, total - amount), totalRepaid: total, creditBand: off.creditBand, fromOwnBank: off.ownBankID != 0,
                         tooSmall: amount < cur.scaledPrice(5000))
    }

    /// What a fixed deposit locked for `weeks` pays at maturity.
    func depositQuote(amount: Double, weeks: Int) -> DepositQuote {
        let rate = max(0.01, state.economy.policyRate - 0.002 + Double(weeks) / 52 * 0.004)
        return DepositQuote(weeks: weeks, yearlyRate: rate, interest: max(0, amount) * rate * Double(weeks) / 52)
    }

    /// How long a running loan still has to go at its current instalment, and the interest still to pay.
    func loanPayoff(loanID: Int) -> LoanPayoff? {
        guard let l = state.loans.first(where: { $0.id == loanID }) else { return nil }
        let rate = Banking.rate(of: l, state: state, countryShift: Banking.countryRateShift(companyID: l.companyID, state: state, context: context))
        let i = rate / 12, b = l.balance, p = l.monthlyPayment
        guard b > 0, p > 0 else { return LoanPayoff(monthsLeft: b > 0 ? nil : 0, interestLeft: 0, yearlyRate: rate) }
        let n: Double
        if i <= 0 { n = b / p }
        else {
            let x = 1 - b * i / p
            guard x > 0 else { return LoanPayoff(monthsLeft: nil, interestLeft: 0, yearlyRate: rate) }
            n = -log(x) / log(1 + i)
        }
        let months = Int((n - 0.01).rounded(.up))
        return LoanPayoff(monthsLeft: months, interestLeft: max(0, p * n - b), yearlyRate: rate)
    }

    /// What buying `rivalID` at `price` needs, for each thing it can become. The checks are those of `Rivals.acquire`,
    /// `RivalAbsorb.absorb` and `RivalAbsorb.buyWithOwnBank`.
    func acquisitionPlan(companyID: Int, rivalID: Int, price: Double) -> AcquisitionPlan? {
        guard let co = state.company(companyID), let r = Rivals.rivals(state, for: co).first(where: { $0.id == rivalID }) else { return nil }
        let cur = currency(for: co)
        let startup = Rivals.startupMoney(state, co, rival: r, data: data)
        let reserve = cur.scaledPrice(200000)
        let liquid = Payments.liquid(state), cash = state.cash
        let group = RivalGroups.group(state, id: r.groupID)
        let troubled = r.groupID != nil ? (group?.inTrouble ?? false)
            : (state.rest["mk"]?[Rivals.key(co)]["riv"].array.first { $0["id"].int == rivalID }?["dist27"].double ?? 0) != 0
        var choices: [AcquisitionPlan.Choice] = []
        func add(_ k: AcquisitionPlan.Kind, need: Double, extra: Double, have: Double, loan: Double = 0, monthly: Double = 0, rate: Double = 0) {
            choices.append(.init(kind: k, cashNeeded: need, extraCost: extra, loan: loan, loanMonthly: monthly, loanRate: rate, affordable: have >= need))
        }
        let ownNeed = price + startup + reserve
        add(.own, need: ownNeed, extra: startup, have: liquid)
        add(.branch, need: ownNeed, extra: startup, have: liquid)
        let merge = RivalAbsorb.extraCost(.merge, price: price), shut = RivalAbsorb.extraCost(.shut, price: price)
        add(.merge, need: price + merge, extra: merge, have: cash)
        add(.shut, need: price + shut, extra: shut, have: cash)
        if co.value("fr")["on"].bool {
            add(.franchiseOldOwner, need: price, extra: 0, have: cash)
            add(.franchiseNewOwner, need: (price * 0.55 / 1000).rounded() * 1000, extra: 0, have: cash)
        }
        if ownBank != nil {
            let room = ownBankRoom()
            let loan = min((price * 0.7 / 1000).rounded() * 1000, (room / 1000).rounded(.down) * 1000)
            if loan > 0, room >= price * 0.2 {
                let rate = state.economy.policyRate + Banking.creditMargin(state.credit) + 0.01
                add(.ownBank, need: max(0, ownNeed - loan), extra: startup, have: liquid, loan: loan,
                    monthly: Loans.annuity(principal: loan, yearlyRate: rate, months: 96), rate: rate)
            }
        }
        return AcquisitionPlan(price: price, startupMoney: startup, reserve: reserve, liquid: liquid, cash: cash, hiddenBillRisk: troubled, choices: choices)
    }
}
