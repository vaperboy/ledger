import Foundation
import GameCore
import Countries

/// Stocks, crypto and funds: their prices move week by week with the market mood and the economy.
/// Original: `initMarkets`, `marketWeek`, `fundsWeek` (engine/world/economy_markets.js, investing.js).
public enum Markets {
    /// symbol, neutral name, sector, price, volatility, beta, dividend yield. A country file can rename them (flavour.stocks).
    static let stockDefinitions: [(sym: String, name: String, sector: String, price: Double, vol: Double, beta: Double, yield: Double)] = [
        ("NRDK", "Northpower Energy", "Energy", 214, 0.034, 0.9, 0.035),
        ("FJSF", "Bay Seafood Group", "Seafood", 168, 0.04, 1.0, 0.02),
        ("HVBK", "Harbour Bank", "Finance", 122, 0.03, 1.1, 0.045),
        ("STVK", "Steelworks Industries", "Industrial", 86, 0.036, 1.2, 0.03),
        ("TLNR", "Telenet Group", "Telecom", 142, 0.022, 0.5, 0.055),
        ("SKOG", "Forest Owners Group", "Materials", 64, 0.032, 0.9, 0.04),
        ("RETL", "Metro Retail Holding", "Retail", 98, 0.035, 1.0, 0.03),
        ("TECH", "Polar Software", "Tech", 310, 0.05, 1.5, 0.0),
        ("SHIP", "Coastal Shipping", "Shipping", 76, 0.045, 1.3, 0.06),
        ("EIEN", "City Property", "Property", 54, 0.03, 0.8, 0.04),
    ]
    static let cryptoDefinitions: [(sym: String, name: String, price: Double, vol: Double, beta: Double)] = [
        ("BTC", "Bitcoin", 980000, 0.055, 1.0), ("ETH", "Ethereum", 36000, 0.07, 1.2), ("SOL", "Solana", 1700, 0.095, 1.5),
        ("NRC", "NorCoin (small-cap)", 12, 0.14, 1.8), ("MEME", "MemeX (meme coin)", 0.8, 0.22, 2.0),
    ]
    public static let stockSymbols = stockDefinitions.map { $0.sym }
    public static let cryptoSymbols = cryptoDefinitions.map { $0.sym }

    /// Create the markets for a new game. Original: `initMarkets`.
    public static func initialize(_ s: inout GameState, country: Country) {
        let renamed = country.pack["flavour"]["stocks"]
        var stocks: [String: JSONValue] = [:]
        for d in stockDefinitions {
            let p = d.price * s.random.range(0.9, 1.1)
            stocks[d.sym] = .object(["sym": .string(d.sym), "n": .string(renamed[d.sym].isNull ? d.name : renamed[d.sym].string), "sec": .string(d.sector),
                                     "p": .number(p), "vol": .number(d.vol), "beta": .number(d.beta), "dy": .number(d.yield),
                                     "h": .array(Array(repeating: .number(jsRound(p * 100) / 100), count: 52)), "p0": .number(p)])
        }
        var crypto: [String: JSONValue] = [:]
        for d in cryptoDefinitions {
            let p = d.price * s.random.range(0.9, 1.1)
            crypto[d.sym] = .object(["sym": .string(d.sym), "n": .string(d.name), "p": .number(p), "vol": .number(d.vol), "beta": .number(d.beta),
                                     "h": .array(Array(repeating: .number(p), count: 52)), "dead": 0])
        }
        s.rest["stocks"] = .object(stocks)
        s.rest["crypto"] = .object(crypto)
        s.rest["mkt"] = .object(["regime": "bull", "left": 40, "m": 0])
        s.rest["idxRet"] = 0
        s.rest["idx"] = 100
        s.economy.set("salmon", 1.0)
        s.rest["fundPx"] = .object(["idx": 100, "bond": 100, "mm": 100])
        s.rest["inv"] = .object(["stocks": .object([:]), "crypto": .object([:]), "funds": .object([:]), "deposits": .array([])])
    }

