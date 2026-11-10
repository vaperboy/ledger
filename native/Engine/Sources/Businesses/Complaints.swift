import Foundation
import GameCore
import Countries
import Finance

public enum Complaints {
    public struct Item: Equatable, Sendable {
        public var id: Int
        public var week: Int
        public var who: String
        public var text: String
        public var severity: Int
        public var state: String
        public var calmed: Bool
        public var answeredWeek: Int
        public var answeredBy: String
        public var weeksLeft: Int
        public var refundCost: Double
    }

    public static func list(_ s: GameState, companyID: Int, data: GameData) -> [Item] {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return [] }
        let w = World(state: s, data: data)
        let tk = Pricing.ticket(co, bd, w)
        let cur = w.currency(co)
        return co.value("compl").array.map { c in
            Item(id: c["id"].int, week: c["w"].int, who: c["who"].string, text: c["t"].string, severity: c["sev"].int, state: c["st"].string,
                 calmed: c["ok"].bool, answeredWeek: c["wd"].int, answeredBy: c["by"].string, weeksLeft: max(0, 2 - (s.week - c["w"].int)),
                 refundCost: Satisfaction.refundAmount(ticket: tk, severity: c["sev"].int, cur))
        }
    }

    @discardableResult
    public static func answer(_ s: inout GameState, companyID: Int, complaintID: Int, answer: Satisfaction.Answer, data: GameData) -> Bool? {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type],
              let k = s.companies[i].value("compl").array.firstIndex(where: { $0["id"].int == complaintID && $0["st"].string == "open" }) else { return nil }
        let r = Satisfaction.resolve(&s, i, bd, complaintAt: k, answer, good: nil, data: data)
        return answer == .refund ? true : answer == .ignore ? false : (r ?? false)
    }
}
