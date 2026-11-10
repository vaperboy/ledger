import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Investments

public struct LoanQuote: Equatable, Sendable {
    public var amount: Double
    public var termMonths: Int
    public var maximum: Double
    public var yearlyRate: Double
    public var monthlyPayment: Double
    public var totalInterest: Double
    public var totalRepaid: Double
    public var creditBand: String
    public var tooSmall: Bool
    public var withinLimit: Bool { amount <= maximum }
}

public struct DepositQuote: Equatable, Sendable {
    public var weeks: Int
    public var yearlyRate: Double
    public var interest: Double
}

public struct LoanPayoff: Equatable, Sendable {
    public var monthsLeft: Int?
    public var interestLeft: Double
    public var yearlyRate: Double
}

public struct AcquisitionPlan: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case own, branch, merge, shut, franchiseOldOwner, franchiseNewOwner }
    public struct Choice: Identifiable, Equatable, Sendable {
        public var id: String { kind.rawValue }
        public var kind: Kind
        public var cashNeeded: Double
        public var extraCost: Double
        public var loan: Double
        public var loanMonthly: Double
        public var loanRate: Double
        public var affordable: Bool
    }
    public var price: Double
    public var startupMoney: Double
    public var reserve: Double
    public var liquid: Double
    public var cash: Double
    public var hiddenBillRisk: Bool
    public var choices: [Choice]
}

public extension GameEngine {
    static let loanTermChoices = [12, 24, 36, 60, 84, 120]
    static let depositTermChoices = [13, 26, 52]

    func loanQuote(kind: String, amount: Double, termMonths: Int, companyID: Int?) -> LoanQuote {
        let off = loanOffer(kind: kind, amount: amount, companyID: companyID)
        let co = companyID.flatMap { state.company($0) }
        let rate = state.economy.policyRate + Banking.countryRateShift(companyID: co?.id ?? 0, state: state, context: context) + off.margin
        let months = max(1, termMonths)
        let monthly = amount > 0 ? Loans.annuity(principal: amount, yearlyRate: rate, months: Double(months)) : 0
        let total = monthly * Double(months)
        let cur = context.currency(co?.countryCode ?? state.homeCountryCode, state)
        return LoanQuote(amount: amount, termMonths: months, maximum: off.maximum, yearlyRate: rate, monthlyPayment: monthly,
                         totalInterest: max(0, total - amount), totalRepaid: total, creditBand: off.creditBand,
                         tooSmall: amount < cur.scaledPrice(5000))
    }

    func depositQuote(amount: Double, weeks: Int) -> DepositQuote {
        let rate = max(0.01, state.economy.policyRate - 0.002 + Double(weeks) / 52 * 0.004)
        return DepositQuote(weeks: weeks, yearlyRate: rate, interest: max(0, amount) * rate * Double(weeks) / 52)
    }

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
        let months = Int(saturating: (n - 0.01).rounded(.up))
        return LoanPayoff(monthsLeft: months, interestLeft: max(0, p * n - b), yearlyRate: rate)
    }

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
        return AcquisitionPlan(price: price, startupMoney: startup, reserve: reserve, liquid: liquid, cash: cash, hiddenBillRisk: troubled, choices: choices)
    }
}
