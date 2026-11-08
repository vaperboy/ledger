import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// When things go wrong: company bankruptcy, forced sales, the bank closing in, game over.
/// Original: `bankruptcyCore`, `forcedSale`, `checkOver`, `coverFromENK` (engine/core/week.js).
///
/// A company fails when it cannot pay: cash below its overdraft room for many weeks, or bills unpaid for months.
/// A *limited company's* owner loses what was put in (unless they signed a personal guarantee); a *sole trader*
/// is personally liable for everything.
public enum Failure {
    /// `announce` false: one store of a chain that fails as a whole (`chainBankrupt` sends the one message, counts it once and hits credit once).
    /// Returns what lands on the owner personally.
    @discardableResult
    public static func bankrupt(_ s: inout GameState, companyIndex i: Int, reason: String, data: GameData, context: FinanceContext, announce: Bool = true) -> Double {
        guard s.companies[i].status.isLive else { return 0 }
        HeldMoney.settle(&s, companyID: s.companies[i].id)   // the rest of this week's money is the company's to settle with
        let co = s.companies[i]
        let cur = context.homeCurrency(s)
        let assets = max(0, CompanyFigures.assets(co) - co.cash) * 0.45
        let p = co.payables
        let ownLoans = s.loans.filter { $0.companyID == co.id }
        let loanBalance = ownLoans.reduce(0) { $0 + $1.balance }
        var debts: Double = loanBalance + CompanyFigures.billsOwed(co)
        debts -= min(0, co.cash)
        var personalHit = 0.0
        // Secured lenders are paid first from what the company owns; only what is left of a guaranteed loan lands on the owner.
        var pool = assets
        for l in ownLoans {
            guard let li = s.loans.firstIndex(where: { $0.id == l.id }) else { continue }
            if l.isGuaranteed || co.form == .soleTrader {
                let cut = min(pool, l.balance)
                s.loans[li].balance -= cut
                pool -= cut
                s.loans[li].companyID = 0
                s.loans[li].name += " (taken over by you)"
                personalHit += s.loans[li].balance
            } else {
                Banking.close(loanID: l.id, repaid: l.balance * 0.4, state: &s)
            }
        }
        let cashPart = max(0, co.cash)
        var shortfall = max(0, debts - loanBalance - pool - cashPart)
        if co.form == .soleTrader {
            shortfall = max(0, debts - loanBalance - pool - cashPart)
            Ledger.move(&s, .me, -shortfall, why: "Debts of failed \(co.name)")
            personalHit += shortfall
        } else if pool + cashPart > debts - loanBalance {
            let rest = (pool + cashPart) - (debts - loanBalance)
            if rest > 0 && co.ownership > 0 { Payments.playerReceives(&s, rest * co.ownership / 100 * 0.2, label: "Remaining value from \(co.name)") }
        }
        // Staff are released.
        for m in s.companies[i].staff { if var person = s.people[m.id] { person.employerID = 0; s.people[m.id] = person } }
        if let mid = s.companies[i].managerID, var mgr = s.people[mid] { mgr.employerID = 0; s.people[mid] = mgr }
        s.companies[i].staff = []
        s.companies[i].managerID = nil
        EquipmentMarket.endAllLeases(&s, companyIndex: i)   // the lessors take their things back
        s.companies[i].status = .bust
        Ledger.set(&s, .company(co.id), to: 0)
        HoldingModel.holdingFailed(&s, holdingID: co.id)
        guard announce else { return personalHit }
        s.stats.bankruptcies += 1
        s.credit = clamp(s.credit - (co.form == .soleTrader ? 22 : 14), 0, 100)
        s.addMessage(from: co.name, title: "\(co.name) has gone bankrupt", body: why(reason) + liability(personalHit, co.form, cur) + "Credit score hit.", companyID: co.id, tone: "bad")
        s.news("\(co.name) files for bankruptcy.", tone: "bad", companyID: co.id)
        return personalHit
    }

    static func why(_ reason: String) -> String {
        reason == "unpaid" ? "Bills went unpaid for months. " : reason == "insolvent" ? "The regulator closed it: its capital was gone. " : reason == "loan" ? "The bank called its loan after missed instalments. " : "Cash ran out. "
    }
    static func liability(_ personalHit: Double, _ form: LegalForm, _ cur: Currency) -> String {
        personalHit > 0
            ? "About \(cur.display(personalHit)) lands on you personally (\(form == .soleTrader ? "sole proprietors are personally liable" : "guarantees you signed")). "
            : "As a limited company, your loss is limited to what you put in. "
    }

    // MARK: A chain fails as one company

