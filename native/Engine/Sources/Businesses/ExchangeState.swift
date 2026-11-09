import Foundation
import GameCore

/// A share that trades on the exchange. Kinds: "com" (a raw material, priced by world supply and demand), "srv" (the World Bank and the World Index, priced by the server's market and always
/// open to trade at the close), "own" (a holding of yours that went public) and "ext" (another player's listing, mirrored from the server).
public struct ExchangeInstrument: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: String
    /// Shares in issue.
    public var shares: Int
    /// Value per share as last reported (the price band hangs on it).
    public var nav: Double
    public var close: Double
    public var previousClose: Double
    /// Game day number of the last close (-1: none yet).
    public var closeDay: Int
    public var listedDay: Int
    public var holdingID: Int
    public var volume: Int
    /// Day of the last dividend declaration (-1: none).
    public var dividendDay: Int
    public var dividendPerShare: Double
    public var halted: Bool
    /// Weekly-day closes, oldest first.
    public var history: [Double]

    public var isOwn: Bool { kind == "own" }
    public var isServer: Bool { kind == "srv" || kind == "com" }
    public var isCommodity: Bool { kind == "com" }
    public var change: Double { previousClose > 0 ? close / previousClose - 1 : 0 }
}

public struct ExchangePosition: Equatable, Sendable {
    public var instrument: String
    public var shares: Int
    /// What the shares cost in all, fees included (the basis for the gains tax).
    public var cost: Double
    /// Game day number of the latest purchase (a dividend needs the share held from the day before).
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

/// The player's side of the exchange, kept in `rest["xch"]`.
public struct ExchangeBook: Equatable, Sendable {
    public var instruments: [String: ExchangeInstrument] = [:]
    public var positions: [String: ExchangePosition] = [:]
    public var orders: [ExchangeOpenOrder] = []
    public var nextSeq = 1
    /// Game day number of the last day the exchange ran.
    public var lastRun = -1
    /// Gains realised on the exchange (sales of shares you bought), for the trading board.
    public var realised = 0.0

    public init() {}

    public init(_ s: GameState) {
        let j = s.rest["xch"] ?? .null
        for (k, v) in j["i"].object {
            instruments[k] = ExchangeInstrument(id: k, name: v["n"].string, kind: v["k"].string, shares: v["sh"].int, nav: v["nav"].double, close: v["c"].double,
                                                previousClose: v["pc"].double, closeDay: v["cd"].isNull ? -1 : v["cd"].int, listedDay: v["ld"].int, holdingID: v["h"].int,
                                                volume: v["vol"].int, dividendDay: v["dd"].isNull ? -1 : v["dd"].int, dividendPerShare: v["dps"].double,
                                                halted: v["off"].bool, history: v["hist"].array.map { $0.double })
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
                            "cd": .number(Double(v.closeDay)), "ld": .number(Double(v.listedDay)), "h": .number(Double(v.holdingID)), "vol": .number(Double(v.volume)),
                            "dd": .number(Double(v.dividendDay)), "dps": .number(v.dividendPerShare), "off": .bool(v.halted), "hist": .array(v.history.map { .number($0) })])
        }
        var p: [String: JSONValue] = [:]
        for (k, v) in positions { p[k] = .object(["q": .number(Double(v.shares)), "cost": .number(v.cost), "since": .number(Double(v.since))]) }
        let o: [JSONValue] = orders.map { .object(["id": .number(Double($0.id)), "i": .string($0.instrument), "s": .string($0.side.rawValue), "q": .number(Double($0.shares)),
                                                   "lim": .number($0.limit), "seq": .number(Double($0.seq)), "day": .number(Double($0.day))]) }
        s.rest["xch"] = .object(["i": .object(i), "p": .object(p), "o": .array(o), "seq": .number(Double(nextSeq)), "run": .number(Double(lastRun)), "real": .number(realised)])
    }

    public func openSells(_ instrument: String) -> Int { orders.filter { $0.instrument == instrument && $0.side == .sell }.reduce(0) { $0 + $1.shares } }
    public func openBuys(_ instrument: String) -> Int { orders.filter { $0.instrument == instrument && $0.side == .buy }.reduce(0) { $0 + $1.shares } }
    /// Money promised to open buy orders (at their limits).
    public var committed: Double { orders.filter { $0.side == .buy }.reduce(0) { $0 + Double($1.shares) * $1.limit } }
}
