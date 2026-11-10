import Foundation
import GameCore

public struct ExchangeInstrument: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: String
    public var shares: Int
    public var nav: Double
    public var close: Double
    public var previousClose: Double
    public var closeDay: Int
    public var listedDay: Int
    public var companyID: Int
    public var volume: Int
    public var dividendDay: Int
    public var dividendPerShare: Double
    public var halted: Bool
    public var history: [Double]
    public var sentiment: Double = 1

    public var isOwn: Bool { kind == "own" }
    public var isServer: Bool { kind == "srv" || kind == "com" }
    public var isCommodity: Bool { kind == "com" }
    public var change: Double { previousClose > 0 ? close / previousClose - 1 : 0 }
}

public struct ExchangePosition: Equatable, Sendable {
    public var instrument: String
    public var shares: Int
    public var cost: Double
    public var since: Int
}

public struct ExchangeOpenOrder: Equatable, Identifiable, Sendable {
    public var id: Int
    public var instrument: String
    public var side: ExchangeSide
    public var shares: Int
    public var limit: Double
    public var seq: Int
    public var day: Int
}

public struct ExchangeBook: Equatable, Sendable {
    public var instruments: [String: ExchangeInstrument] = [:]
    public var positions: [String: ExchangePosition] = [:]
    public var orders: [ExchangeOpenOrder] = []
    public var nextSeq = 1
    public var lastRun = -1
    public var realised = 0.0

    public init() {}

    public init(_ s: GameState) {
        let j = s.rest["xch"] ?? .null
        for (k, v) in j["i"].object {
            instruments[k] = ExchangeInstrument(id: k, name: v["n"].string, kind: v["k"].string, shares: v["sh"].int, nav: v["nav"].double, close: v["c"].double,
                                                previousClose: v["pc"].double, closeDay: v["cd"].isNull ? -1 : v["cd"].int, listedDay: v["ld"].int, companyID: v["h"].int,
                                                volume: v["vol"].int, dividendDay: v["dd"].isNull ? -1 : v["dd"].int, dividendPerShare: v["dps"].double,
                                                halted: v["off"].bool, history: v["hist"].array.map { $0.double }, sentiment: v["sm"].isNull ? 1 : v["sm"].double)
        }
        for (k, v) in j["p"].object { positions[k] = ExchangePosition(instrument: k, shares: v["q"].int, cost: v["cost"].double, since: v["since"].int) }
        orders = j["o"].array.map { ExchangeOpenOrder(id: $0["id"].int, instrument: $0["i"].string, side: $0["s"].string == "buy" ? .buy : .sell, shares: $0["q"].int,
                                                      limit: $0["lim"].double, seq: $0["seq"].int, day: $0["day"].int) }
        nextSeq = max(1, j["seq"].int)
        lastRun = j["run"].isNull ? -1 : j["run"].int
        realised = j["real"].double
    }

    public func write(to s: inout GameState) {
        var i: [String: JSONValue] = [:]
        for (k, v) in instruments {
            i[k] = .object(["n": .string(v.name), "k": .string(v.kind), "sh": .number(Double(v.shares)), "nav": .number(v.nav), "c": .number(v.close), "pc": .number(v.previousClose),
                            "cd": .number(Double(v.closeDay)), "ld": .number(Double(v.listedDay)), "h": .number(Double(v.companyID)), "vol": .number(Double(v.volume)),
                            "dd": .number(Double(v.dividendDay)), "dps": .number(v.dividendPerShare), "off": .bool(v.halted), "hist": .array(v.history.map { .number($0) }), "sm": .number(v.sentiment)])
        }
        var p: [String: JSONValue] = [:]
        for (k, v) in positions { p[k] = .object(["q": .number(Double(v.shares)), "cost": .number(v.cost), "since": .number(Double(v.since))]) }
        let o: [JSONValue] = orders.map { .object(["id": .number(Double($0.id)), "i": .string($0.instrument), "s": .string($0.side.rawValue), "q": .number(Double($0.shares)),
                                                   "lim": .number($0.limit), "seq": .number(Double($0.seq)), "day": .number(Double($0.day))]) }
        s.rest["xch"] = .object(["i": .object(i), "p": .object(p), "o": .array(o), "seq": .number(Double(nextSeq)), "run": .number(Double(lastRun)), "real": .number(realised)])
    }

    public func openSells(_ instrument: String) -> Int { orders.filter { $0.instrument == instrument && $0.side == .sell }.reduce(0) { $0 + $1.shares } }
    public func openBuys(_ instrument: String) -> Int { orders.filter { $0.instrument == instrument && $0.side == .buy }.reduce(0) { $0 + $1.shares } }
    public var committed: Double { orders.filter { $0.side == .buy }.reduce(0) { $0 + Double($1.shares) * $1.limit } }
}
