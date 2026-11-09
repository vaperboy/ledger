import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Startups funded by other players, on the player's books. The rules are `CrowdStartupRules`; this moves the money and every move goes through
/// `Ledger`, so `Ledger.gaps` stays empty. Escrow is the server's: money paid in leaves the investor at once and reaches the startup only at a milestone.
/// A founder's own startup is a real company made by `Startups.found`; released money and the investors' shares land on it.
public enum CrowdStartups {
    public static let me = "me"

    public enum FoundOutcome { case ok(CrowdStartupRules.Startup), refused(String) }

    /// What founding costs in the player's money: the entry cost, the founder's own money and the registration, and the plan that results.
    public struct FoundQuote: Equatable {
        public var entryCost: Double
        public var founderPutIn: Double
        public var registration: Double
        public var plan: CrowdStartupRules.Plan
        public var total: Double { entryCost + founderPutIn + registration }
    }

    public static func foundQuote(_ s: GameState, sector: String, who: String, seedMultiple: Double, planFactor: Double, context fc: FinanceContext) -> FoundQuote? {
        guard let p = Startups.plan(s, sector: sector, who: who, seedMultiple: seedMultiple, context: fc), CrowdStartupRules.planFactors.contains(planFactor) else { return nil }
        let cur = fc.homeCurrency(s)
        let c = fc.homeCountry(s)
        let plan = CrowdStartupRules.Plan(cost: p.seed * planFactor, founderPutIn: p.seed)
        return FoundQuote(entryCost: cur.scaledPrice(CrowdStartupRules.entryCostReference), founderPutIn: p.seed, registration: c.registrationFee, plan: plan)
    }

    /// Found a startup that other players can fund: the entry cost leaves for good, the founder's money goes into the new company, and the
    /// plan is listed for investors. Refused for new accounts, a plan with too little of the founder's own money, or too little cash.
    public static func found(_ s: inout GameState, name: String?, sector: String, product: String, model: String, who: String, seedMultiple: Double, planFactor: Double,
                             pitch: String, accountWeeks: Int, today: Int, data: GameData, context fc: FinanceContext) -> FoundOutcome {
        if accountWeeks < CrowdStartupRules.minAccountWeeks { return .refused(CrowdStartupRules.Refusal.newAccount(weeksLeft: CrowdStartupRules.minAccountWeeks - accountWeeks).message) }
        guard let q = foundQuote(s, sector: sector, who: who, seedMultiple: seedMultiple, planFactor: planFactor, context: fc), q.plan.valid else { return .refused("That plan is not allowed: you put in at least a third of it yourself.") }
        if Payments.liquid(s) < q.total { return .refused("You need \(Int(q.total.rounded())) in cash: the entry cost, your own money and the registration.") }
        switch Startups.found(&s, name: name, sector: sector, product: product, model: model, who: who, seedMultiple: seedMultiple, data: data, context: fc) {
        case .ok(let id):
            Payments.transferFromSavings(&s, need: q.entryCost)
            Payments.playerPays(&s, q.entryCost, label: "Startup entry cost", companyID: id)
            let rec = Startups.founded(s, id: id)
            let st = CrowdStartupRules.Startup(id: "S\(id)", name: s.company(id)?.name ?? "Startup", trade: rec?.sectorName ?? sector, pitch: pitch, founderID: me, founderName: "You", founderLinkKey: me,
                                               founderExits: Funding.record(s).exits, founderFails: Funding.record(s).fails, plan: q.plan, createdDay: today, companyID: id)
            return .ok(st)
        case .notEnoughMoney(let n): return .refused("You need \(Int(n.rounded())) more in cash.")
        case .unknownSector: return .refused("That sector is not available.")
        }
    }

    // MARK: Investing

    public enum InvestOutcome { case ok(CrowdStartupRules.Quote, CrowdStartupRules.Holding), refused(String) }

    /// The player puts money into a startup's open stage. The money goes into escrow; the shares are owned at once but locked.
    public static func invest(_ s: inout GameState, startup st: inout CrowdStartupRules.Startup, linkKeys: Set<String>, accountWeeks: Int, amount: Double, today: Int) -> InvestOutcome {
        let amt = jsRound(amount)
        switch CrowdStartupRules.investCheck(st, investorID: me, linkKeys: linkKeys, accountWeeks: accountWeeks, amount: amt, today: today) {
        case .refused(let r): return .refused(r.message)
        case .ok(let q):
            if Payments.liquid(s) < amt { return .refused("You do not have that much in cash.") }
            Payments.transferFromSavings(&s, need: amt)
            Payments.playerPays(&s, amt, label: "Invested in \(st.name) (held until \(q.releasedAtMilestone.lowercased()))")
            st.investments.append(.init(id: "\(st.id)-\(st.investments.count)", investorID: me, linkKey: linkKeys.first ?? me, stage: q.stage, amount: amt, percent: q.percent, day: today))
            return .ok(q, CrowdStartupRules.Holding(startupID: st.id, ownerID: me, linkKey: linkKeys.first ?? me, percent: q.percent, paid: amt, boughtDay: today))
        }
    }

    /// Adds a purchase to the player's holdings (one per startup; the lock restarts from the latest purchase).
    public static func add(_ h: CrowdStartupRules.Holding, to list: inout [CrowdStartupRules.Holding]) {
        if let i = list.firstIndex(where: { $0.startupID == h.startupID && $0.ownerID == h.ownerID }) {
            list[i].percent += h.percent; list[i].paid += h.paid; list[i].boughtDay = max(list[i].boughtDay, h.boughtDay)
        } else { list.append(h) }
    }

