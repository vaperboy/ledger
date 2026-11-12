import Foundation
import GameCore
import Countries
import Finance

public struct OnlineSettlement: Equatable, Sendable {
    public var id: String
    public var amount: Double
    public var currency: String
    public var kind: String
    public var label: String
    public var companyKey: String?
    public var units: Int?
    public var unitPrice: Double?
    public var meta: JSONValue

    public init(id: String, amount: Double, currency: String, kind: String, label: String = "", companyKey: String? = nil, units: Int? = nil, unitPrice: Double? = nil,
                meta: JSONValue = .null) {
        self.id = id; self.amount = amount; self.currency = currency; self.kind = kind; self.label = label
        self.companyKey = companyKey; self.units = units; self.unitPrice = unitPrice; self.meta = meta
    }
}

public enum OnlineSettlements {
    static let memory = 600

    public static func companyID(fromKey key: String?) -> Int? {
        guard let key, key.hasPrefix("own.") else { return nil }
        return Int(key.dropFirst(4))
    }

    public static func isBooked(_ s: GameState, id: String) -> Bool {
        (s.rest["online"] ?? .null)["booked"].array.contains { (v: JSONValue) -> Bool in v.string == id }
    }

    // Lets a later module book kinds it owns; it gets the amount in game money and returns true when it took the item.
    public typealias Handler = (inout GameState, OnlineSettlement, Double) -> Bool

    @discardableResult
    public static func book(_ s: inout GameState, _ items: [OnlineSettlement], data: GameData, handler: Handler? = nil) -> [String] {
        var booked: [JSONValue] = (s.rest["online"] ?? .null)["booked"].array
        var seen: Set<String> = Set(booked.map { (v: JSONValue) -> String in v.string })
        var done: [String] = []
        for item in items {
            if !seen.contains(item.id) {
                bookOne(&s, item, data: data, handler: handler)
                booked.append(.string(item.id))
                seen.insert(item.id)
            }
            done.append(item.id)
        }
        if booked.count > memory { booked.removeFirst(booked.count - memory) }
        var online: JSONValue = s.rest["online"] ?? .null
        online["booked"] = .array(booked)
        s.rest["online"] = online
        return done
    }

    static func rate(_ currency: String, _ s: GameState, _ data: GameData) -> Double {
        let country: Country = data.countries.countries.first { (c: Country) -> Bool in c.currencyCode == currency }
            ?? data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode)
        return Currency(country: country, rates: ExchangeRates(drift: s.exchangeRates.values)).rate
    }

    private static func bookOne(_ s: inout GameState, _ item: OnlineSettlement, data: GameData, handler: Handler?) {
        let fx: Double = rate(item.currency, s, data)
        let amount: Double = item.amount * fx
        if let handler, handler(&s, item, amount) { return }
        let company: Int? = companyID(fromKey: item.companyKey).flatMap { (id: Int) -> Int? in s.company(id)?.status == .open ? id : nil }
        if item.kind.hasPrefix("market_") {
            MarketSettlements.book(&s, item, amount: amount, data: data)
            return
        }
        if item.kind == "supply_notice" {
            s.addMessage(kind: "info", from: "Supply", title: "A buyer chose you", body: item.label, companyID: company ?? 0, tone: "good")
            return
        }
        guard amount.isFinite, amount != 0 else { return }
        switch item.kind {
        case "supply_purchase":
            return
        case "supply_sale":
            if let company, let units = item.units, units > 0 {
                let price: Double = (item.unitPrice ?? item.amount / Double(units)) * fx
                SupplyMarketBooks.bookSaleToPlayer(&s, supplierCompanyID: company, units: units, unitPrice: price, unitCost: price * SupplyMarketBooks.standInCostShare)
                return
            }
        case "supply_end_fee":
            if let company {
                let label: String = item.label.isEmpty ? "Fee for ending a supply deal" : item.label
                if amount > 0 {
                    Payments.companyReceives(&s, companyID: company, amount: amount, category: "oth", label: label)
                } else {
                    Payments.companyPays(&s, companyID: company, amount: -amount, category: "oth", label: label)
                }
                return
            }
        default:
            break
        }
        Ledger.move(&s, .me, amount, why: item.label.isEmpty ? "Online" : item.label)
    }
}
