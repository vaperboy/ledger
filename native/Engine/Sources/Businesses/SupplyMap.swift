import Foundation
import GameCore

// The one map of supplies (supply_map.json): every line a trade buys and the trades that supply it.
public enum SupplyMap {
    public struct LineSpec: Equatable, Sendable {
        public var id: String
        public var name: String
        public var group: String
        public var category: String
        public var suppliers: [String]
        public var local: Bool
        public var lead: Int
        public var terms: Int
        public var critical: Bool
        public var variable: Bool
        public var noCapacity: Bool
        public var delivered: Bool
        public var automatic: Bool
        public var cargo: String?
    }

    // One line a buying trade needs. costShare feeds the cost split, salesShare what an own company can take over.
    public struct Need: Equatable, Sendable {
        public var line: String
        public var costShare: Double?
        public var salesShare: Double?
        public var label: String?
        public var from: [String]?
        public var category: String?
        public var isStock: Bool
    }

    struct Book {
        var groups: [String] = []
        var order: [String] = []
        var lines: [String: LineSpec] = [:]
        var trades: [String: [Need]] = [:]
    }

    static let book: Book = {
        guard let url = Bundle.module.url(forResource: "supply_map", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return Book() }
        return parse(j)
    }()

    static func parse(_ j: JSONValue) -> Book {
        var b = Book()
        b.groups = j["groups"].array.map { $0.string }
        b.order = j["order"].array.map { $0.string }
        for (id, v) in j["lines"].object {
            b.lines[id] = LineSpec(id: id, name: v["name"].string, group: v["group"].string, category: v["category"].string,
                                   suppliers: v["suppliers"].array.map { $0.string }, local: v["local"].bool, lead: v["lead"].int, terms: v["terms"].int,
                                   critical: v["critical"].bool, variable: v["variable"].bool, noCapacity: v["noCapacity"].bool, delivered: v["delivered"].bool,
                                   automatic: v["auto"].bool, cargo: v["cargo"].isNull ? nil : v["cargo"].string)
        }
        let rank: [String: Int] = Dictionary(b.order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })
        for (trade, v) in j["trades"].object {
            let needs: [Need] = v.object.map { (kv: (key: String, value: JSONValue)) -> Need in
                let e: JSONValue = kv.value
                return Need(line: kv.key, costShare: e["o"].isNull ? nil : e["o"].double, salesShare: e["s"].isNull ? nil : e["s"].double,
                     label: e["n"].isNull ? nil : e["n"].string, from: e["from"].isNull ? nil : e["from"].array.map { $0.string },
                     category: e["c"].isNull ? nil : e["c"].string, isStock: e["stock"].bool)
            }
            b.trades[trade] = needs.sorted { (rank[$0.line] ?? 999, $0.line) < (rank[$1.line] ?? 999, $1.line) }
        }
        return b
    }

    public static var groups: [String] { book.groups }
    public static var lineOrder: [String] { book.order }
    public static func line(_ id: String) -> LineSpec? { book.lines[id] }
    public static var allLines: [LineSpec] { book.order.compactMap { book.lines[$0] } }

    // What a trade buys, in the map's line order.
    public static func needs(_ trade: String) -> [Need] { book.trades[trade] ?? [] }
    public static func need(_ trade: String, line: String) -> Need? { needs(trade).first { $0.line == line } }
    public static func stockLine(_ trade: String) -> Need? { needs(trade).first { $0.isStock } }

    // The trades that supply a line to this buyer (the buyer may name its own, like bulk fuel for ships).
    public static func suppliers(line: String, buyer: String?) -> [String] {
        if let b = buyer, let f = need(b, line: line)?.from, !f.isEmpty { return f }
        return SupplyMap.line(line)?.suppliers ?? []
    }

    public static func uses(buyerTrade: String, line: String, supplierTrade: String) -> Bool {
        guard need(buyerTrade, line: line) != nil else { return false }
        return suppliers(line: line, buyer: buyerTrade).contains(supplierTrade)
    }

    // Every (supplier trade, line) pair, including buyer overrides: the rows of the server's supply_trade_lines.
    public static var supplyPairs: [(trade: String, line: String)] {
        var seen = Set<String>()
        var out: [(trade: String, line: String)] = []
        func add(_ t: String, _ l: String) { if seen.insert(t + "|" + l).inserted { out.append((trade: t, line: l)) } }
        for l in allLines where !l.automatic { for t in l.suppliers { add(t, l.id) } }
        for needs in book.trades.values {
            for n in needs { if let spec = SupplyMap.line(n.line), !spec.automatic { for t in n.from ?? [] { add(t, n.line) } } }
        }
        return out.sorted { ($0.trade, $0.line) < ($1.trade, $1.line) }
    }

    public static func linesSupplied(by trade: String) -> [String] {
        let set = Set(supplyPairs.filter { $0.trade == trade }.map { $0.line })
        return book.order.filter { set.contains($0) }
    }

    public static func buyers(of line: String) -> [String] {
        book.trades.filter { (kv: (key: String, value: [Need])) -> Bool in kv.value.contains { (n: Need) -> Bool in n.line == line } }.map { $0.key }.sorted()
    }
}