    /// Market mood, stock and crypto prices for the week. Original: `marketWeek`.
    public static func weekly(_ s: inout GameState) {
        var M = s.rest["mkt"] ?? .object(["regime": "bull", "left": 40, "m": 0])
        M["left"] = .number(M["left"].double - 1)
        if M["left"].double <= 0 {
            var next: [String: [String]] = [:]
            next["bull"] = ["bull", "correction", "bear"]
            next["correction"] = ["bull", "bear"]
            next["bear"] = ["bull", "recovery"]
            next["recovery"] = ["bull", "bull", "bear"]
            next["crash"] = ["bear", "recovery"]
            let regime = M["regime"].string
            let options = next[regime] ?? ["bull"]
            let r = s.random.chance(0.03) ? "crash" : s.random.pick(options)
            M["regime"] = .string(r)
            M["left"] = .number(Double(r == "crash" ? s.random.int(3, 8) : s.random.int(10, 40)))
            if r == "crash" { s.news("MARKETS PANIC: stocks and crypto plunge.", tone: "bad") }
        }
        let regime = M["regime"].string
        let drifts: [String: Double] = ["bull": 0.0035, "correction": -0.003, "bear": -0.005, "recovery": 0.004, "crash": -0.04]
        let vols: [String: Double] = ["bull": 0.012, "correction": 0.02, "bear": 0.022, "recovery": 0.018, "crash": 0.04]
        let drift = drifts[regime] ?? 0
        let vol = vols[regime] ?? 0.012
        let m = drift + s.random.gauss() * vol + (s.economy.demand - 1) * 0.01
        M["m"] = .number(m)
        s.rest["mkt"] = M
        var total = 0.0, n = 0.0
        var stocks = s.rest["stocks"] ?? .object([:])
        for k in stockSymbols {
            var st = stocks[k]
            if st.isNull { continue }
            var r = st["beta"].double * m + s.random.gauss() * st["vol"].double * 0.4
            if st["sec"].string == "Energy" { r += (s.economy.oil - 1) * 0.004 }
            if st["sec"].string == "Seafood" { r += (s.economy.salmon - 1) * 0.004 }
            if st["sec"].string == "Property" { r += (s.economy.housing - 1) * 0.003 }
            let p = max(1, st["p"].double * (1 + r))
            st["p"] = .number(p)
            var h = st["h"].array
            h.append(.number(jsRound(p * 100) / 100))
            if h.count > 104 { h.removeFirst() }
            st["h"] = .array(h)
            st["divW"] = .number(s.week % 13 == 0 ? p * st["dy"].double / 4 : 0)
            stocks[k] = st
            total += r; n += 1
        }
        s.rest["stocks"] = stocks
        let idxRet = n > 0 ? total / n : 0
        s.rest["idxRet"] = .number(idxRet)
        s.rest["idx"] = .number((s.rest["idx"]?.double ?? 100) * (1 + idxRet))
        var crypto = s.rest["crypto"] ?? .object([:])
        for k in cryptoSymbols {
            var c = crypto[k]
            if c.isNull || c["dead"].bool { continue }
            var r = c["beta"].double * m * 1.8 + s.random.gauss() * c["vol"].double * 0.55 + (regime == "bull" ? 0.002 : 0)
            if k == "MEME" && s.random.chance(0.012) { r += s.random.range(0.2, 1.4) }
            if (k == "MEME" || k == "NRC") && s.random.chance(0.006) {
                r = -s.random.range(0.5, 0.93)
                if s.random.chance(0.25) { c["dead"] = 1; s.news("\(c["n"].string) collapses: rug pull.", tone: "bad") }
            }
            let p = max(0.0001, c["p"].double * (1 + r))
            c["p"] = .number(p)
            var h = c["h"].array
            h.append(.number(p))
            if h.count > 104 { h.removeFirst() }
            c["h"] = .array(h)
            crypto[k] = c
        }
        s.rest["crypto"] = crypto
    }

    /// Index, bond and money-market fund prices. Original: `fundsWeek`.
    public static func fundsWeekly(_ s: inout GameState) {
        var F = s.rest["fundPx"] ?? .object(["idx": 100, "bond": 100, "mm": 100])
        let idxRet = s.rest["idxRet"]?.double ?? 0
        F["idx"] = .number(F["idx"].double * (1 + idxRet - 0.0002))
        let policy = s.economy.policyRate
        F["mm"] = .number(F["mm"].double * (1 + max(0.001, policy - 0.006) / 52))
        let rate0 = s.economy.raw["rate0"].map { $0.isNull ? s.economy.policyRate : $0.double } ?? s.economy.policyRate
        let dr = s.economy.policyRate - rate0
        F["bond"] = .number(F["bond"].double * (1 + (policy + 0.008) / 52 - dr * 6 + s.random.gauss() * 0.0015))
        s.economy.set("rate0", s.economy.policyRate)
        s.rest["fundPx"] = F
    }
}
