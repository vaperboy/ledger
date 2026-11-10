import Foundation
import GameCore
import Countries

public struct LendingModifiers: Sendable {
    public var rateAdjustment: @Sendable (Loan, GameState) -> Double = { _, _ in 0 }
    public var marginAdjustment: @Sendable (String, Company?, GameState) -> Double = { _, _, _ in 0 }
    public init() {}
}

public struct LoanOffer: Equatable, Sendable {
    public var maximum: Double
    public var margin: Double
    public var creditBand: String
}

public enum LoanResult: Equatable, Sendable {
    case ok(Loan)
    case declined
    case tooSmall
}

public enum Banking {
    public static let consumerBaseMonths = 80_000 / ReferenceEconomy.medianWage
    public static let assumedIncomeMonths = 380_000 / ReferenceEconomy.medianWage

    public static func creditBand(_ credit: Double) -> String {
        credit >= 80 ? "A" : credit >= 65 ? "B" : credit >= 50 ? "C" : credit >= 35 ? "D" : "E"
    }

    public static func creditMargin(_ credit: Double) -> Double {
        credit >= 80 ? 0.018 : credit >= 65 ? 0.028 : credit >= 50 ? 0.045 : credit >= 35 ? 0.075 : 0.12
    }

    public static func creditWord(_ credit: Double) -> String {
        credit >= 80 ? "Excellent" : credit >= 65 ? "Good" : credit >= 50 ? "Fair" : credit >= 35 ? "Weak" : "Poor"
    }

    public static func rate(of loan: Loan, state: GameState, modifiers: LendingModifiers = .init(), countryShift: Double = 0) -> Double {
        var core = max(0.005, state.economy.policyRate + countryShift + loan.margin)
        if let cut = state.rest["net31"]?["loanCut"], !cut.isNull, Double(state.week) < cut["until"].double { core = max(0.005, core - cut["cut"].double) }
        return core + modifiers.rateAdjustment(loan, state)
    }

    public static func countryRateShift(companyID: Int, state s: GameState, context: FinanceContext) -> Double {
        guard companyID != 0, let co = s.company(companyID), !co.countryCode.isEmpty, co.countryCode != s.homeCountryCode else { return 0 }
        return context.country(of: co, s).startingPolicyRate - context.homeCountry(s).startingPolicyRate
    }

    public static func overdraftRate(state s: GameState, country: Country, home: Country, personal: Bool = false) -> Double {
        s.economy.policyRate + (country.startingPolicyRate - home.startingPolicyRate) + country.overdraftMargin + (personal ? personalOverdraftExtra : 0)
    }
    public static let personalOverdraftExtra = 0.02

    public static func totalDebt(_ s: GameState, personalOnly: Bool = false) -> Double {
        s.loans.filter { !personalOnly || $0.companyID == 0 }.reduce(0) { $0 + $1.balance }
    }