    /// A branch never fails alone. The chain does, by the same rules as any company, judged on all its branches together: the combined account
    /// overdrawn past twice its limit for more than 12 weeks, a called loan not caught up, bills unpaid for months while the chain has no cash,
    /// or (a financial chain) its capital gone.
    public static func chainChecks(_ s: inout GameState, data: GameData, context: FinanceContext, insolvent: Set<Int>) {
        for ch in Chains.all(s) {
            let L = Chains.stores(s, ch)
            guard L.count >= 2 else { continue }
            let cash = L.reduce(0) { $0 + $1.cash }, room = L.reduce(0) { $0 + context.overdraftRoom($1, s) }
            let today = Payday.dayNumber(week: s.week, day: s.day)
            let running = L.filter { $0.status == .open || $0.status == .closed }
            if running.isEmpty { continue }
            var reason: String?
            if ch["neg"].int > 12 && cash < -room * 2 { reason = "cash" }
            else if running.contains(where: { $0.int("loanCall") > 0 && s.week >= $0.int("loanCall") }) { reason = "loan" }
            else if cash < 0 && running.contains(where: { Payday.unpaidForMonths($0, today: today) }) { reason = "unpaid" }
            else if L.contains(where: { insolvent.contains($0.id) }) { reason = "insolvent" }
            if let r = reason { chainBankrupt(&s, chainID: ch["id"].int, reason: r, data: data, context: context) }
        }
    }

    /// Every branch of the chain goes down together under the company failure rules, with one message, one count and one credit hit.
    public static func chainBankrupt(_ s: inout GameState, chainID: Int, reason: String, data: GameData, context: FinanceContext) {
        guard let ch = Chains.chain(s, id: chainID) else { return }
        let L = Chains.stores(s, ch)
        guard let head = L.first else { return }
        var hit = 0.0
        for c in L { if let i = s.companyIndex(c.id) { hit += bankrupt(&s, companyIndex: i, reason: reason, data: data, context: context, announce: false) } }
        let name = ch["name"].string
        s.stats.bankruptcies += 1
        s.credit = clamp(s.credit - (head.form == .soleTrader ? 22 : 14), 0, 100)
        s.addMessage(from: name, title: "\(name) has gone bankrupt", body: why(reason) + "All \(L.count) branches close with the chain. " + liability(hit, head.form, context.homeCurrency(s)) + "Credit score hit.",
                     companyID: head.id, tone: "bad")
        s.news("\(name) files for bankruptcy and closes its \(L.count) branches.", tone: "bad", companyID: head.id)
    }

    /// The bank sells a company at a discount to cover an overdraft. Original: `forcedSale`.
    /// A branch is not sold alone: the bank sells your chain, every branch of it, as the one company it is.
    static func forcedSale(_ s: inout GameState, companyIndex i: Int, data: GameData, context: FinanceContext) {
        let br = s.chainStores(of: s.companies[i])
        if br.count >= 2, let chainID = Optional(s.companies[i].value("chain").int) {
            for c in br { HeldMoney.settle(&s, companyID: c.id) }
            let parts = br.map { c in (c, s.company(c.id).map { jsRound(Valuation.companyValue($0, state: s, trades: data.catalog) * $0.ownership / 100 * 0.6) } ?? 0) }
            let v = parts.reduce(0) { $0 + $1.1 }
            if v <= 0 { chainBankrupt(&s, chainID: chainID, reason: "cash", data: data, context: context); return }
            for (c, _) in parts { if let k = s.companyIndex(c.id) { sellToCreditors(&s, companyIndex: k) } }
            let name = Chains.chain(s, id: chainID)?["name"].string ?? br[0].name
            Ledger.move(&s, .me, v, why: "Forced sale of \(name)")
            s.stats.companiesSold += 1
            s.addMessage(from: "Bank", title: "\(name) was sold by creditors",
                         body: "You could not cover your overdraft. The bank forced a sale of the whole chain (\(br.count) branches) at a discount: \(context.homeCurrency(s).display(v)).",
                         companyID: br[0].id, tone: "bad")
            return
        }
        HeldMoney.settle(&s, companyID: s.companies[i].id)
        let co = s.companies[i]
        let v = jsRound(Valuation.companyValue(co, state: s, trades: data.catalog) * co.ownership / 100 * 0.6)
        if v <= 0 { bankrupt(&s, companyIndex: i, reason: "cash", data: data, context: context); return }
        sellToCreditors(&s, companyIndex: i)
        Ledger.move(&s, .me, v, why: "Forced sale of \(co.name)")
        s.stats.companiesSold += 1
        s.addMessage(from: "Bank", title: "\(co.name) was sold by creditors",
                     body: "You could not cover your overdraft. The bank forced a sale at a discount: \(context.homeCurrency(s).display(v)).",
                     companyID: co.id, tone: "bad")
    }
    /// The company leaves your hands: loans settled from the price, staff released.
    static func sellToCreditors(_ s: inout GameState, companyIndex i: Int) {
        for l in s.loans.filter({ $0.companyID == s.companies[i].id }) { Banking.close(loanID: l.id, repaid: l.balance, state: &s) }
        for m in s.companies[i].staff { if var person = s.people[m.id] { person.employerID = 0; s.people[m.id] = person } }
        s.companies[i].staff = []
        s.companies[i].status = .sold
    }

