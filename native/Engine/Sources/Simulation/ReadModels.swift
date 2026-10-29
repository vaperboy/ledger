import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Investments

/// Read-only views of the state for screens, so the app never reads raw JSON.
public struct Quote: Identifiable, Equatable, Sendable {
    public var id: String { "\(kind.rawValue)-\(symbol)" }
    public var kind: Brokerage.Kind
    public var symbol: String
    public var name: String
    public var sector: String
    public var price: Double
    /// Change over the last week, as a share (nil when there is no history yet).
    public var weekChange: Double?
    public var history: [Double]
    public var quantity: Double
    public var value: Double
    public var costBasis: Double
    public var isDelisted: Bool
}

public struct NewsItem: Identifiable, Equatable, Sendable {
    public var id: Int
    public var week: Int
    public var text: String
    public var tone: String
}

public struct DepositInfo: Identifiable, Equatable, Sendable {
    public var id: Int
    public var balance: Double
    public var rate: Double
    public var weeksLeft: Int
}

public extension GameEngine {
    func quotes(_ kind: Brokerage.Kind) -> [Quote] {
        let inv = state.rest["inv"] ?? .null
        switch kind {
        case .stock, .crypto:
            let book = state.rest[kind == .stock ? "stocks" : "crypto"]?.object ?? [:]
            let held = inv[kind == .stock ? "stocks" : "crypto"]
            return book.keys.sorted().map { sym in
                let q = book[sym]!
                let h = q["h"].array.map { $0.double }
                var week: Double? = nil
                if h.count >= 2, h[h.count - 2] > 0 { week = h[h.count - 1] / h[h.count - 2] - 1 }
                let pos = held[sym]
                return Quote(kind: kind, symbol: sym, name: q["n"].string, sector: q["sec"].string, price: q["p"].double, weekChange: week, history: h,
                             quantity: pos["q"].double, value: Brokerage.positionValue(state, kind, sym), costBasis: pos["cost"].double, isDelisted: q["dead"].bool)
            }
        case .fund:
            let names = ["idx": "Index fund", "bond": "Bond fund", "mm": "Money-market fund"]
            return ["idx", "bond", "mm"].map { k in
                let pos = inv["funds"][k]
                return Quote(kind: .fund, symbol: k, name: names[k] ?? k, sector: "Fund", price: Brokerage.price(state, .fund, k), weekChange: nil, history: [],
                             quantity: pos["q"].double, value: Brokerage.positionValue(state, .fund, k), costBasis: pos["cost"].double, isDelisted: false)
            }
        }
    }

    var news: [NewsItem] {
        (state.rest["news"]?.array ?? []).enumerated().map { NewsItem(id: $0.offset, week: $0.element["w"].int, text: localized($0.element["t"].string), tone: $0.element["tone"].string) }
    }

    var deposits: [DepositInfo] {
        (state.rest["inv"]?["deposits"].array ?? []).enumerated().map {
            DepositInfo(id: $0.offset, balance: $0.element["bal"].double, rate: $0.element["rate"].double, weeksLeft: max(0, $0.element["wEnd"].int - state.week))
        }
    }

    /// Text as the player should read it: `{auth:..}` and `{m:..}` tokens resolved for the company's country (or the home country).
    func localized(_ text: String, companyID: Int = 0) -> String {
        let co = state.company(companyID)
        let cur = co.map { currency(for: $0) } ?? homeCurrency
        return TextTokens.resolve(text, country: cur.country, currency: cur)
    }

    /// Display name of a company's trade ("Café"), falling back to the raw id.
    func tradeName(_ co: Company) -> String { data.catalog[co.type]?.name ?? co.type }
    func cityName(_ co: Company) -> String { data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? co.cityID }
    func currency(for co: Company) -> Currency { context.currency(co.countryCode, state) }

    /// The company's last twelve closed months, oldest first.
    func monthlyProfitSeries(_ co: Company) -> [Double] { co.monthlyHistory.suffix(12).map { $0.profit } }
}
