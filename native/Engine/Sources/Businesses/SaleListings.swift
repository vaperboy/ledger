import Foundation
import GameCore

/// The one place a company is put on the market. `CompanySale` (Events) runs the offers; the board's "put it up for sale" point and the
/// owner's sale routes both list through here, so there is a single listing per company in `rest["sales"]`.
/// A listing is {co, m (route), w0, pct, offers[]}; routes: "private" (handshake), "broker", "auction" (adds res, rnd, bd) and "mbo".
public enum SaleListings {
    public static func canSell(_ s: GameState, companyID: Int) -> Bool {
        guard let co = s.company(companyID) else { return false }
        return (co.status == .open || co.status == .closed) && co.type != "hold" && s.companies.filter { $0.status.isLive }.count > 0
    }
    public static func isListed(_ s: GameState, companyID: Int) -> Bool { (s.rest["sales"]?.array ?? []).contains { $0["co"].int == companyID } }

    /// Why a route cannot be used for this company (nil when it can).
    public static func routeProblem(_ s: GameState, companyID: Int, route: String, pct: Int) -> String? {
        guard let co = s.company(companyID), canSell(s, companyID: companyID) else { return "This company cannot be sold now." }
        if isListed(s, companyID: companyID) { return "It is already on the market." }
        if pct < 100 {
            if co.form != .limited { return "Only a limited company has shares to sell." }
            if co.ownership * Double(pct) / 100 > co.ownership - 1 { return "You must keep at least 1%." }
            if route == "mbo" { return "A management buyout takes the whole company." }
        }
        if route == "mbo", co.managerID == nil || s.people[co.managerID ?? 0] == nil { return "A buyout needs a manager who wants to buy." }
        return nil
    }

    @discardableResult
    public static func start(_ s: inout GameState, companyID: Int, route: String, pct: Int = 100, extra: [String: JSONValue] = [:]) -> Bool {
        guard routeProblem(s, companyID: companyID, route: route, pct: pct) == nil else { return false }
        var rec: [String: JSONValue] = ["co": .number(Double(companyID)), "m": .string(route), "w0": .number(Double(s.week)), "pct": .number(Double(pct)), "offers": .array([])]
        for (k, v) in extra { rec[k] = v }
        s.rest["sales"] = .array((s.rest["sales"]?.array ?? []) + [.object(rec)])
        return true
    }
}
