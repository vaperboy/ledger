import Foundation
import GameCore

/// Receipts kept in a company's Accounting records. A purchase, a lease or an insurance policy is paid by one company (its own account)
/// while the receipt can be filed with another (the "accounting account" the player picks), so a group can keep its paperwork in one place.
/// A company holds a receipt list (`rcpt`, newest first) only once it has filed one; older saves carry no such key.
public enum Receipts {
    static let key = "rcpt"
    static let keep = 200

    public struct Row: Equatable, Sendable, Identifiable {
        public var id: String { number }
        public var number: String
        /// "order", "lease" or "policy".
        public var kind: String
        public var title: String
        public var detail: String
        public var amount: Double
        public var week: Int
        public var day: Int
        /// The company whose account paid.
        public var payer: String
    }

    /// File a receipt with `receiptCompanyID`. Nothing is filed (and false comes back) when that company does not exist.
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

    /// The receipts filed with this company, newest first.
    public static func rows(_ co: Company) -> [Row] {
        co.value(key).array.map { v in
            Row(number: v["no"].string, kind: v["k"].string, title: v["t"].string, detail: v["d"].string, amount: v["a"].double,
                week: v["w"].int, day: v["dy"].int, payer: v["p"].string)
        }
    }

    /// A reference such as "AS-2027-00412": a prefix, the game year and the record's own id.
    public static func reference(prefix: String, year: Int, id: Int) -> String {
        prefix + "-" + String(year) + "-" + String(format: "%05d", id)
    }
}
