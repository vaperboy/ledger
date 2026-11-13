import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum Failure {
    @discardableResult
    public static func bankrupt(_ s: inout GameState, companyIndex i: Int, reason: String, data: GameData, context: FinanceContext, announce: Bool = true) -> Double {
        guard s.companies[i].status.isLive else { return 0 }
        HeldMoney.settle(&s, companyID: s.companies[i].id)
        let co = s.companies[i]
        let cur = context.homeCurrency(s)
        let assets = max(0, CompanyFigures.assets(co)) * 0.45
        let p = co.payables
        let ownLoans = s.loans.filter { $0.companyID == co.id }
        let loanBalance = ownLoans.reduce(0) { $0 + $1.balance }
        let borrowedHeld = ClawBack.borrowedStillHeld(s, co)
        let debts: Double = loanBalance + CompanyFigures.billsOwed(co)
        var personalHit = 0.0
        var pool = assets
        var unpaid: [Int: Double] = [:]
        for l in ownLoans {
            let cut = min(pool, l.balance)
            pool -= cut
            unpaid[l.id] = l.balance - cut
        }
        let billsDue = max(0, debts - loanBalance)
        var spare = max(0, pool - billsDue)
        var repaidToLoans = 0.0
        var lendersLost = 0.0
        for l in ownLoans {
            guard let li = s.loans.firstIndex(where: { $0.id == l.id }) else { continue }
            let more = min(unpaid[l.id] ?? 0, spare)
            spare -= more
            let left = (unpaid[l.id] ?? 0) - more
            repaidToLoans += l.balance - left
            if l.isGuaranteed {
                // A loan the owner guaranteed passes to the owner, so its lender loses nothing.
                s.loans[li].balance = left
                s.loans[li].companyID = 0
                s.loans[li].name += " (taken over by you)"
                personalHit += left
                if left < 1 { s.loans.remove(at: li) }
            } else {
                // Limited liability: a lender without a guarantee loses what the company's things do not repay.
                lendersLost += left
                Banking.close(loanID: l.id, repaid: l.balance - left, state: &s)
            }
        }
        let rest = assets - billsDue - repaidToLoans
        let billsLost = max(0, billsDue - max(0, assets - repaidToLoans))
        if rest > 0 && co.ownership > 0 { Payments.playerReceives(&s, rest * co.ownership / 100 * 0.2, label: "Remaining value from \(co.name)") }
        // Money the company handed its owner while insolvent, and borrowed money it still owed, goes back to the creditors who lost out.
        let claw = jsRound(min(max(ClawBack.takenOut(s, co), borrowedHeld), lendersLost + billsLost))
        let back = ClawBack.collect(&s, amount: claw, from: co)
        s.companies[i].set("clawBk", claw)
        s.companies[i].retainedCash = 0
        for m in s.companies[i].staff { if var person = s.people[m.id] { person.employerID = 0; s.people[m.id] = person } }
        if let mid = s.companies[i].managerID, var mgr = s.people[mid] { mgr.employerID = 0; s.people[mid] = mgr }
        s.companies[i].staff = []
        s.companies[i].managerID = nil
        EquipmentMarket.endAllLeases(&s, companyIndex: i)
        s.companies[i].status = .bust
        guard announce else { return personalHit }
        s.stats.bankruptcies += 1
        s.credit = clamp(s.credit - 14, 0, 100)
        Banking.recordBankruptcy(&s)
        s.addMessage(from: co.name, title: "\(co.name) has gone bankrupt",
                     body: why(reason) + liability(personalHit, cur) + clawBackText(claw, owed: back.owed, cur) + "Credit score hit. " + banText,
                     companyID: co.id, tone: "bad")
        s.news("\(co.name) files for bankruptcy.", tone: "bad", companyID: co.id)
        return personalHit
    }

    static func why(_ reason: String) -> String {
        reason == "unpaid" ? "Bills went unpaid for months. " : reason == "insolvent" ? "The regulator closed it: its capital was gone. " : reason == "loan" ? "The bank called its loan after missed instalments. "
            : reason == "filed" ? "You filed for bankruptcy: it owed more than it had. " : "Cash ran out. "
    }
    static func liability(_ personalHit: Double, _ cur: Currency) -> String {
        personalHit > 0
            ? "About \(cur.display(personalHit)) lands on you personally (guarantees you signed). "
            : "As a limited company, your loss is limited to what you put in. "
    }
    static func clawBackText(_ claw: Double, owed: Double, _ cur: Currency) -> String {
        guard claw >= 1 else { return "" }
        let rest = owed >= 1 ? "\(cur.display(owed)) of it you could not pay now becomes a debt you repay monthly. " : ""
        return "\(cur.display(claw)) it brought into your account while it could not pay its debts is taken back for its lenders. " + rest
    }
    static let banText = "No new bank loans for two years."

    public static func chainChecks(_ s: inout GameState, data: GameData, context: FinanceContext, insolvent: Set<Int>) {
        for ch in Chains.all(s) {
            let L = Chains.stores(s, ch)
            guard L.count >= 2 else { continue }
            let today = Payday.dayNumber(week: s.week, day: s.day)
            let running = L.filter { $0.status == .open || $0.status == .closed }
            if running.isEmpty { continue }
            var reason: String?
            if running.contains(where: { $0.int("loanCall") > 0 && s.week >= $0.int("loanCall") }) { reason = "loan" }
            else if s.cash < 0 && running.contains(where: { Payday.unpaidForMonths($0, today: today) }) { reason = "unpaid" }
            else if L.contains(where: { insolvent.contains($0.id) }) { reason = "insolvent" }
            if let r = reason { chainBankrupt(&s, chainID: ch["id"].int, reason: r, data: data, context: context) }
        }
    }

    public static func chainBankrupt(_ s: inout GameState, chainID: Int, reason: String, data: GameData, context: FinanceContext) {
        guard let ch = Chains.chain(s, id: chainID) else { return }
        let L = Chains.stores(s, ch)
        guard let head = L.first else { return }
        var hit = 0.0
        for c in L { if let i = s.companyIndex(c.id) { hit += bankrupt(&s, companyIndex: i, reason: reason, data: data, context: context, announce: false) } }
        let name = ch["name"].string
        s.stats.bankruptcies += 1
        s.credit = clamp(s.credit - 14, 0, 100)
        Banking.recordBankruptcy(&s)
        let claw = L.reduce(0.0) { $0 + (s.company($1.id)?.num("clawBk") ?? 0) }
        let cur = context.homeCurrency(s)
        s.addMessage(from: name, title: "\(name) has gone bankrupt",
                     body: why(reason) + "All \(L.count) branches close with the chain. " + liability(hit, cur) + clawBackText(claw, owed: 0, cur) + "Credit score hit. " + banText,
                     companyID: head.id, tone: "bad")
        s.news("\(name) files for bankruptcy and closes its \(L.count) branches.", tone: "bad", companyID: head.id)
    }

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
    static func sellToCreditors(_ s: inout GameState, companyIndex i: Int) {
        for l in s.loans.filter({ $0.companyID == s.companies[i].id }) { Banking.close(loanID: l.id, repaid: l.balance, state: &s) }
        for m in s.companies[i].staff { if var person = s.people[m.id] { person.employerID = 0; s.people[m.id] = person } }
        s.companies[i].staff = []
        s.companies[i].status = .sold
    }

    public static func checkOver(_ s: inout GameState, data: GameData, context: FinanceContext, liquidate: (inout GameState, Double) -> Void) {
        PersonalFinance.withholdNow(&s, context: context)
        TaxSettlement.collectIfRefused(&s, context: context)
        TaxSettlement.refresh(&s, data: data, context: context)
        CreditorPressure.weekly(&s, data: data)
        var od = s.rest["flags"]?["od"].int ?? 0
        let choosingTaxPayment = s.inbox.contains { $0.status == "open" && $0.actionID == PersonalFinance.dueAction }
        if s.cash < -s.overdraftLimit && choosingTaxPayment {
        } else if s.cash < -s.overdraftLimit {
            od += 1
            if od == 1 {
                s.addMessage(from: "Bank", title: "Overdraft limit exceeded",
                             body: "Your account is below the limit. Within 8 weeks the bank sells your investments and then forces a sale of a company. Pay yourself a salary or dividend, or put money in.", tone: "bad")
            }
            if od == 5 {
                s.addMessage(from: "Bank", title: "Final warning: forced sale in 3 weeks",
                             body: "Your account is still below the overdraft limit. Bring it back up or the bank forces a sale.", tone: "bad")
            }
            if od >= 8 {
                liquidate(&s, -s.overdraftLimit * 0.5)
                if s.cash < -s.overdraftLimit {
                    let list = s.companies.indices.filter { s.companies[$0].status.isLive}
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
        let floor = context.homeCurrency(s).scaledPrice(10000)
        if live.isEmpty && nw < floor && Payments.liquid(s) < floor && s.week > 2 {
            s.gameOver = .object(["reason": "broke", "week": .number(Double(s.week)), "nw": .number(nw)])
        }
    }
}