    // MARK: Milestones and failure

    /// A milestone is reached: the stage's escrow goes to the startup. When the startup is the player's company, the money lands in its cash and the
    /// investors' shares are issued on its cap table. Returns the amount released.
    @discardableResult
    public static func reachMilestone(_ s: inout GameState, startup st: inout CrowdStartupRules.Startup, today: Int) -> Double {
        let stage = st.milestones
        let released = CrowdStartupRules.reachMilestone(&st, today: today)
        guard released > 0, let cid = st.companyID, let i = s.companyIndex(cid) else { return released }
        let pct = st.investments.filter { $0.stage == stage && $0.released }.reduce(0.0) { $0 + $1.percent }
        Ledger.moveRaw(&s, .company(cid), released)
        s.companies[i].addTransaction(week: s.week, amount: released, label: "Investors' money released: \(CrowdStartupRules.stageNames[stage].lowercased())")
        let total = CapTable.table(s.companies[i]).total
        CapTable.issue(&s, i, newShares: CapTable.sharesForPercent(min(pct, 49), total: total), to: "Crowd investors (\(CrowdStartupRules.stageNames[stage].lowercased()))", paid: released)
        let own = s.companies[i].ownership
        Startups.edit(&s, cid) { $0["pct"] = .number(own) }
        s.note("\(CrowdStartupRules.milestoneNames[stage]): \(Int(released.rounded())) of investors' money is released to \(st.name).", tone: "good", companyID: cid)
        return released
    }

    /// Pays back what the startup's failure returns from escrow to the player.
    public static func settleRefunds(_ s: inout GameState, _ back: [(investorID: String, amount: Double)], startupName: String) {
        for b in back where b.investorID == me && b.amount > 0 {
            Payments.playerReceives(&s, b.amount, label: "Escrow returned: \(startupName)")
        }
    }

    // MARK: Secondary sales

    /// The player buys shares from another holder at a price inside the band; the transfer tax is paid on top and leaves the economy.
    public static func buy(_ s: inout GameState, startup st: CrowdStartupRules.Startup, from seller: CrowdStartupRules.Holding, percent: Double, price: Double, accountWeeks: Int,
                           linkKeys: Set<String>, gainsRate: Double, today: Int) -> Result<(CrowdStartupRules.SaleQuote, CrowdStartupRules.Holding), SaleFailure> {
        switch CrowdStartupRules.saleCheck(st, holding: seller, percent: percent, price: price, buyerID: me, buyerLinkKeys: linkKeys, buyerAccountWeeks: accountWeeks, gainsRate: gainsRate, today: today) {
        case .refused(let r): return .failure(SaleFailure(message: r.message))
        case .ok(let q):
            if Payments.liquid(s) < q.buyerPays { return .failure(SaleFailure(message: "You do not have that much in cash.")) }
            Payments.transferFromSavings(&s, need: q.buyerPays)
            Payments.playerPays(&s, q.price, label: "Bought \(String(format: "%.1f", percent))% of \(st.name)")
            Payments.playerPays(&s, q.transferTax, label: "Transfer tax: \(st.name)")
            return .success((q, CrowdStartupRules.Holding(startupID: st.id, ownerID: me, linkKey: linkKeys.first ?? me, percent: percent, paid: q.price, boughtDay: today)))
        }
    }

    /// The player sells shares to a buyer: the price comes in, the gains tax is withheld on a gain.
    public static func sell(_ s: inout GameState, startup st: CrowdStartupRules.Startup, holding: inout CrowdStartupRules.Holding, percent: Double, price: Double, buyerID: String,
                            buyerLinkKeys: Set<String>, buyerAccountWeeks: Int, gainsRate: Double, today: Int) -> Result<CrowdStartupRules.SaleQuote, SaleFailure> {
        switch CrowdStartupRules.saleCheck(st, holding: holding, percent: percent, price: price, buyerID: buyerID, buyerLinkKeys: buyerLinkKeys, buyerAccountWeeks: buyerAccountWeeks, gainsRate: gainsRate, today: today) {
        case .refused(let r): return .failure(SaleFailure(message: r.message))
        case .ok(let q):
            let basis = holding.paid * percent / max(holding.percent, 1e-9)
            Payments.playerReceives(&s, q.price, label: "Sold \(String(format: "%.1f", percent))% of \(st.name)")
            if q.gainsTax > 0 { Payments.playerPays(&s, q.gainsTax, label: "Tax on gains: \(st.name)") }
            holding.percent -= percent
            holding.paid -= basis
            return .success(q)
        }
    }

    public struct SaleFailure: Error, Equatable { public var message: String }

    // MARK: Progress of the player's own startup

    /// How far the player's own startup company has come, by what is true in its books: launched (opened), selling (first sales), covering its costs (first profit).
    public struct Progress: Equatable {
        public var milestones: Int
        public var assets: Double
        public var weeklyProfit: Double
        public var alive: Bool
    }

    public static func progress(_ s: GameState, companyID: Int) -> Progress? {
        guard let f = Startups.founded(s, id: companyID) else { return nil }
        let revenue = f.product?.revenueWeekly ?? 0
        let profit = revenue - f.burn
        let reached = f.product?.phase == "live" ? (revenue > 0 ? (profit > 0 ? 3 : 2) : 1) : 0
        return Progress(milestones: reached, assets: f.cash, weeklyProfit: profit, alive: f.live)
    }
}
