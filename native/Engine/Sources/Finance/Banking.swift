import Foundation
import GameCore
import Countries

/// Hooks for effects that other features add to lending (country events that raise rates, a banker friend,
/// a finance manager ...). The simulation fills them in; by default there are none.
public struct LendingModifiers: Sendable {
    /// Extra to add to a loan's interest rate (event-driven rate rises) minus any temporary cut.
    public var rateAdjustment: @Sendable (Loan, GameState) -> Double = { _, _ in 0 }
    /// Extra to add to the margin offered on a new loan for a company.
    public var marginAdjustment: @Sendable (String, Company?, GameState) -> Double = { _, _, _ in 0 }
    public init() {}
}

public struct LoanOffer: Equatable, Sendable {
    public var maximum: Double
    public var margin: Double
    public var creditBand: String
    /// Id of the player's own bank company that would fund the loan, 0 if an outside bank does.
    public var ownBankID: Int
}

public enum LoanResult: Equatable, Sendable {
    case ok(Loan)
    case declined
    case tooSmall
}

/// Lending: rates, offers, drawing, repaying and the monthly instalments. Original: `engine/money/money.js`.
public enum Banking {
    /// A bank lends a consumer at least this many months of the country's median wage (80 000 at the reference economy's 56 000).
    public static let consumerBaseMonths = 80_000 / ReferenceEconomy.medianWage
    /// A bank assumes a borrower earns at least this many months of the median wage a year (380 000 at the reference economy).
    public static let assumedIncomeMonths = 380_000 / ReferenceEconomy.medianWage

    // MARK: Credit

    /// Original: `creditBand`.
    public static func creditBand(_ credit: Double) -> String {
        credit >= 80 ? "A" : credit >= 65 ? "B" : credit >= 50 ? "C" : credit >= 35 ? "D" : "E"
    }

    /// Bank margin by credit band. Original: `creditMargin`.
    public static func creditMargin(_ credit: Double) -> Double {
        credit >= 80 ? 0.018 : credit >= 65 ? 0.028 : credit >= 50 ? 0.045 : credit >= 35 ? 0.075 : 0.12
    }

    public static func creditWord(_ credit: Double) -> String {
        credit >= 80 ? "Excellent" : credit >= 65 ? "Good" : credit >= 50 ? "Fair" : credit >= 35 ? "Weak" : "Poor"
    }

    // MARK: Rates

    /// Yearly interest rate of a loan today. Original: `loanRate`.
    public static func rate(of loan: Loan, state: GameState, modifiers: LendingModifiers = .init(), countryShift: Double = 0) -> Double {
        var core = max(0.005, state.economy.policyRate + countryShift + loan.margin)
        // A banker you know cuts the rate for a while (world around you: favours). Original: 'loanRate' step.
        if let cut = state.rest["net31"]?["loanCut"], !cut.isNull, Double(state.week) < cut["until"].double { core = max(0.005, core - cut["cut"].double) }
        return core + modifiers.rateAdjustment(loan, state)
    }

    /// How far the policy rate of a company's own country sits from the home country's (the economy tracks one policy rate,
    /// moving around the home country's starting rate). 0 for the player's own loans and for companies at home.
    public static func countryRateShift(companyID: Int, state s: GameState, context: FinanceContext) -> Double {
        guard companyID != 0, let co = s.company(companyID), !co.countryCode.isEmpty, co.countryCode != s.homeCountryCode else { return 0 }
        return context.country(of: co, s).startingPolicyRate - context.homeCountry(s).startingPolicyRate
    }

    public static func totalDebt(_ s: GameState, personalOnly: Bool = false) -> Double {
        s.loans.filter { !personalOnly || $0.companyID == 0 }.reduce(0) { $0 + $1.balance }
    }

    // MARK: Offers