    public static func offer(kind: String, amount: Double, company co: Company?, state s: GameState, netWorth: Double,
                             collateral: Double = 0, companyValue: Double? = nil, context: FinanceContext) -> LoanOffer {
        let band = creditBand(s.credit)
        var margin = creditMargin(s.credit) + (kind == "biz" ? 0.01 : kind == "mort" ? -0.012 : kind == "cons" ? 0.03 : kind == "lomb" ? -0.004 : 0)
        var maxLoan: Double
        let bandBiz: Double = band == "E" ? 0 : band == "D" ? 0.5 : 1
        switch kind {
        case "cons":
            let f: Double = band == "A" ? 2 : band == "B" ? 1.4 : band == "C" ? 1 : band == "D" ? 0.4 : 0
            maxLoan = max(0, consumerBaseMonths * context.homeCountry(s).medianMonthlyWage + max(0, netWorth) * 0.15) * f
        case "biz":
            let fromBooks: Double = co.map { max(0, CompanyFigures.yearlyProfitEstimate($0, currentWeek: s.week)) * 3 + CompanyFigures.fixedAssets($0) * 0.5 } ?? 0
            let base: Double = fromBooks + max(0, companyValue ?? 0) * 0.35
            maxLoan = (base + max(0, netWorth) * 0.25) * bandBiz
        case "mort":
            maxLoan = max(0, netWorth) * 1.6 * (band == "E" ? 0 : 1)
        case "lomb":
            let borrowed = s.loans.filter { $0.companyID == 0 && $0.kind == "lomb" }.reduce(0) { $0 + $1.balance }
            maxLoan = max(0, collateral - borrowed) * (band == "E" ? 0 : 1)
        default:
            maxLoan = 0
        }
        let personal = s.loans.filter { $0.companyID == 0 }
        let owedP = personal.reduce(0) { $0 + $1.balance }
        let owedC = co.map { c in s.loans.filter { $0.companyID == c.id }.reduce(0) { $0 + $1.balance } } ?? 0
        let payP = personal.reduce(0) { $0 + $1.monthlyPayment } * 12
        let payC = co.map { c in s.loans.filter { $0.companyID == c.id }.reduce(0) { $0 + $1.monthlyPayment } * 12 } ?? 0
        let openLimited = s.companies.filter { $0.status == .open }
        let profitShare = 0.4 * s.companies.filter { $0.status == .open }.reduce(0) {
            $0 + max(0, CompanyFigures.yearlyProfitEstimate($1, currentWeek: s.week)) * $1.ownership / 100
        }
        let income = max(profitShare, assumedIncomeMonths * context.homeCountry(s).medianMonthlyWage)
        let rate = s.economy.policyRate + countryRateShift(companyID: co?.id ?? 0, state: s, context: context) + margin
        func room(_ inc: Double, _ pay: Double) -> Double {
            let free = max(0, inc * 0.4 - pay)
            let f = Loans.annuity(principal: 100000, yearlyRate: rate, months: 60) * 12 / 100000
            return f > 0 ? free / f : 0
        }
        switch kind {
        case "cons": maxLoan = min(max(0, maxLoan - owedP), room(income, payP))
        case "mort":
            let mortgages = s.loans.filter { $0.companyID == 0 && $0.kind == "mort" }.reduce(0) { $0 + $1.balance }
            maxLoan = min(max(0, maxLoan - mortgages), room(income * 1.6, payP))
        case "biz":
            maxLoan = max(0, maxLoan - owedC)
            if let c = co, c.monthlyHistory.count >= 3 {
                let serviceable = max(max(0, CompanyFigures.yearlyProfitEstimate(c, currentWeek: s.week)) * 0.8, max(0, companyValue ?? 0) * 0.06)
                maxLoan = min(maxLoan, room(serviceable, payC))
            }
        default: break
        }
        if kind == "biz", let c = co, c.flag("loanFrozen") { maxLoan = 0 }
        if (owedP + owedC) > max(1, netWorth) * 0.6 { margin += 0.012 }
        margin += context.lending.marginAdjustment(kind, co, s)
        return LoanOffer(maximum: (maxLoan / 1000).rounded(.down) * 1000, margin: margin, creditBand: band)
    }

    public static func take(kind: String, amount: Double, termMonths: Int, company co: Company?, guaranteed: Bool = false,
                            state s: inout GameState, netWorth: Double, collateral: Double = 0, companyValue: Double? = nil, context: FinanceContext) -> LoanResult {
        let off = offer(kind: kind, amount: amount, company: co, state: s, netWorth: netWorth, collateral: collateral, companyValue: companyValue, context: context)
        if amount > off.maximum { return .declined }
        let currency = context.currency(co?.countryCode ?? s.homeCountryCode, s)
        if amount < currency.scaledPrice(5000) { return .tooSmall }
        var loan = Loan(raw: [:])
        loan.id = s.makeID()
        loan.kind = kind
        loan.name = kind == "biz" ? "Business loan" : kind == "cons" ? "Consumer loan" : kind == "lomb" ? "Loan against your collection" : "Mortgage"
        loan.balance = amount
        loan.originalAmount = amount
        loan.margin = off.margin
        loan.termMonths = termMonths
        loan.companyID = co?.id ?? 0
        loan.startWeek = s.week
        loan.isGuaranteed = guaranteed
        loan.monthlyPayment = Loans.annuity(principal: amount, yearlyRate: s.economy.policyRate + countryRateShift(companyID: loan.companyID, state: s, context: context) + off.margin, months: Double(termMonths))
        s.loans.append(loan)
        if let c = co {
            Payments.companyReceives(&s, companyID: c.id, amount: amount, category: nil, label: "Loan drawn")
        } else {
            Payments.playerReceives(&s, amount, label: "Loan drawn")
        }
        return .ok(loan)
    }

