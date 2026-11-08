import Foundation
import GameCore
import Countries
import Finance

/// What a manager does on their own in a store: set item prices inside a band around the market price, keep the shelves stocked to the company's stock
/// policy, and run marketing under a monthly ceiling. The owner's order (`ManagerModel.Direction`) picks the band and the ceiling; the budget says whether
/// the manager acts alone at all. A sales director takes over the ads and a marketing manager the prices (`ManagerHeads`). Every action is one plain
/// sentence in the manager's weekly report (`ManagerVoice.record`).
enum ManagerStore {
    /// Weeks between two price reviews and between two marketing reviews of one store.
    static let reviewWeeks = 4
    /// One price step against the market price (0.05 = 5%); the band is one step either side.
    static let priceStep = 0.05
    /// Awareness from which a manager stops buying more of it: a name that is not unknown (the old manager's own bar), or 70 when the owner asked for growth.
    static let steadyKnownEnough = 26.0
    static let knownEnoughGrowing = 70.0
    /// Weekly ad budget (in the base currency) a manager does not go above on their own unless the owner asked for growth.
    static let steadyAdBudget = 1500.0

    static func awarenessGoal(_ co: Company) -> Double { ManagerModel.direction(of: co) == .grow ? knownEnoughGrowing : steadyKnownEnough }

    static func week(_ s: inout GameState, _ ci: Int, manager n: Person, quality q: Double, _ bd: Trade, utilisation util: Double, data: GameData) {
        guard s.companies[ci].status == .open else { return }
        let cur = World(state: s, data: data).currency(s.companies[ci])
        if let spent = StockHandling.managerOrder(&s, ci, bd, manager: n, data: data) {
            let pct = Int(saturating: jsRound((s.companies[ci].inventory - spent) / max(1, StockHandling.policyTarget(s.companies[ci], bd) ?? 1) * 100))
            ManagerVoice.record(&s, companyIndex: ci, "Ordered \(cur.display(spent)) of extra stock because the shelves were at \(pct)% of what the stock policy asks for.")
        }
        let co = s.companies[ci]
        guard ManagerModel.budget(of: co).actsAlone, (s.week + co.id) % reviewWeeks == 0 else { return }
        pricing(&s, ci, by: ManagerHeads.actor(s, co, "mkt", manager: n).tag, data: data)
        marketing(&s, ci, by: ManagerHeads.actor(s, co, "sales", manager: n).tag, bd, utilisation: util, data: data)
    }

    // MARK: Prices

    /// Move every item's price one step towards the band edge the owner's direction calls for. Nothing happens while the owner or a market advisor sets prices.
    static func pricing(_ s: inout GameState, _ ci: Int, by tag: String, data: GameData) {
        let co = s.companies[ci]
        guard case .manager = SalesItems.priceSetter(s, co) else { return }
        let dir = ManagerModel.direction(of: co)
        let target = 1 + Double(dir?.priceSteps ?? 0) * priceStep
        var raised: [String] = [], lowered: [String] = []
        for row in SalesItems.rows(s, companyID: co.id, data: data) where row.marketPrice > 0 && row.discountPercent == 0 {
            guard SalesItems.refusal(s, companyID: co.id, itemID: row.id, data: data) == nil else { continue }
            let now = row.price / row.marketPrice
            guard abs(now - target) > 0.01 else { continue }
            let next = now < target ? min(target, now + priceStep) : max(target, now - priceStep)
            SalesItems.setPrice(&s, companyID: co.id, itemID: row.id, price: row.marketPrice * next, data: data)
            if next > now { raised.append(row.name) } else { lowered.append(row.name) }
        }
        let why = dir?.priceReason ?? "to stay at the market price"
        if !raised.isEmpty { ManagerVoice.record(&s, companyIndex: ci, "Raised the price of \(list(raised)) one step \(why)\(tag).") }
        if !lowered.isEmpty { ManagerVoice.record(&s, companyIndex: ci, "Lowered the price of \(list(lowered)) one step \(why)\(tag).") }
    }

    static func list(_ names: [String]) -> String {
        names.count <= 2 ? names.joined(separator: " and ") : "\(names[0]), \(names[1]) and \(names.count - 2) more"
    }

    // MARK: Marketing

    /// Most a store spends on marketing a week: the direction's share of a month's revenue, spread over the weeks.
    static func weeklyCeiling(_ co: Company) -> Double {
        ManagerModel.recentMonthlyRevenue(co) * marketingShare(co) * 12 / 52
    }
    static func marketingShare(_ co: Company) -> Double { ManagerModel.direction(of: co)?.marketingShare ?? ManagerModel.Direction.steadyMarketingShare }

    /// Raise the store's ad budget one step while it is under the ceiling and people still do not know the place, or bring it back under the ceiling.
    static func marketing(_ s: inout GameState, _ ci: Int, by tag: String, _ bd: Trade, utilisation util: Double, data: GameData) {
        let co = s.companies[ci]
        let ch = bd.audience > 0.5 ? "google" : "meta"
        guard FranchiseStandards.campaignRefusal(co, channel: ch) == nil, !Marketing.runByChain(co, channel: ch, state: s) else { return }
        let cur = World(state: s, data: data).currency(co)
        var mkt = co.value("mkt")
        let others = mkt.object.filter { $0.key != ch }.reduce(0.0) { $0 + $1.value["b"].double }
        let room = weeklyCeiling(co) - others
        let now = mkt[ch]["b"].double
        let steps = ManagerModel.marketingSteps(ch, cur)
        let name = ch == "google" ? "Google" : "Meta"
        let share = Int(saturating: jsRound(marketingShare(co) * 100))
        if now > 0 && now > room {
            // over the ceiling: back to the largest step under it, or off, once the campaign's minimum run is over
            guard Double(s.week) >= (mkt[ch]["lock"].isNull ? 0 : mkt[ch]["lock"].double) else { return }
            if let lower = steps.last(where: { $0 <= room }) {
                mkt[ch]["b"] = .number(lower)
                ManagerVoice.record(&s, companyIndex: ci, "Cut \(name) ads to \(cur.display(lower)) a week to stay under \(share)% of revenue\(tag).")
            } else {
                mkt = Marketing.removing(mkt, ch)
                ManagerVoice.record(&s, companyIndex: ci, "Stopped the \(name) ads to stay under \(share)% of revenue\(tag).")
            }
            s.companies[ci].set("mkt", mkt)
            return
        }
        // Without a growth order the manager stays at one modest campaign: unbounded ads would turn a thinly known, capacity-light trade into a get-rich path.
        let top = ManagerModel.direction(of: co) == .grow ? Double.infinity : cur.scaledPrice(steadyAdBudget)
        guard co.awareness < awarenessGoal(co), util < 0.95, co.cash > ManagerModel.weekCost(s, co, data: data) * 6, let next = steps.first(where: { $0 > now }), next <= room, next <= top else { return }
        if mkt[ch].isNull { mkt[ch] = .object(["b": .number(next), "since": .number(Double(s.week)), "lock": .number(Double(s.week + 4))]) } else { mkt[ch]["b"] = .number(next) }
        s.companies[ci].set("mkt", mkt)
        ManagerVoice.record(&s, companyIndex: ci, "\(now > 0 ? "Raised" : "Started") \(name) ads\(now > 0 ? " to" : " at") \(cur.display(next)) a week because only \(Int(co.awareness))% of people know us and the ceiling is \(share)% of revenue\(tag).")
    }
}
