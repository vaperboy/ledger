import Foundation
import GameCore

public enum AftermathQueue {
    public struct Item { public var id: Int, companyID: Int, week: Int, kind: String }

    static func cooldownKey(_ kind: String) -> String { "aftc_" + kind }

    @discardableResult
    public static func schedule(_ s: inout GameState, companyID: Int, kind: String, delay: Int) -> Bool {
        guard let i = s.companyIndex(companyID) else { return false }
        var q = s.rest["aft"]?.array ?? []
        if q.contains(where: { $0["co"].int == companyID && $0["k"].string == kind }) { return false }
        if s.companies[i].value("flags")[cooldownKey(kind)].double > Double(s.week) { return false }
        q.append(.object(["id": .number(Double(s.makeID())), "co": .number(Double(companyID)), "w": .number(Double(s.week + max(1, delay))), "k": .string(kind)]))
        s.rest["aft"] = .array(q)
        return true
    }

    public static func pending(_ s: GameState, companyID: Int? = nil) -> [Item] {
        (s.rest["aft"]?.array ?? []).filter { companyID == nil || $0["co"].int == companyID }
            .map { Item(id: $0["id"].int, companyID: $0["co"].int, week: $0["w"].int, kind: $0["k"].string) }
    }

    public static func takeDue(_ s: inout GameState, cooldownWeeks: Int = 12) -> [Item] {
        let q = s.rest["aft"]?.array ?? []
        var keep: [JSONValue] = [], due: [Item] = []
        for x in q {
            if s.week < x["w"].int { keep.append(x); continue }
            let it = Item(id: x["id"].int, companyID: x["co"].int, week: x["w"].int, kind: x["k"].string)
            if let i = s.companyIndex(it.companyID), s.companies[i].status.isLive {
                var flags = s.companies[i].value("flags")
                flags[cooldownKey(it.kind)] = .number(Double(s.week + cooldownWeeks))
                s.companies[i].set("flags", flags)
                due.append(it)
            }
        }
        s.rest["aft"] = .array(keep)
        return due
    }
}
