import Foundation
import GameCore
import Countries
import Finance

/// The other ways to sell: platforms, memberships, referrals, on-call service, add-ons and peak seasons. Original: `weekly`,
/// `ACT.sw33t` and the 'Ways to sell' card in features/sales/trade_sales_mechanics.js. (Contracts and one-off orders are
/// `VolumeContracts`; the demand side of all of them is `DemandModel.applyWaysToSell`, which reads the state kept here.)
///
/// State: the original's `co.sw33` (`on` switches, `mem` members, `ref` referrals, `paidUp`, `peakY`/`peakM`), shared with the
/// volume contracts, so old saves load as they are.
///
/// What each does, every week, from last week's till (the money moves through `Payments`, so the books balance):
///  * platform (on): more customers (demand), and a commission on the part of last week's revenue that the platform brought;
///  * members (on): the member count follows sales and rating, steadier demand; perks cost 2 % of sales. Off: members drift away;
///  * referral: happy customers bring others, in proportion to the rating, while sales last (demand);
///  * emergency (on): a weekly on-call fee, 7 % more customers, and urgent jobs at a premium;
///  * upsell (on): a one-off set-up cost, then extra revenue on every sale, which costs 35 % of itself;
///  * peak: three weeks before the season starts you are told, with how much busier it gets (the extra customers are in the demand).
///
/// The seasonal help a manager brings in ahead of a peak is `ManagerSeasonal.swift`. Not ported: the shortcut to Find workers.
public enum SalesWays {
    public enum Switch: Equatable, Sendable { case changed, notAWay, notSwitchable, notEnoughCash(Double), noCompany }

    /// The ways a player can switch on and off.
    static let switchable: Set<String> = ["platform", "members", "emergency", "upsell"]

    public struct Row: Equatable, Sendable {
        public var kind: String
        public var name: String
        public var isOn: Bool
        public var canSwitch: Bool
        public var detail: String
    }

    static func ways(_ co: Company, _ w: World) -> [Balance.SalesWay] { w.balance.salesWays[co.type] ?? [] }

    // MARK: Reading

    /// The ways this company has, with their state (the 'Ways to sell' card). Contracts and orders are in `VolumeContracts`.
    public static func rows(_ s: GameState, companyID: Int, data: GameData) -> [Row] {
        guard let co = s.company(companyID) else { return [] }
        let w = World(state: s, data: data)
        let cur = w.currency(co)
        let sw = co.value("sw33")
        return ways(co, w).filter { $0.kind != "contract" && $0.kind != "offer" }.map { (way: Balance.SalesWay) -> Row in
            let on = sw["on"][way.kind].bool
            var detail = ""
            switch way.kind {
            case "platform":
                detail = "About \(Int(jsRound((way.options["lift"] ?? 0.2) * 100)))% more customers, \(Int(jsRound((way.options["fee"] ?? 0.2) * 100)))% commission on them"
            case "members":
                detail = (on ? "\(Int(jsRound(sw["mem"].double))) members" : "Not offered") + ", perks cost 2% of sales"
            case "emergency":
                detail = "On call \(cur.display(cur.scaledPrice(2500))) a week, urgent jobs pay half again"
            case "upsell":
                detail = "About \(Int(jsRound((way.options["u"] ?? 0.08) * 100)))% extra per sale" + (sw["paidUp"].bool ? "" : ", set-up \(cur.display(cur.scaledPrice(12000)))")
            case "referral":
                detail = VolumeContracts.ratingFactor(co) < 0.2 ? "Too few happy customers" : "About \(jsRound(sw["ref"].double * 10) / 10) a week"
            case "peak":
                detail = "Busy in months " + way.peakMonths.map { String($0) }.joined(separator: ", ")
            default:
                break
            }
            return Row(kind: way.kind, name: way.name, isOn: on, canSwitch: switchable.contains(way.kind), detail: detail)
        }
    }

    // MARK: Switching

