import Foundation
import GameCore

public enum Receipts {
    static let key = "rcpt"
    static let keep = 200

    public struct Row: Equatable, Sendable, Identifiable {
        public var id: String { number }
        public var number: String
        public var kind: String
        public var title: String
        public var detail: String
        public var amount: Double
        public var week: Int
        public var day: Int
        public var payer: String
    }

    @discardableResult
    public static func add(_ s: inout GameState, receiptCompanyID: Int, number: String, kind: String, title: String, detail: String, amount: Double, payer: String) -> Bool {
        guard let i = s.companyIndex(receiptCompanyID) else { return false }
        var list: [JSONValue] = s.companies[i].value(key).array
        let row: JSONValue = .object(["no": .string(number), "k": .string(kind), "t": .string(title), "d": .string(detail), "a": .number(amount),
                                      "w": .number(Double(s.week)), "dy": .number(Double(s.day)), "p": .string(payer)])
        list.insert(row, at: 0)
        if list.count > keep { list.removeLast(list.count - keep) }
        s.companies[i].set(key, .array(list))
        return true
    }

    public static func rows(_ co: Company) -> [Row] {
        co.value(key).array.map { v in
            Row(number: v["no"].string, kind: v["k"].string, title: v["t"].string, detail: v["d"].string, amount: v["a"].double,
                week: v["w"].int, day: v["dy"].int, payer: v["p"].string)
        }
    }

    public static func reference(prefix: String, year: Int, id: Int) -> String {
        prefix + "-" + String(year) + "-" + String(format: "%05d", id)
    }
}
