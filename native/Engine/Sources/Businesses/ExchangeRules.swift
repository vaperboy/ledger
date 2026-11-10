import Foundation
import GameCore
import Countries

public enum ExchangeSide: String, Sendable { case buy, sell }

public struct ExchangeOrder: Equatable, Sendable {
    public var id: Int
    public var instrument: String
    public var trader: String
    public var side: ExchangeSide
    public var shares: Int
    public var limit: Double
    public var seq: Int

    public init(id: Int, instrument: String, trader: String, side: ExchangeSide, shares: Int, limit: Double, seq: Int) {
        self.id = id; self.instrument = instrument; self.trader = trader; self.side = side; self.shares = shares; self.limit = limit; self.seq = seq
    }
}

public struct ExchangeFill: Equatable, Sendable {
    public var buyOrder: Int
    public var sellOrder: Int
    public var buyer: String
    public var seller: String
    public var shares: Int
    public var price: Double
}

public struct AuctionResult: Equatable, Sendable {
    public var price: Double?
    public var volume: Int
    public var fills: [ExchangeFill]
    public var demand: Int
    public var supply: Int
    public static let none = AuctionResult(price: nil, volume: 0, fills: [], demand: 0, supply: 0)
}

public enum ExchangeRules {
    public static let bandShare = 0.25
    public static let ownerFloorPercent = 51
    public static let dayMoveShare = 0.10
    public static let valueStepShare = 0.10
    public static let maxOpenOrders = 20
    public static let holderCapPercent = 20
    public static let serverPositionCap = 200e6
    public static let lockUpDays = 28
    public static let quarterDays = 91
    public static let blackoutBefore = 7
    public static let blackoutAfter = 1
    public static let disclosureDays = 2
    public static let minimumAgeWeeks = 26
    public static let dividendGapDays = 91

    public static func round4(_ x: Double) -> Double { (x * 1e4).rounded() / 1e4 }

    public static func inBand(price: Double, nav: Double, rules: WorldRules = WorldRules.defaults) -> Bool {
        let r: ClosedRange<Double> = rules.exchangeBand
        return price >= nav * r.lowerBound && price <= nav * r.upperBound
    }
    public static func band(nav: Double, rules: WorldRules = WorldRules.defaults) -> (low: Double, high: Double) {
        let r: ClosedRange<Double> = rules.exchangeBand
        return (round4(nav * r.lowerBound), round4(nav * r.upperBound))
    }

    public static func closeBounds(previous: Double, nav: Double, rules: WorldRules = WorldRules.defaults) -> (low: Double, high: Double) {
        let b = band(nav: nav, rules: rules)
        var lo = max(round4(previous * (1 - dayMoveShare)), b.low), hi = min(round4(previous * (1 + dayMoveShare)), b.high)
        if lo > hi { let p = round4(clamp(previous, b.low, b.high)); lo = p; hi = p }
        return (lo, hi)
    }

    public static func ownerFloor(total: Int) -> Int { (total * ownerFloorPercent + 99) / 100 }
    public static func ownerSellable(owned: Int, openSells: Int, total: Int) -> Int { max(0, owned - openSells - ownerFloor(total: total)) }
    public static func holderSellable(owned: Int, openSells: Int) -> Int { max(0, owned - openSells) }
    public static func holderBuyable(owned: Int, openBuys: Int, total: Int) -> Int { max(0, total * holderCapPercent / 100 - owned - openBuys) }
    public static func serverPositionLimit(_ currency: Currency?) -> Double { currency?.scaledPrice(serverPositionCap) ?? serverPositionCap }

    public static func fee(_ amount: Double, currency: Currency?) -> Double { max(currency?.scaledPrice(29) ?? 29, amount * 0.001) }
    public static func minimumOrder(_ currency: Currency?) -> Double { currency?.scaledPrice(100) ?? 100 }

    public enum ListingCheck: Equatable, Sendable { case ok, tooSmall(needed: Double), tooYoung(weeksLeft: Int) }
    public static func listingCheck(value: Double, minimum: Double, ageWeeks: Int) -> ListingCheck {
        if ageWeeks < minimumAgeWeeks { return .tooYoung(weeksLeft: minimumAgeWeeks - ageWeeks) }
        if value < minimum { return .tooSmall(needed: minimum) }
        return .ok
    }

    public static func insiderBlock(listedDay: Int, disclosureDay: Int, today: Int) -> String? {
        let n = today - listedDay
        if n < lockUpDays { return "Lock-up: you cannot sell your own shares for \(lockUpDays - n) more days after the listing." }
        let r = n % quarterDays
        if r >= quarterDays - blackoutBefore { return "Blackout: the results are due in \(quarterDays - r) days, and you cannot sell until they are out." }
        if n >= quarterDays && r <= blackoutAfter { return "Blackout: the results are just out. You can sell again tomorrow." }
        if disclosureDay >= 0, today - disclosureDay <= disclosureDays { return "Blackout: you declared a dividend, and the market needs a few days to take it in." }
        return nil
    }

    public static func nextResultsDay(listedDay: Int, today: Int) -> Int {
        let n = max(0, today - listedDay)
        return listedDay + (n / quarterDays + 1) * quarterDays
    }

    public static func clear(_ orders: [ExchangeOrder], reference: Double, low: Double, high: Double) -> AuctionResult {
        let buys = orders.filter { $0.side == .buy && $0.shares > 0 }, sells = orders.filter { $0.side == .sell && $0.shares > 0 }
        guard !buys.isEmpty, !sells.isEmpty else { return .none }
        var prices = Set<Double>()
        for o in orders where o.limit >= low && o.limit <= high { prices.insert(round4(o.limit)) }
        prices.insert(round4(clamp(reference, low, high)))
        var best: (price: Double, volume: Int, surplus: Int, demand: Int, supply: Int)? = nil
        for p in prices.sorted() {
            let d = buys.reduce(0) { $0 + ($1.limit >= p ? $1.shares : 0) }
            let s = sells.reduce(0) { $0 + ($1.limit <= p ? $1.shares : 0) }
            let v = min(d, s), surplus = abs(d - s)
            guard let b = best else { best = (p, v, surplus, d, s); continue }
            if v > b.volume || (v == b.volume && (surplus < b.surplus || (surplus == b.surplus && abs(p - reference) < abs(b.price - reference)))) {
                best = (p, v, surplus, d, s)
            }
        }
        guard let b = best, b.volume > 0 else { return .none }
        let eligibleBuys = buys.filter { $0.limit >= b.price }.sorted { $0.limit != $1.limit ? $0.limit > $1.limit : $0.seq < $1.seq }
        let eligibleSells = sells.filter { $0.limit <= b.price }.sorted { $0.limit != $1.limit ? $0.limit < $1.limit : $0.seq < $1.seq }
        var left = eligibleSells.map { $0.shares }
        var fills: [ExchangeFill] = []
        var done = 0
        for buy in eligibleBuys {
            var need = buy.shares
            for k in eligibleSells.indices {
                if need == 0 || done >= b.volume { break }
                let sell = eligibleSells[k]
                if left[k] == 0 || sell.trader == buy.trader { continue }
                let q = min(need, left[k], b.volume - done)
                fills.append(ExchangeFill(buyOrder: buy.id, sellOrder: sell.id, buyer: buy.trader, seller: sell.trader, shares: q, price: b.price))
                left[k] -= q; need -= q; done += q
            }
        }
        return AuctionResult(price: b.price, volume: done, fills: fills, demand: b.demand, supply: b.supply)
    }
}