    /// Start or stop a way to sell. The add-ons cost a set-up fee the first time. Original: `ACT.sw33t`.
    @discardableResult
    public static func setOn(_ s: inout GameState, companyID: Int, kind: String, on: Bool, data: GameData) -> Switch {
        guard let i = s.companyIndex(companyID) else { return .noCompany }
        let co = s.companies[i]
        let w = World(state: s, data: data)
        guard let way = ways(co, w).first(where: { $0.kind == kind }) else { return .notAWay }
        guard switchable.contains(kind) else { return .notSwitchable }
        var sw = VolumeContracts.store(co)
        if sw["on"][kind].bool == on { return .changed }
        if on, kind == "upsell", !sw["paidUp"].bool {
            let fee = w.currency(co).scaledPrice(12000)
            if co.cash < fee { return .notEnoughCash(fee) }
            Payments.companyPays(&s, companyID: companyID, amount: fee, category: "oth", label: "Set-up: \(way.name.lowercased())")
            sw["paidUp"] = 1
        }
        var onMap = sw["on"].object
        onMap[kind] = on ? 1 : 0
        sw["on"] = .object(onMap)
        VolumeContracts.addLog(&sw, week: s.week, "\(on ? "Started" : "Stopped"): \(way.name.lowercased()).")
        s.companies[i].set("sw33", sw)
        return .changed
    }

    // MARK: The week

    /// Called for every open company after its week (the till has booked last week's sales). Original: `weekly` (the part before offers).
    static func weekly(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) {
        let co = s.companies[i]
        guard co.status == .open else { return }
        let w = World(state: s, data: data)
        let list = ways(co, w)
        if list.isEmpty { return }
        func way(_ k: String) -> Balance.SalesWay? { list.first { $0.kind == k } }
        var sw = VolumeContracts.store(co)
        let on = sw["on"]
        let lw = co.value("lastW")
        let rev = lw["rev"].double, units = lw["units"].double
        let tk = Pricing.ticket(co, bd, w)
        let rating = VolumeContracts.ratingFactor(co)
        var changed = false
        let id = co.id

        if let pl = way("platform"), on["platform"].bool, rev > 0 {
            let lift = pl.options["lift"] ?? 0.2
            Payments.companyPays(&s, companyID: id, amount: rev * lift / (1 + lift) * (pl.options["fee"] ?? 0.2), category: "oth")
        }
        if way("members") != nil {
            let mem = sw["mem"].double
            if on["members"].bool {
                sw["mem"] = .number(max(0, mem * 0.97 + units * 0.03 * (0.5 + rating)))
                if rev > 0 { Payments.companyPays(&s, companyID: id, amount: rev * 0.02, category: "oth") }
                changed = true
            } else if mem != 0 {
                sw["mem"] = .number(mem * 0.85)
                changed = true
            }
        }
        if way("referral") != nil {
            let ref = sw["ref"].double * 0.75 + units * 0.05 * rating
            if ref != sw["ref"].double { sw["ref"] = .number(ref); changed = true }
        }
        if way("emergency") != nil, on["emergency"].bool {
            Payments.companyPays(&s, companyID: id, amount: w.currency(co).scaledPrice(2500), category: "wages")
            if units > 0 { Payments.companyReceives(&s, companyID: id, amount: jsRound(units * 0.07 * tk * 0.5), category: "rev", label: nil) }
        }
        if let up = way("upsell"), on["upsell"].bool, rev > 0 {
            // Customers only add to the bill when they are happy with the service: the extra follows how well the shop is rated, it is not a given.
            let x = jsRound(rev * (up.options["u"] ?? 0.08) * rating)
            Payments.companyReceives(&s, companyID: id, amount: x, category: "rev", label: nil)
            Payments.companyPays(&s, companyID: id, amount: x * 0.35, category: "cogs")
        }
        // A season of your own: told three weeks ahead, once a year.
        if let pk = way("peak") {
            let ahead = GameCalendar.month(week: s.week + 3) + 1, now = GameCalendar.month(week: s.week) + 1
            let year = GameCalendar.year(week: s.week)
            if pk.peakMonths.contains(ahead), !pk.peakMonths.contains(now), !(sw["peakY"].int == year && sw["peakM"].int == ahead) {
                sw["peakY"] = .number(Double(year)); sw["peakM"] = .number(Double(ahead))
                let boost = Int(jsRound((pk.options["b"] ?? 0.3) * 100))
                let room = lw["util"].double > 0.8 ? " You are already near your limit, so plan for extra hands (seasonal workers are hired under Find workers)." : " You have the room to serve it."
                s.addMessage(from: co.name, title: "\(monthName(ahead)): \(pk.name.lowercased()) is coming",
                             body: "Customers come in waves in \(pk.peakMonths.map { monthName($0) }.joined(separator: " and ")): about \(boost)% more than usual.\(room)",
                             companyID: id, tone: "n")
                changed = true
            }
        }
        // Nothing is written for a company that never used any of this (saves stay as they were).
        if changed || !co.value("sw33").isNull { s.companies[i].set("sw33", sw) }
    }

    static func monthName(_ m: Int) -> String {
        let names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        return names[max(0, min(11, m - 1))]
    }
}