    public struct Instalment: Equatable, Sendable {
        public var payment: Double
        public var interest: Double
        public var principal: Double
        public var yearlyRate: Double
        public var monthsLeft: Int
        public var total: Double { interest + principal }
    }

    public static func instalment(of l: Loan, state s: GameState, context: FinanceContext) -> Instalment {
        let r = rate(of: l, state: s, modifiers: context.lending, countryShift: countryRateShift(companyID: l.companyID, state: s, context: context))
        var payment = l.monthlyPayment
        let elapsedMonths = ((Double(s.week - l.startWeek)) / 4.33).rounded(.down)
        let remaining = max(1, Double(l.termMonths == 0 ? 120 : l.termMonths) - elapsedMonths)
        if l.monthlyPayment > 0 && l.kind != "start" {
            payment = max(Loans.annuity(principal: l.balance, yearlyRate: r, months: remaining), l.balance * r / 12 * 1.02)
        }
        let interest = l.balance * r / 12
        let principal: Double = (l.graceUntilWeek > 0 && s.week < l.graceUntilWeek) ? 0 : min(l.balance, max(0, payment - interest))
        return Instalment(payment: payment, interest: interest, principal: principal, yearlyRate: r, monthsLeft: Int(saturating: remaining))
    }

    public static func paidThroughMonth(_ l: Loan) -> Int? { l.raw["ptm"].map { $0.int } }

    public static func instalmentSettled(_ l: Loan, state s: GameState) -> Bool {
        guard let p = paidThroughMonth(l) else { return false }
        return p >= GameCalendar.monthIndex(week: s.week)
    }

    public static func accruedInterest(of l: Loan, state s: GameState, context: FinanceContext) -> Double {
        if instalmentSettled(l, state: s) { return 0 }
        let d = GameCalendar.date(week: s.week, dayOffset: s.day)
        let dim = GameCalendar.daysFromCivil(year: d.month == 11 ? d.year + 1 : d.year, month: d.month == 11 ? 1 : d.month + 2, day: 1)
            - GameCalendar.daysFromCivil(year: d.year, month: d.month + 1, day: 1)
        let fraction = min(1, max(0, Double(d.day) / Double(max(1, dim))))
        let r = rate(of: l, state: s, modifiers: context.lending, countryShift: countryRateShift(companyID: l.companyID, state: s, context: context))
        return jsRound(l.balance * r / 12 * fraction)
    }

    public struct Payoff: Equatable, Sendable {
        public var balance: Double
        public var accruedInterest: Double
        public var total: Double { balance + accruedInterest }
    }
    public static func payoff(loanID: Int, state s: GameState, context: FinanceContext) -> Payoff? {
        guard let l = s.loans.first(where: { $0.id == loanID }) else { return nil }
        return Payoff(balance: l.balance, accruedInterest: accruedInterest(of: l, state: s, context: context))
    }

    public enum EarlyInstalment: Equatable, Sendable { case paid(Double), alreadySettled, notEnoughMoney, noLoan }