    /// Sole traders are the same person as their business: spare business cash covers a negative private account.
    /// Original: `coverFromENK`.
    static func coverFromSoleTraders(_ s: inout GameState, context: FinanceContext) {
        if s.cash >= 0 { return }
        var moved = 0.0
        var names: [String] = []
        let order = s.companies.indices.filter { s.companies[$0].form == .soleTrader && [.open, .closed, .setup].contains(s.companies[$0].status) }
            .sorted { s.companies[$0].cash > s.companies[$1].cash }
        for i in order {
            if s.cash >= 0 { break }
            let spare = s.companies[i].cash - context.weeklyCost(s.companies[i], s) * 2
            if spare <= 0 { continue }
            let take = min(spare, -s.cash + (s.overdraftLimit * 0.25).rounded())
            if take <= 0 { continue }
            if Payments.withdrawCash(&s, companyID: s.companies[i].id, amount: take) == .ok { moved += take; names.append(s.companies[i].name) }
        }
        if moved > 0 {
            s.note("Moved \(context.homeCurrency(s).display(moved)) from \(names.joined(separator: ", ")) to your private account to cover a negative balance. As a sole trader it is the same money.", tone: "n")
        }
    }

    /// The end-of-week check: overdraft limit, bank warnings, forced sales, game over. Original: `checkOver`.
    public static func checkOver(_ s: inout GameState, data: GameData, context: FinanceContext, liquidate: (inout GameState, Double) -> Void) {
        TaxSettlement.collectIfRefused(&s, context: context)
        TaxSettlement.refresh(&s, data: data, context: context)
        coverFromSoleTraders(&s, context: context)
        var od = s.rest["flags"]?["od"].int ?? 0
        // While the player is choosing how to pay a tax bill, the bank's clock waits.
        let choosingTaxPayment = s.inbox.contains { $0.status == "open" && $0.actionID == PersonalFinance.dueAction }
        if s.cash < -s.overdraftLimit && choosingTaxPayment {
            // no weeks counted until the answer or its deadline
        } else if s.cash < -s.overdraftLimit {
            od += 1
            if od == 1 {
                s.addMessage(from: "Bank", title: "Overdraft limit exceeded",
                             body: "Your private account is below the limit. Within 8 weeks the bank sells your investments and then forces a sale of a company. Pay yourself a salary or dividend, or put money in.", tone: "bad")
            }
            if od == 5 {
                s.addMessage(from: "Bank", title: "Final warning: forced sale in 3 weeks",
                             body: "Your private account is still below the overdraft limit. Bring it back up or the bank forces a sale.", tone: "bad")
            }
            if od >= 8 {
                liquidate(&s, -s.overdraftLimit * 0.5)
                if s.cash < -s.overdraftLimit {
                    let list = s.companies.indices.filter { s.companies[$0].status.isLive && s.companies[$0].holdingID == 0 }
                        .sorted { Valuation.companyValue(s.companies[$0], state: s, trades: data.catalog) > Valuation.companyValue(s.companies[$1], state: s, trades: data.catalog) }
                    for i in list {
                        if s.cash >= -s.overdraftLimit * 0.5 { break }
                        forcedSale(&s, companyIndex: i, data: data, context: context)
                    }
                }
            }
        } else { od = 0 }
        var flags = s.rest["flags"] ?? .object([:])
        flags["od"] = .number(Double(od))
        s.rest["flags"] = flags
        let nw = Valuation.netWorth(s, trades: data.catalog).total
        let live = s.companies.filter { $0.status.isLive }
        if s.cash < -s.overdraftLimit && od >= 8 && nw <= 0 {
            s.gameOver = .object(["reason": "insolvent", "week": .number(Double(s.week)), "nw": .number(nw)]); return
        }
        if s.cash < -s.overdraftLimit * 3 && live.isEmpty {
            s.gameOver = .object(["reason": "insolvent", "week": .number(Double(s.week)), "nw": .number(nw)]); return
        }
        // Broke means no company and no money to start another: someone still holding cash for a first company (a trade the country bans, a name not yet chosen) is not out of the game.
        let floor = context.homeCurrency(s).scaledPrice(10000)
        if live.isEmpty && nw < floor && Payments.liquid(s) < floor && s.week > 2 {
            s.gameOver = .object(["reason": "broke", "week": .number(Double(s.week)), "nw": .number(nw)])
        }
    }
}
