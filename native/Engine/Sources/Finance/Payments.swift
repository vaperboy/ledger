import Foundation
import GameCore
import Countries

/// Every payment between the player, companies and the outside world. Original: `payCo`, `coIn`, `payMe`, `gainMe`
/// and friends in engine/money/money.js. Each one moves cash through `Ledger` (so it is recorded) and books the
/// amount in the right category of the company's accounts.
public enum Payments {
    /// Recurring costs that, while a week is being simulated in day mode, wait on the monthly bill instead of
    /// leaving cash at once. Original: `MONTHLY` in tidier_screens_and_monthly_bills.js.
    static let monthlyCategories: Set<String> = ["oth", "mkt", "ins", "acc", "rent"]

    // MARK: Companies

    /// A company pays. `category` books it in the P&L ("wages", "rent", "oth", "mkt", "ins", "acc", "int", "fine", "tax" ...);
    /// nil category = not an expense (e.g. buying equipment, repaying a loan). A labelled payment shows in the company's
    /// transaction list and always leaves cash now. Returns whether the account is still in credit.
    @discardableResult
    public static func companyPays(_ s: inout GameState, companyID: Int, amount: Double, category: String?, label: String? = nil) -> Bool {
        guard let i = s.companyIndex(companyID) else { return false }
        var amt = amount
        // Fines are cut by a good lawyer or a legal team in the head office. Original: payCoCore.
        if category == "fine" {
            if let q = s.companies[i].value("law")["q"].isNull ? nil : s.companies[i].value("law")["q"].double { amt *= 1.1 - 0.45 * q }
            if s.hasHeadOffice("law") { amt *= 0.85 }
            if s.companies[i].flag("brdLaw") { amt *= 0.9 }   // a legal adviser on the board
            // A lawyer you know gets the next fine halved (world around you: favours).
            if amt > 0, s.rest["net31"]?["fineCut"].double ?? 0 != 0 { amt *= 0.5; s.rest["net31"]?["fineCut"] = 0 }
        }
        // A finance manager in the management team: cheaper books and fines.
        if category == "fine" || category == "acc", s.companies[i].value("tm")["fin"].double > 0 { amt *= 1 - 0.15 * s.companies[i].value("tm")["fin"].double }
        // Monthly bills build up during a week simulated in day mode. Original: 'payCo.later'.
        if s.transient.simulatingWeek && s.dayMode && label == nil, let cat = category, monthlyCategories.contains(cat), s.companies[i].status.isLive {
            let a = jsRound(amt)
            if a <= 0 { return true }
            s.companies[i].addPayable("other", a)
            var b = s.companies[i].books
            b.add(cat, a)
            s.companies[i].books = b
            var f30 = s.companies[i].value("f30")
            f30[cat] = .number(f30[cat].double + a)
            s.companies[i].set("f30", f30)
            return true
        }
        amt = jsRound(amt)
        if amt <= 0 { return true }
        if Ledger.observer != nil { Ledger.cause = "pays:\(category ?? "-"):\(label ?? "")" }
        Ledger.moveRaw(&s, .company(companyID), -amt)
        if let cat = category {
            var b = s.companies[i].books
            b.add(cat, amt)
            s.companies[i].books = b
        }
        if let l = label { s.companies[i].addTransaction(week: s.week, amount: -amt, label: l) }
        return s.companies[i].cash >= 0
    }

    /// A company receives money. Original: `coIn`.
    public static func companyReceives(_ s: inout GameState, companyID: Int, amount: Double, category: String?, label: String?) {
        guard let i = s.companyIndex(companyID) else { return }
        let amt = jsRound(amount)
        if Ledger.observer != nil { Ledger.cause = "gets:\(category ?? "-"):\(label ?? "")" }
        Ledger.moveRaw(&s, .company(companyID), amt)
        if let cat = category {
            var b = s.companies[i].books
            b.add(cat, amt)
            s.companies[i].books = b
        }
        if let l = label { s.companies[i].addTransaction(week: s.week, amount: amt, label: l) }
    }

    /// Book an expense without moving cash. Original: `bk`.
    public static func book(_ s: inout GameState, companyID: Int, category: String, amount: Double) {
        guard let i = s.companyIndex(companyID) else { return }
        var b = s.companies[i].books
        b.add(category, amount)
        s.companies[i].books = b
    }

    // MARK: The player

    /// Proceeds from selling a company or shares of it, to whoever owns it: the holding company when it sits in a holding (cash and the gain in its
    /// books, like dividends), else you (cash and the capital-gains base). Returns true when it went to a holding.
    @discardableResult
    public static func ownerReceivesSale(_ s: inout GameState, from co: Company, amount: Double, gain: Double, label: String) -> Bool {
        let g = max(0, gain)
        if co.holdingID != 0, let hi = s.companyIndex(co.holdingID), s.companies[hi].status.isLive {
            let amt = jsRound(amount)
            Ledger.moveRaw(&s, .company(co.holdingID), amt)
            s.companies[hi].addTransaction(week: s.week, amount: amt, label: label)
            book(&s, companyID: co.holdingID, category: "gain", amount: g)
            return true
        }
        playerReceives(&s, amount, label: label, companyID: co.id)
        s.tax.gains += g
        return false
    }

    public static func playerPays(_ s: inout GameState, _ amount: Double, label: String, companyID: Int = 0) {
        Ledger.move(&s, .me, -jsRound(amount), why: label, companyID: companyID)
    }
    public static func playerReceives(_ s: inout GameState, _ amount: Double, label: String, companyID: Int = 0) {
        Ledger.move(&s, .me, jsRound(amount), why: label, companyID: companyID)
    }