    public static func payInstalmentNow(loanID: Int, state s: inout GameState, context: FinanceContext) -> EarlyInstalment {
        guard let li = s.loans.firstIndex(where: { $0.id == loanID }) else { return .noLoan }
        let l = s.loans[li]
        if instalmentSettled(l, state: s) { return .alreadySettled }
        let inst = instalment(of: l, state: s, context: context)
        let amount = jsRound(inst.total)
        if Payments.liquid(s) < amount { return .notEnoughMoney }
        settle(&s, loan: l, inst: inst, context: context)
        guard let lj = s.loans.firstIndex(where: { $0.id == loanID }) else { return .paid(amount) }
        s.loans[lj].set("ptm", .number(Double(GameCalendar.monthIndex(week: s.week))))
        return .paid(amount)
    }

    private static func settle(_ s: inout GameState, loan l: Loan, inst: Instalment, context: FinanceContext) {
        if l.companyID != 0, s.companyIndex(l.companyID) != nil {
            Payments.companyPaysLoanInstalment(&s, companyID: l.companyID, interest: inst.interest, principal: inst.principal, loanName: l.name, loanID: l.id, context: context)
        } else {
            Payments.playerPaysLoanInstalment(&s, interest: inst.interest, principal: inst.principal, loanName: l.name)
        }
        guard let lj = s.loans.firstIndex(where: { $0.id == l.id }) else { return }
        s.loans[lj].balance -= inst.principal
        s.loans[lj].monthlyPayment = inst.payment
        if s.loans[lj].int("miss") > 0 { cureInstalment(&s, loanID: l.id) }
        if let lk = s.loans.firstIndex(where: { $0.id == l.id }), s.loans[lk].balance < 1 { s.loans.remove(at: lk) }
    }

    public static func repay(loanID: Int, amount: Double, state s: inout GameState, context: FinanceContext? = nil) -> Bool {
        guard let li = s.loans.firstIndex(where: { $0.id == loanID }) else { return false }
        let amt = min(amount, s.loans[li].balance)
        let loan = s.loans[li]
        let closing = amt >= loan.balance - 0.5
        let accrued = (closing && context != nil) ? accruedInterest(of: loan, state: s, context: context!) : 0
        if loan.companyID != 0, let ci = s.companyIndex(loan.companyID) {
            if s.cash < amt + accrued { return false }
            Payments.companyPays(&s, companyID: loan.companyID, amount: amt, category: nil, label: "Loan repaid")
            if accrued > 0 { Payments.companyPays(&s, companyID: loan.companyID, amount: accrued, category: "int", label: "Loan interest to payoff date") }
        } else {
            if s.cash < amt + accrued { return false }
            Payments.playerPays(&s, amt, label: "Loan repaid")
            if accrued > 0 { Payments.playerPays(&s, accrued, label: "Loan interest to payoff date"); s.stats.interestPaid += accrued }
        }
        s.loans[li].balance -= amt
        if s.loans[li].balance < 1 {
            s.loans.remove(at: li)
        } else if let c = context {
            s.loans[li].monthlyPayment = instalment(of: s.loans[li], state: s, context: c).payment
        }
        refreshCovenant(&s, companyID: loan.companyID)
        return true
    }

    public static func close(loanID: Int, repaid: Double, keep: Bool = false, state s: inout GameState) {
        guard let li = s.loans.firstIndex(where: { $0.id == loanID }) else { return }
        let loan = s.loans[li]
        let repaidAmt = max(0, min(loan.balance, repaid))
        if keep {
            s.loans[li].balance -= repaidAmt
            s.loans[li].companyID = 0
            if s.loans[li].balance < 1 { s.loans.remove(at: li) }
        } else {
            s.loans.remove(at: li)
        }
    }

