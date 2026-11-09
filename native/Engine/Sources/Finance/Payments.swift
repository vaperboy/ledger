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
        AccountingLedger.note(category: category, label: label ?? defaultLabel(category, income: false))
        Ledger.moveRaw(&s, .company(companyID), -amt)
        if let cat = category {
            var b = s.companies[i].books
            b.add(cat, amt)
            s.companies[i].books = b
        }
        if let l = label { s.companies[i].addTransaction(week: s.week, amount: -amt, label: l) }
        return s.companies[i].cash >= 0
    }

    static let categoryNames: [String: String] = ["rev": "Sales", "cogs": "Supplier purchases", "wages": "Payroll", "rent": "Rent", "mkt": "Marketing", "ins": "Insurance",
                                                   "oth": "Running costs", "int": "Interest", "fine": "Fines", "acc": "Accounting fees", "tax": "Tax", "loss": "Losses"]
    static func defaultLabel(_ category: String?, income: Bool) -> String { category.flatMap { categoryNames[$0] } ?? (income ? "Receipt" : "Payment") }

    /// A company receives money. Original: `coIn`.
    public static func companyReceives(_ s: inout GameState, companyID: Int, amount: Double, category: String?, label: String?, bookInPnL: Bool = true) {
        guard let i = s.companyIndex(companyID) else { return }
        let amt = jsRound(amount)
        if Ledger.observer != nil { Ledger.cause = "gets:\(category ?? "-"):\(label ?? "")" }
        AccountingLedger.note(category: category, label: label ?? defaultLabel(category, income: true))
        Ledger.moveRaw(&s, .company(companyID), amt)
        if let cat = category, bookInPnL {
            var b = s.companies[i].books
            b.add(cat, amt)
            s.companies[i].books = b
        }
        if let l = label, bookInPnL { s.companies[i].addTransaction(week: s.week, amount: amt, label: l) }
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

    /// What the player can spend now: the one account's balance.
    public static func liquid(_ s: GameState) -> Double { s.cash }

    // MARK: Owner and company

    /// The owner puts money into a company. Original: `injectCash`.
    @discardableResult
    public static func injectCash(_ s: inout GameState, companyID: Int, amount: Double) -> Bool {
        guard let i = s.companyIndex(companyID), liquid(s) >= amount else { return false }
        Ledger.move(&s, .me, -amount, why: "Invested in \(s.companies[i].name)", companyID: companyID)
        AccountingLedger.note(category: "owner", label: "Owner investment")
        Ledger.moveRaw(&s, .company(companyID), amount)
        s.companies[i].ownerNetFlow += amount
        s.companies[i].injectedCapital += amount
        s.companies[i].addTransaction(week: s.week, amount: amount, label: "Owner investment")
        return true
    }

    /// Most that can go out as a dividend now: retained profits (equity above share capital), leaving two weeks of
    /// costs in the account. Original: `divMax`.
    public static func maximumDividend(_ co: Company, state s: GameState, context: FinanceContext) -> Double {
        let br = s.chainStores(of: co)
        if br.count >= 2 { return max(0, min(chainEquity(br, s), br.reduce(0) { $0 + spare($1, s, context) }).rounded(.down)) }
        let equity = CompanyFigures.assets(co) - CompanyFigures.debts(co, loans: s.loans) - co.shareCapital
        return max(0, (min(equity, co.cash - context.weeklyCost(co, s) * 2)).rounded(.down))
    }

    /// `needsBoard`: the company has partners, so a board meeting must vote for the dividend first.
    public enum DividendResult: Equatable, Sendable { case ok, noRetainedProfit, notEnoughCash, needsBoard }

    /// A limited company pays a dividend. Original: `payDividend`.
    public static func payDividend(_ s: inout GameState, companyID: Int, amount: Double, context: FinanceContext) -> DividendResult {
        guard let i = s.companyIndex(companyID) else { return .notEnoughCash }
        let co = s.companies[i]
        // A store of a chain is a branch: the dividend is the chain's, declared once from all branches (whichever store it is asked of).
        let br = s.chainStores(of: co)
        if br.count >= 2 { return payChainDividend(&s, br, amount: amount, context: context) }
        let equity = CompanyFigures.assets(co) - CompanyFigures.debts(co, loans: s.loans) - co.shareCapital
        if amount > equity { return .noRetainedProfit }
        if co.cash - amount < context.weeklyCost(co, s) * 2 { return .notEnoughCash }
        AccountingLedger.note(category: "owner", label: "Dividend")
        Ledger.moveRaw(&s, .company(companyID), -amount)
        s.companies[i].ownerNetFlow -= amount
        s.companies[i].addTransaction(week: s.week, amount: -amount, label: "Dividend")
        receiveDividend(&s, from: co, amount: amount, name: co.name, context: context)
        s.companies[i].distributed += amount
        return .ok
    }

    /// A chain is one company: its retained profit is that of all its branches together, and its cash is pooled.
    static func chainEquity(_ br: [Company], _ s: GameState) -> Double {
        br.reduce(0) { $0 + CompanyFigures.assets($1) - CompanyFigures.debts($1, loans: s.loans) - $1.shareCapital }
    }
    /// Cash a branch can give up and keep two weeks of its costs.
    static func spare(_ co: Company, _ s: GameState, _ context: FinanceContext) -> Double { co.cash - context.weeklyCost(co, s) * 2 }

    /// The chain's one dividend: each branch pays a part in proportion to its spare cash, and the owners of the chain (the cap table of its
    /// head office, the oldest store) receive it once.
    static func payChainDividend(_ s: inout GameState, _ br: [Company], amount: Double, context: FinanceContext) -> DividendResult {
        let head = br[0]
        if amount > chainEquity(br, s) { return .noRetainedProfit }
        let spares = br.map { max(0, spare($0, s, context)) }
        let total = spares.reduce(0, +)
        if total <= 0 || amount > total { return .notEnoughCash }
        var left = amount
        let last = spares.lastIndex { $0 > 0 } ?? 0
        for (k, co) in br.enumerated() where spares[k] > 0 && left > 0 {
            let part = k == last ? left : min(left, jsRound(amount * spares[k] / total))
            guard part > 0, let i = s.companyIndex(co.id) else { continue }
            AccountingLedger.note(category: "owner", label: "Dividend")
            Ledger.moveRaw(&s, .company(co.id), -part)
            s.companies[i].ownerNetFlow -= part
            s.companies[i].addTransaction(week: s.week, amount: -part, label: "Dividend (whole chain)")
            s.companies[i].distributed += part
            left -= part
        }
        let name = (s.rest["chains"]?.array ?? []).first { $0["id"].int == head.value("chain").int }?["name"].string ?? head.name
        receiveDividend(&s, from: head, amount: amount - left, name: name, context: context)
        return .ok
    }

    /// Keeps what a holding received as dividends, week by week (`divIn`: [[week, amount]], the latest 400 entries), so its income never depends on
    /// how many bank movements are still remembered.
    static func recordHoldingDividend(_ s: inout GameState, holdingIndex hi: Int, amount: Double) {
        guard amount > 0 else { return }
        var list: [JSONValue] = s.companies[hi].value("divIn").array
        if let last = list.last, last[0].int == s.week {
            list[list.count - 1] = .array([.number(Double(s.week)), .number(last[1].double + amount)])
        } else {
            list.append(.array([.number(Double(s.week)), .number(amount)]))
        }
        if list.count > 400 { list.removeFirst(list.count - 400) }
        s.companies[hi].set("divIn", .array(list))
    }

    /// Dividends a holding received in the given weeks (all time when nil).
    public static func holdingDividends(_ co: Company, weeks: ClosedRange<Int>? = nil) -> Double {
        co.value("divIn").array.filter { (e: JSONValue) -> Bool in weeks?.contains(e[0].int) ?? true }.reduce(0.0) { $0 + $1[1].double }
    }

    /// The owners' side of a dividend: the holding the company sits in, or you.
    static func receiveDividend(_ s: inout GameState, from co: Company, amount: Double, name: String, context: FinanceContext) {
        let mine = amount * co.ownership / 100
        if co.holdingID != 0, let hi = s.companyIndex(co.holdingID), s.companies[hi].status.isLive {
            Ledger.moveRaw(&s, .company(co.holdingID), mine)
            s.companies[hi].addTransaction(week: s.week, amount: mine, label: "Dividend from \(name)")
            recordHoldingDividend(&s, holdingIndex: hi, amount: mine)
        } else {
            playerReceives(&s, mine, label: "Dividend from \(name)")
            s.tax.dividends += mine
            s.stats.dividendsReceived += mine
        }
        // A holding that owns a bought stake (a `holders` entry with `hid`) takes its share too; outside owners' shares leave the group.
        for l in co.value("holders").array where l["hid"].int != 0 {
            let part = amount * l["pct"].double / 100
            guard part > 0, let hi = s.companyIndex(l["hid"].int), s.companies[hi].status.isLive else { continue }
            Ledger.moveRaw(&s, .company(l["hid"].int), part)
            s.companies[hi].addTransaction(week: s.week, amount: part, label: "Dividend from \(name)")
            recordHoldingDividend(&s, holdingIndex: hi, amount: part)
        }
        let shield = context.homeCountry(s).dividendShield
        let injected = s.companies.filter { $0.status.isLive }.reduce(0) { $0 + $1.injectedCapital * $1.ownership / 100 }
        s.tax.dividendShield = max(s.tax.dividendShield, injected * shield)
        PersonalFinance.withholdNow(&s, context: context)   // dividend tax is withheld on payout
    }

    // MARK: Loan instalments

    /// Original: `payCoLoan`. Returns whether the account stays within its overdraft room.
    @discardableResult
    static func companyPaysLoanInstalment(_ s: inout GameState, companyID: Int, interest: Double, principal: Double, loanName: String, loanID: Int = 0, context: FinanceContext) -> Bool {
        guard let i = s.companyIndex(companyID) else { return false }
        AccountingLedger.note(category: "loan", label: "Loan payment: \(loanName)", ref: loanID == 0 ? "" : "loan:\(loanID)")
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