    /// When the current account is short, the rest comes over from savings: one transfer on the statement.
    /// Original: `fromSavings`.
    public static func transferFromSavings(_ s: inout GameState, need: Double) {
        let r = min(max(0, s.savings), need - max(0, s.cash))
        if r > 0 {
            s.savings -= r
            Ledger.move(&s, .me, r, why: "From savings")
        }
    }

    public static func liquid(_ s: GameState) -> Double { s.cash + s.savings }

    // MARK: Owner and company

    /// The owner puts money into a company. Original: `injectCash`.
    @discardableResult
    public static func injectCash(_ s: inout GameState, companyID: Int, amount: Double) -> Bool {
        guard let i = s.companyIndex(companyID), liquid(s) >= amount else { return false }
        transferFromSavings(&s, need: amount)
        Ledger.move(&s, .me, -amount, why: "Invested in \(s.companies[i].name)", companyID: companyID)
        Ledger.moveRaw(&s, .company(companyID), amount)
        s.companies[i].ownerNetFlow += amount
        if s.companies[i].form == .limited { s.companies[i].injectedCapital += amount }
        s.companies[i].addTransaction(week: s.week, amount: amount, label: "Owner investment")
        return true
    }

    public enum WithdrawResult: Equatable, Sendable { case ok, notEnoughCash, dividendOnly }

    /// A sole trader takes money out of the business. A limited company may only pay dividends. Original: `withdrawCash`.
    public static func withdrawCash(_ s: inout GameState, companyID: Int, amount: Double) -> WithdrawResult {
        guard let i = s.companyIndex(companyID) else { return .notEnoughCash }
        guard s.companies[i].form == .soleTrader else { return .dividendOnly }
        if s.companies[i].cash < amount { return .notEnoughCash }
        Ledger.moveRaw(&s, .company(companyID), -amount)
        s.companies[i].ownerNetFlow -= amount
        playerReceives(&s, amount, label: "Drawing from \(s.companies[i].name)")
        s.companies[i].distributed += amount
        s.companies[i].addTransaction(week: s.week, amount: -amount, label: "Owner drawing")
        return .ok
    }

    /// Most that can go out as a dividend now: retained profits (equity above share capital), leaving two weeks of
    /// costs in the account. Original: `divMax`.
    public static func maximumDividend(_ co: Company, state s: GameState, context: FinanceContext) -> Double {
        let equity = CompanyFigures.assets(co) - CompanyFigures.debts(co, loans: s.loans) - co.shareCapital
        return max(0, (min(equity, co.cash - context.weeklyCost(co, s) * 2)).rounded(.down))
    }

    public enum DividendResult: Equatable, Sendable { case ok, notLimitedCompany, noRetainedProfit, notEnoughCash }

    /// A limited company pays a dividend. Original: `payDividend`.
    public static func payDividend(_ s: inout GameState, companyID: Int, amount: Double, context: FinanceContext) -> DividendResult {
        guard let i = s.companyIndex(companyID) else { return .notEnoughCash }
        let co = s.companies[i]
        guard co.form == .limited else { return .notLimitedCompany }
        let equity = CompanyFigures.assets(co) - CompanyFigures.debts(co, loans: s.loans) - co.shareCapital
        if amount > equity { return .noRetainedProfit }
        if co.cash - amount < context.weeklyCost(co, s) * 2 { return .notEnoughCash }
        Ledger.moveRaw(&s, .company(companyID), -amount)
        s.companies[i].ownerNetFlow -= amount
        s.companies[i].addTransaction(week: s.week, amount: -amount, label: "Dividend")
        let mine = amount * co.ownership / 100
        if co.holdingID != 0, let hi = s.companyIndex(co.holdingID), s.companies[hi].status.isLive {
            Ledger.moveRaw(&s, .company(co.holdingID), mine)
            s.companies[hi].addTransaction(week: s.week, amount: mine, label: "Dividend from \(co.name)")
        } else {
            playerReceives(&s, mine, label: "Dividend from \(co.name)")
            s.tax.dividends += mine
            s.stats.dividendsReceived += mine
        }
        let shield = context.homeCountry(s).dividendShield
        let injected = s.companies.filter { $0.status.isLive && $0.form == .limited }.reduce(0) { $0 + $1.injectedCapital * $1.ownership / 100 }
        s.tax.dividendShield = max(s.tax.dividendShield, injected * shield)
        s.companies[i].distributed += amount
        return .ok
    }

    // MARK: Loan instalments

    /// Original: `payCoLoan`. Returns whether the account stays within its overdraft room.
    @discardableResult
    static func companyPaysLoanInstalment(_ s: inout GameState, companyID: Int, interest: Double, principal: Double, loanName: String, context: FinanceContext) -> Bool {
        guard let i = s.companyIndex(companyID) else { return false }
        Ledger.moveRaw(&s, .company(companyID), -jsRound(interest + principal))
        var b = s.companies[i].books
        b.add("int", interest)
        s.companies[i].books = b
        s.companies[i].addTransaction(week: s.week, amount: -(interest + principal), label: "Loan payment: \(loanName)")
        return s.companies[i].cash >= -context.overdraftRoom(s.companies[i], s)
    }

    /// Original: `payPersonalLoan`. Missing the limit hurts the credit score.
    @discardableResult
    static func playerPaysLoanInstalment(_ s: inout GameState, interest: Double, principal: Double, loanName: String) -> Bool {
        let total = interest + principal
        Ledger.move(&s, .me, -jsRound(total), why: "Loan payment: \(loanName)")
        s.stats.interestPaid += interest
        if s.cash < -s.overdraftLimit {
            s.credit = clamp(s.credit - 4, 0, 100)
            s.note("You could not cover a loan payment in full.", tone: "bad")
            return false
        }
        return true
    }
}