    public static func collectMonthlyInstalments(state s: inout GameState, context: FinanceContext) {
        let month = GameCalendar.monthIndex(week: s.week)
        for loanSnapshot in s.loans {
            guard let li = s.loans.firstIndex(where: { $0.id == loanSnapshot.id }) else { continue }
            var l = s.loans[li]
            if instalmentSettled(l, state: s) { continue }
            let inst = instalment(of: l, state: s, context: context)
            if l.monthlyPayment > 0 && l.kind != "start" { l.monthlyPayment = inst.payment; s.loans[li] = l }
            let interest = inst.interest, principal = inst.principal
            if l.companyID != 0, let ci = s.companyIndex(l.companyID), !s.companies[ci].status.isLive { continue }
            if l.companyID != 0, let ci = s.companyIndex(l.companyID) {
                let room = max(0, s.companies[ci].cash + context.overdraftRoom(s.companies[ci], s))
                if jsRound(interest + principal) > room + 0.5 {
                    missInstalment(&s, loanID: l.id, interest: interest, companyIndex: ci, context: context)
                    continue
                }
            }
            settle(&s, loan: l, inst: inst, context: context)
            if let lj = s.loans.firstIndex(where: { $0.id == l.id }) { s.loans[lj].set("ptm", .number(Double(month))) }
        }
    }

    static let penaltyShare = 0.5
    static let callGraceWeeks = 6

    static func missInstalment(_ s: inout GameState, loanID: Int, interest: Double, companyIndex ci: Int, context: FinanceContext) {
        guard let li = s.loans.firstIndex(where: { $0.id == loanID }) else { return }
        let cur = context.currency(s.companies[ci].countryCode, s)
        let name = s.companies[ci].name
        let id = s.companies[ci].id
        let miss = s.loans[li].int("miss") + 1
        let added = interest * (1 + penaltyShare)
        s.loans[li].set("miss", miss)
        s.loans[li].balance += added
        var b = s.companies[ci].books
        b.add("int", added)
        s.companies[ci].books = b
        s.credit = clamp(s.credit - 2, 0, 100)
        if miss == 1 {
            s.addMessage(from: "Bank", title: "Missed loan payment at \(name)",
                         body: "\(name) could not pay its instalment on \(s.loans[li].name). \(cur.display(added)) of unpaid and penalty interest was added to the loan. Pay in time next month or the bank restricts credit.",
                         companyID: id, tone: "bad", sev: 3)
        } else if miss == 2 {
            s.companies[ci].set("loanFrozen", true)
            s.addMessage(from: "Bank", title: "Loan covenant breached at \(name)",
                         body: "Two instalments missed on \(s.loans[li].name). The bank restricts \(name)'s credit: no new loans until it is back on track. A third miss and the bank calls the loan.",
                         companyID: id, tone: "bad", sev: 3)
        } else if miss == 3 {
            s.companies[ci].set("loanFrozen", true)
            s.companies[ci].set("loanCall", s.week + callGraceWeeks)
            s.addMessage(from: "Bank", title: "Bank calls the loan at \(name)",
                         body: "Three missed instalments. The bank demands \(cur.display(s.loans[li].balance)) on \(s.loans[li].name). Put money in and pay the next instalment within \(callGraceWeeks) weeks, or \(name) is wound up.",
                         companyID: id, tone: "bad", sev: 4)
        }
    }

    static func cureInstalment(_ s: inout GameState, loanID: Int) {
        guard let li = s.loans.firstIndex(where: { $0.id == loanID }) else { return }
        s.loans[li].set("miss", 0)
        refreshCovenant(&s, companyID: s.loans[li].companyID)
    }

    static func refreshCovenant(_ s: inout GameState, companyID: Int) {
        guard companyID != 0, let ci = s.companyIndex(companyID), s.companies[ci].flag("loanFrozen") || s.companies[ci].int("loanCall") != 0 else { return }
        if s.loans.contains(where: { $0.companyID == companyID && $0.int("miss") > 0 }) { return }
        s.companies[ci].set("loanFrozen", false)
        s.companies[ci].set("loanCall", 0)
        s.addMessage(from: "Bank", title: "Loan back on track at \(s.companies[ci].name)",
                     body: "The instalments are paid. The bank lifts the credit restriction on \(s.companies[ci].name).", companyID: companyID, tone: "good", sev: 1)
    }
}
