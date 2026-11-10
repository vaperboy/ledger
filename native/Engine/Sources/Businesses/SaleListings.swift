import Foundation
import GameCore

public enum SaleListings {
    public static func canSell(_ s: GameState, companyID: Int) -> Bool {
        guard let co = s.company(companyID) else { return false }
        return (co.status == .open || co.status == .closed) && co.type != "hold" && s.companies.filter { $0.status.isLive }.count > 0
    }
    public static let branchNote = "A branch has no shares of its own: sell it as a going concern or close it from the chain."
    public static func isListed(_ s: GameState, companyID: Int) -> Bool { (s.rest["sales"]?.array ?? []).contains { $0["co"].int == companyID } }

    public static func boardBlock(_ s: GameState, companyID: Int) -> String? {
        guard let co = s.company(companyID) else { return nil }
        let members = co.value("jv")["members"].array
        guard members.contains(where: { $0["id"].string != "me" }) else { return nil }
        if (s.rest["jvgo"]?.int ?? 0) == companyID { return nil }
        return "\(co.name) has partners. It is sold only when a board meeting votes for it."
    }
    public static func isBoardListing(_ s: GameState, companyID: Int) -> Bool {
        (s.rest["sales"]?.array ?? []).contains { $0["co"].int == companyID && $0["jv"].int == 1 }
    }

    public static func routeProblem(_ s: GameState, companyID: Int, route: String, pct: Int, board: Bool = false) -> String? {
        if let co = s.company(companyID), s.isBranch(co) { return branchNote }
        if pct >= 100, !board, let why = boardBlock(s, companyID: companyID) { return why }
        guard let co = s.company(companyID), canSell(s, companyID: companyID) else { return "This company cannot be sold now." }
        if isListed(s, companyID: companyID) { return "It is already on the market." }
        if pct < 100 {
            if co.ownership * Double(pct) / 100 > co.ownership - 1 { return "You must keep at least 1%." }
            if route == "mbo" { return "A management buyout takes the whole company." }
        }
        if route == "mbo", co.managerID == nil || s.people[co.managerID ?? 0] == nil { return "A buyout needs a manager who wants to buy." }
        return nil
    }

    @discardableResult
    public static func start(_ s: inout GameState, companyID: Int, route: String, pct: Int = 100, extra: [String: JSONValue] = [:]) -> Bool {
        guard routeProblem(s, companyID: companyID, route: route, pct: pct, board: extra["jv"] != nil) == nil else { return false }
        var rec: [String: JSONValue] = ["co": .number(Double(companyID)), "m": .string(route), "w0": .number(Double(s.week)), "pct": .number(Double(pct)), "offers": .array([])]
        for (k, v) in extra { rec[k] = v }
        s.rest["sales"] = .array((s.rest["sales"]?.array ?? []) + [.object(rec)])
        return true
    }
}
