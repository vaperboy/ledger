import Foundation
import GameCore

/// Customer invoices as records. Every invoice the simulation raises on a business customer (key accounts one by one, other trade customers
/// as one invoice for the week) is written here when it is raised and closed when the customer pays (Paid) or never does (Written off).
/// Status is derived at read time: Sent until the due week, Overdue after it, Paid, Written off. There is no Draft: the simulation has no step before sending.
/// Payment is recorded when the customer's money arrives in the company account (the ledger row "Customer invoices paid"); the player cannot mark an
/// invoice paid by hand, that would be a made-up receipt.
public enum InvoiceBook {
    public static let keep = 300

    public struct Line: Equatable, Sendable {
        public var description: String
        public var quantity: Double
        public var net: Double
    }

    public struct Record: Equatable, Sendable, Identifiable {
        public var id: String { number }
        public var number: String
        public var issuedWeek: Int
        public var dueWeek: Int
        public var customer: String
        public var gross: Double
        public var tax: Double
        public var lines: [Line]
        /// "sent", "paid" or "bad".
        public var closed: String
        public var paidWeek: Int?
    }

    static func issue(_ co: inout Company, week: Int, customer: String, gross: Double, tax: Double, dueWeek: Int, lines: [Line]) -> String {
        let n = co.int("invN") + 1
        co.set("invN", n)
        let number = "INV-" + String(format: "%04d", n)
        var book = co.value("invb").array
        book.append(.object(["no": .string(number), "w": .number(Double(week)), "due": .number(Double(dueWeek)), "cu": .string(customer), "g": .number(gross), "tax": .number(tax),
                             "ln": .array(lines.map { .object(["d": .string($0.description), "q": .number($0.quantity), "a": .number($0.net)]) }), "st": "draft"]))
        if book.count > keep { book.removeFirst(book.count - keep) }
        co.set("invb", .array(book))
        return number
    }

    /// The invoices raised last week are sent to the customers at the start of the next weekly run (a draft until then).
    static func sendDrafts(_ co: inout Company, week: Int) {
        var book = co.value("invb").array
        var changed = false
        for k in book.indices where book[k]["st"].string == "draft" { book[k]["st"] = "sent"; book[k]["sw"] = .number(Double(week)); changed = true }
        if changed { co.set("invb", .array(book)) }
    }

    /// Send one draft now. Returns false when it is not a draft.
    public static func send(_ co: inout Company, number: String, week: Int) -> Bool {
        var book = co.value("invb").array
        guard let k = book.lastIndex(where: { $0["no"].string == number && $0["st"].string == "draft" }) else { return false }
        book[k]["st"] = "sent"; book[k]["sw"] = .number(Double(week))
        co.set("invb", .array(book))
        return true
    }

    static func close(_ co: inout Company, number: String, paid: Bool, week: Int) {
        guard !number.isEmpty else { return }
        var book = co.value("invb").array
        guard let k = book.lastIndex(where: { $0["no"].string == number }) else { return }
        book[k]["st"] = .string(paid ? "paid" : "bad")
        book[k]["pw"] = .number(Double(week))
        co.set("invb", .array(book))
    }

    public static func records(_ co: Company) -> [Record] {
        co.value("invb").array.map { j in
            Record(number: j["no"].string, issuedWeek: j["w"].int, dueWeek: j["due"].int, customer: j["cu"].string, gross: j["g"].double, tax: j["tax"].double,
                   lines: j["ln"].array.map { Line(description: $0["d"].string, quantity: $0["q"].double, net: $0["a"].double) }, closed: j["st"].string,
                   paidWeek: j["pw"].isNull ? nil : j["pw"].int)
        }
    }
}