    /// What the bank would lend. `kind`: "cons" consumer, "biz" business, "mort" mortgage, "lomb" against collateral.
    /// `netWorth` is the player's net worth; `collateral` is the total lendable value of luxury assets.
    /// Original: `loanOfferCore` (+ the steps that add the own-bank, finance-manager and young-borrower rules).
    public static func offer(kind: String, amount: Double, company co: Company?, state s: GameState, netWorth: Double,
                             collateral: Double = 0, context: FinanceContext) -> LoanOffer {
        let band = creditBand(s.credit)
        var margin = creditMargin(s.credit) + (kind == "biz" ? 0.01 : kind == "mort" ? -0.012 : kind == "cons" ? 0.03 : kind == "lomb" ? -0.004 : 0)
        var maxLoan: Double
        let bandBiz: Double = band == "E" ? 0 : band == "D" ? 0.5 : 1
        switch kind {
        case "cons":
            let f: Double = band == "A" ? 2 : band == "B" ? 1.4 : band == "C" ? 1 : band == "D" ? 0.4 : 0
            maxLoan = max(0, consumerBaseMonths * context.homeCountry(s).medianMonthlyWage + max(0, netWorth) * 0.15) * f
        case "biz":
            let base = co.map { max(0, CompanyFigures.yearlyProfitEstimate($0, currentWeek: s.week)) * 3 + CompanyFigures.fixedAssets($0) * 0.5 } ?? 0
            maxLoan = (base + max(0, netWorth) * 0.25) * bandBiz
        case "mort":
            maxLoan = max(0, netWorth) * 1.6 * (band == "E" ? 0 : 1)
        case "lomb":
            let borrowed = s.loans.filter { $0.companyID == 0 && $0.kind == "lomb" }.reduce(0) { $0 + $1.balance }
            maxLoan = max(0, collateral - borrowed) * (band == "E" ? 0 : 1)
        default:
            maxLoan = 0
        }
        // Real bank rules: what you already owe counts against you, and payments must fit your income.
        let personal = s.loans.filter { $0.companyID == 0 }
        let owedP = personal.reduce(0) { $0 + $1.balance }
        let owedC = co.map { c in s.loans.filter { $0.companyID == c.id }.reduce(0) { $0 + $1.balance } } ?? 0
        let payP = personal.reduce(0) { $0 + $1.monthlyPayment } * 12
        let payC = co.map { c in s.loans.filter { $0.companyID == c.id }.reduce(0) { $0 + $1.monthlyPayment } * 12 } ?? 0
        let openLimited = s.companies.filter { $0.status == .open && $0.form == .limited }
        let ownerSalaries = openLimited.reduce(0) { $0 + $1.ownerMonthlySalary * 12 }
        let profitShare = 0.4 * s.companies.filter { $0.status == .open }.reduce(0) {
            $0 + max(0, CompanyFigures.yearlyProfitEstimate($1, currentWeek: s.week)) * $1.ownership / 100
        }
        // The least income a bank assumes: a fixed number of months of the country's median wage. (The original wrote
        // `380000 * CC().wage0`, but no country defines `wage0`, so every country got the same floor, the level of one particular
        // country. Corrected on purpose; docs/MONEY_SCALING.md.)
        let income = max(ownerSalaries + profitShare, assumedIncomeMonths * context.homeCountry(s).medianMonthlyWage)
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
                maxLoan = min(maxLoan, room(max(0, CompanyFigures.yearlyProfitEstimate(c, currentWeek: s.week)) * 0.8, payC))
            }
        default: break
        }
        // A bank that has restricted or called the company's loans lends it nothing more.
        if kind == "biz", let c = co, c.flag("loanFrozen") { maxLoan = 0 }
        if (owedP + owedC) > max(1, netWorth) * 0.6 { margin += 0.012 }
        // Own bank: cheaper (it earns the spread), but priced like anyone else's for its own owner (+0.006).
        var ownBank = 0
        // The own bank lends to your companies up to 25% of its capital; beyond that an outside bank funds the loan.
        if let bank = s.companies.first(where: { b in
            guard b.type == "bank" && b.status == .open else { return false }
            let fm = b.value("fm"), equity = b.cash + fm["book"].double + fm["gb"].double - fm["dep"].double
            return fm["gb"].double < max(0, equity) * 0.25
        }) {
            margin -= 0.006
            margin += 0.006
            ownBank = bank.id
        }
        margin += context.lending.marginAdjustment(kind, co, s)
        return LoanOffer(maximum: (maxLoan / 1000).rounded(.down) * 1000, margin: margin, creditBand: band, ownBankID: ownBank)
    }

    // MARK: Drawing and repaying

    /// Take out a loan. Money lands in the company's account (or the player's). Original: `takeLoan`.
    public static func take(kind: String, amount: Double, termMonths: Int, company co: Company?, guaranteed: Bool = false,
                            state s: inout GameState, netWorth: Double, collateral: Double = 0, context: FinanceContext) -> LoanResult {
        let off = offer(kind: kind, amount: amount, company: co, state: s, netWorth: netWorth, collateral: collateral, context: context)
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
        loan.bankCompanyID = off.ownBankID
        if loan.bankCompanyID != 0 {
            if let bi = s.companyIndex(loan.bankCompanyID), s.companies[bi].status == .open, s.companies[bi].cash > amount * 1.2 {
                Ledger.moveRaw(&s, .company(loan.bankCompanyID), -amount)
                var fm = s.companies[bi].value("fm")
                fm["gb"] = .number(fm["gb"].double + amount)
                s.companies[bi].set("fm", fm)
            } else {
                loan.bankCompanyID = 0
            }
        }
        loan.monthlyPayment = Loans.annuity(principal: amount, yearlyRate: s.economy.policyRate + countryRateShift(companyID: loan.companyID, state: s, context: context) + off.margin, months: Double(termMonths))
        s.loans.append(loan)
        if let c = co {
            Payments.companyReceives(&s, companyID: c.id, amount: amount, category: nil, label: "Loan drawn")
        } else {
            Payments.playerReceives(&s, amount, label: "Loan drawn")
        }
        return .ok(loan)
    }

    /// Repay part or all of a loan from the right account. Returns false if there is not enough money.
    /// Original: `repayLoan`.
    public static func repay(loanID: Int, amount: Double, state s: inout GameState) -> Bool {
        guard let li = s.loans.firstIndex(where: { $0.id == loanID }) else { return false }
        let amt = min(amount, s.loans[li].balance)
        let loan = s.loans[li]
        if loan.companyID != 0, let ci = s.companyIndex(loan.companyID) {
            if s.companies[ci].cash < amt { return false }
            Payments.companyPays(&s, companyID: loan.companyID, amount: amt, category: nil, label: "Loan repaid")
        } else {
            if s.cash + s.savings < amt { return false }
            Payments.transferFromSavings(&s, need: amt)
            Payments.playerPays(&s, amt, label: "Loan repaid")
        }
        if loan.bankCompanyID != 0, let bi = s.companyIndex(loan.bankCompanyID), s.companies[bi].status == .open {
            Ledger.moveRaw(&s, .company(loan.bankCompanyID), amt)
            var fm = s.companies[bi].value("fm")
            fm["gb"] = .number(max(0, fm["gb"].double - amt))
            s.companies[bi].set("fm", fm)
        }
        s.loans[li].balance -= amt
        if s.loans[li].balance < 1 {
            s.loans.remove(at: li)
        } else {
            let l = s.loans[li]
            s.loans[li].monthlyPayment = min(l.monthlyPayment, Loans.annuity(principal: l.balance, yearlyRate: s.economy.policyRate + l.margin, months: 12))
        }
        refreshCovenant(&s, companyID: loan.companyID)
        return true
    }

    /// Wipe a loan, e.g. when a company fails. `repaid` is what the lender actually receives; with `keep` the
    /// loan stays on the books as the player's own debt. Original: `closeLoan`.
    public static func close(loanID: Int, repaid: Double, keep: Bool = false, state s: inout GameState) {
        guard let li = s.loans.firstIndex(where: { $0.id == loanID }) else { return }
        let loan = s.loans[li]
        let repaidAmt = max(0, min(loan.balance, repaid))
        if loan.bankCompanyID != 0, let bi = s.companyIndex(loan.bankCompanyID), s.companies[bi].status == .open {
            Ledger.moveRaw(&s, .company(loan.bankCompanyID), repaidAmt)
            var fm = s.companies[bi].value("fm")
            fm["gb"] = .number(max(0, fm["gb"].double - loan.balance))
            s.companies[bi].set("fm", fm)
            let loss = loan.balance - repaidAmt
            if loss > 1 && !keep {
                var b = s.companies[bi].books
                b.add("loss", loss)
                s.companies[bi].books = b
            }
            s.loans[li].bankCompanyID = 0
        }
        if keep {
            s.loans[li].balance -= repaidAmt
            s.loans[li].companyID = 0
            if s.loans[li].balance < 1 { s.loans.remove(at: li) }
        } else {
            s.loans.remove(at: li)
        }
    }

    // MARK: Monthly instalments

    /// Collect this month's instalment on every loan. Original: `loansDueMonth`.
    /// Interest and principal come out of the right account on the day; the payment is re-worked each month so
    /// a loan always finishes on time, and never pays less than the interest.
    public static func collectMonthlyInstalments(state s: inout GameState, context: FinanceContext) {
        for loanSnapshot in s.loans {
            guard let li = s.loans.firstIndex(where: { $0.id == loanSnapshot.id }) else { continue }
            var l = s.loans[li]
            let r = rate(of: l, state: s, modifiers: context.lending, countryShift: countryRateShift(companyID: l.companyID, state: s, context: context))
            if l.monthlyPayment > 0 && l.kind != "start" {
                let elapsedMonths = ((Double(s.week - l.startWeek)) / 4.33).rounded(.down)
                let remaining = max(1, Double(l.termMonths == 0 ? 120 : l.termMonths) - elapsedMonths)
                l.monthlyPayment = max(Loans.annuity(principal: l.balance, yearlyRate: r, months: remaining), l.balance * r / 12 * 1.02)
                s.loans[li] = l
            }
            let interest = l.balance * r / 12
            let principal: Double = (l.graceUntilWeek > 0 && s.week < l.graceUntilWeek) ? 0 : min(l.balance, max(0, l.monthlyPayment - interest))
            if l.companyID != 0, let ci = s.companyIndex(l.companyID), !s.companies[ci].status.isLive { continue }
            if l.companyID != 0, let ci = s.companyIndex(l.companyID) {
                // A company that cannot cover the instalment (cash plus overdraft room) misses it: no cash moves, the unpaid interest
                // and a penalty are added to the loan, and the bank escalates.
                let room = max(0, s.companies[ci].cash + context.overdraftRoom(s.companies[ci], s))
                if jsRound(interest + principal) > room + 0.5 {
                    missInstalment(&s, loanID: l.id, interest: interest, companyIndex: ci, context: context)
                    continue
                }
                Payments.companyPaysLoanInstalment(&s, companyID: l.companyID, interest: interest, principal: principal, loanName: l.name, context: context)
            } else {
                Payments.playerPaysLoanInstalment(&s, interest: interest, principal: principal, loanName: l.name)
            }
            guard let lj = s.loans.firstIndex(where: { $0.id == l.id }) else { continue }
            s.loans[lj].balance -= principal
            if s.loans[lj].int("miss") > 0 { cureInstalment(&s, loanID: l.id) }
            if l.bankCompanyID != 0, let bi = s.companyIndex(l.bankCompanyID), s.companies[bi].status == .open {
                Payments.companyReceives(&s, companyID: l.bankCompanyID, amount: interest, category: "rev", label: "Interest from group")
                Ledger.moveRaw(&s, .company(l.bankCompanyID), principal)
                var fm = s.companies[bi].value("fm")
                fm["gb"] = .number(max(0, fm["gb"].double - principal))
                s.companies[bi].set("fm", fm)
            }
            if s.loans[lj].balance < 1 {
                s.loans.remove(at: lj)
            }
        }
    }

    // MARK: Missed instalments

    /// Penalty on top of the interest that went unpaid: half of it again.
    static let penaltyShare = 0.5
    /// Weeks the bank gives after calling a loan before the company is wound up (see `Failure`).
    static let callGraceWeeks = 6

    /// The company could not pay: the unpaid interest plus a penalty is added to the loan (booked as interest; no cash moves).
    /// 1st miss: warning. 2nd: covenant breach, the bank restricts credit (`loanFrozen`). 3rd: the bank calls the loan
    /// (`loanCall` = the week the company is wound up unless it has caught up; the weekly check then uses the bankruptcy path).
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
                         companyID: id, tone: "bad")
        } else if miss == 2 {
            s.companies[ci].set("loanFrozen", true)
            s.addMessage(from: "Bank", title: "Loan covenant breached at \(name)",
                         body: "Two instalments missed on \(s.loans[li].name). The bank restricts \(name)'s credit: no new loans until it is back on track. A third miss and the bank calls the loan.",
                         companyID: id, tone: "bad")
        } else if miss == 3 {
            s.companies[ci].set("loanFrozen", true)
            s.companies[ci].set("loanCall", s.week + callGraceWeeks)
            s.addMessage(from: "Bank", title: "Bank calls the loan at \(name)",
                         body: "Three missed instalments. The bank demands \(cur.display(s.loans[li].balance)) on \(s.loans[li].name). Put money in and pay the next instalment within \(callGraceWeeks) weeks, or \(name) is wound up.",
                         companyID: id, tone: "bad")
        }
    }

    /// An instalment was paid after misses: the loan is back on track.
    static func cureInstalment(_ s: inout GameState, loanID: Int) {
        guard let li = s.loans.firstIndex(where: { $0.id == loanID }) else { return }
        s.loans[li].set("miss", 0)
        refreshCovenant(&s, companyID: s.loans[li].companyID)
    }

    /// Lifts the credit restriction and the loan call once no loan of the company is in arrears.
    static func refreshCovenant(_ s: inout GameState, companyID: Int) {
        guard companyID != 0, let ci = s.companyIndex(companyID), s.companies[ci].flag("loanFrozen") || s.companies[ci].int("loanCall") != 0 else { return }
        if s.loans.contains(where: { $0.companyID == companyID && $0.int("miss") > 0 }) { return }
        s.companies[ci].set("loanFrozen", false)
        s.companies[ci].set("loanCall", 0)
        s.addMessage(from: "Bank", title: "Loan back on track at \(s.companies[ci].name)",
                     body: "The instalments are paid. The bank lifts the credit restriction on \(s.companies[ci].name).", companyID: companyID, tone: "good")
    }
}
