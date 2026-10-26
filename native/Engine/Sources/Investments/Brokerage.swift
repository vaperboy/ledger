import Foundation
import GameCore
import Countries
import Finance

/// Buying and selling investments, savings and fixed deposits. Original: `buyAsset`, `sellAsset`, `saveMove`,
/// `openDeposit`, `investWeek` (engine/world/investing.js).
public enum Brokerage {
    public enum Kind: String, Sendable { case stock, crypto, fund }
    public enum BuyResult: Equatable, Sendable { case ok, tooSmall, notEnoughCash, delisted }

    /// The broker's fee: 0.1 % with a minimum, and the smallest purchase. Both minimums are in the reference economy's prices; a currency
    /// scales them to the country's price level (`Currency.scaledPrice`). Without one (`nil`) they stay 29 and 100.
    static func brokerFee(_ v: Double, currency: Currency? = nil) -> Double { max(currency?.scaledPrice(29) ?? 29, v * 0.001) }
    static func minimumPurchase(_ currency: Currency?) -> Double { currency?.scaledPrice(100) ?? 100 }

    static func bagKey(_ k: Kind) -> String { k == .stock ? "stocks" : k == .crypto ? "crypto" : "funds" }

    public static func price(_ s: GameState, _ kind: Kind, _ sym: String) -> Double {
        switch kind {
        case .stock: return s.rest["stocks"]?[sym]["p"].double ?? 0
        case .crypto: return s.rest["crypto"]?[sym]["p"].double ?? 0
        case .fund: return s.rest["fundPx"]?[sym].isNull == false ? s.rest["fundPx"]![sym].double : 100
        }
    }

    public static func buy(_ s: inout GameState, _ kind: Kind, _ sym: String, amount: Double, currency: Currency? = nil) -> BuyResult {
        let amt = jsRound(amount)
        if amt < minimumPurchase(currency) { return .tooSmall }
        let px = kind == .crypto ? price(s, kind, sym) * 1.008 : price(s, kind, sym)
        let fee = kind == .crypto ? amt * 0.004 : brokerFee(amt, currency: currency)
        if s.cash < amt + fee {
            if Payments.liquid(s) < amt + fee { return .notEnoughCash }
            Payments.transferFromSavings(&s, need: amt + fee)
        }
        if kind == .crypto && s.rest["crypto"]?[sym]["dead"].bool == true { return .delisted }
        Ledger.move(&s, .me, -(amt + fee), why: "Bought \(sym)")
        var inv = s.rest["inv"] ?? .object([:])
        var bag = inv[bagKey(kind)]
        var pos = bag[sym].isNull ? JSONValue.object(["q": 0, "cost": 0]) : bag[sym]
        pos["q"] = .number(pos["q"].double + amt / px)
        pos["cost"] = .number(pos["cost"].double + amt + fee)   // the buy fee is part of the cost base, so a round trip is not taxed as a gain
        bag[sym] = pos
        inv[bagKey(kind)] = bag
        s.rest["inv"] = inv
        return .ok
    }

    /// Sell a share (0...1) of a holding; returns the sale value. Gains are taxed at the year end.
    @discardableResult
    public static func sell(_ s: inout GameState, _ kind: Kind, _ sym: String, fraction frac: Double, currency: Currency? = nil) -> Double {
        var inv = s.rest["inv"] ?? .object([:])
        var bag = inv[bagKey(kind)]
        var pos = bag[sym]
        if pos.isNull || pos["q"].double <= 0 { return 0 }
        let px = kind == .crypto ? price(s, kind, sym) * 0.992 : price(s, kind, sym)
        let f = clamp(frac, 0, 1)
        let q = pos["q"].double * f
        let v = q * px
        let cost = pos["cost"].double * f
        let fee = kind == .crypto ? v * 0.004 : brokerFee(v, currency: currency)
        pos["q"] = .number(pos["q"].double - q)
        pos["cost"] = .number(pos["cost"].double - cost)
        if pos["q"].double < 1e-9 { var o = bag.object; o.removeValue(forKey: sym); bag = .object(o) } else { bag[sym] = pos }
        inv[bagKey(kind)] = bag
        s.rest["inv"] = inv
        Ledger.move(&s, .me, v - fee, why: "Sold \(sym)")
        s.tax.gains += v - fee - cost
        return v
    }

    public static func positionValue(_ s: GameState, _ kind: Kind, _ sym: String) -> Double {
        let p = s.rest["inv"]?[bagKey(kind)][sym] ?? .null
        return p.isNull ? 0 : p["q"].double * price(s, kind, sym)
    }

    /// Move money to (positive) or from (negative) savings. Original: `saveMove`.
    public static func moveToSavings(_ s: inout GameState, _ amount: Double) -> Bool {
        let amt = jsRound(amount)
        if amt > 0 {
            if s.cash < amt { return false }
            Ledger.move(&s, .me, -amt, why: "To savings")
            s.savings += amt
        } else {
            if s.savings < -amt { return false }
            s.savings += amt
            Ledger.move(&s, .me, -amt, why: "From savings")
        }
        return true
    }

    /// A fixed deposit pays more the longer it is locked. Original: `openDeposit`.
    public static func openDeposit(_ s: inout GameState, amount: Double, weeks: Int) -> Bool {
        if s.cash < amount { return false }
        let rate = max(0.01, s.economy.policyRate - 0.002 + Double(weeks) / 52 * 0.004)
        Ledger.move(&s, .me, -amount, why: "Fixed deposit opened")
        var inv = s.rest["inv"] ?? .object([:])
        var deposits = inv["deposits"].array
        deposits.append(.object(["id": .number(Double(s.makeID())), "bal": .number(amount), "rate": .number(rate), "wEnd": .number(Double(s.week + weeks)), "w0": .number(Double(s.week))]))
        inv["deposits"] = .array(deposits)
        s.rest["inv"] = inv
        return true
    }

    /// Dividends each quarter, deposits maturing. Original: `investWeek`.
    public static func weekly(_ s: inout GameState) {
        var inv = s.rest["inv"] ?? .object([:])
        if s.week % 13 == 0 {
            for (sym, pos) in inv["stocks"].object.sorted(by: { $0.key < $1.key }) {
                let st = s.rest["stocks"]?[sym] ?? .null
                let d = pos["q"].double * st["p"].double * st["dy"].double / 4
                if d > 0 {
                    Ledger.move(&s, .me, d, why: "Dividend \(sym)")
                    s.tax.dividends += d
                }
            }
        }
        var kept: [JSONValue] = []
        for d in inv["deposits"].array {
            if Double(s.week) >= d["wEnd"].double {
                let interest = d["bal"].double * d["rate"].double * (d["wEnd"].double - d["w0"].double) / 52
                Ledger.move(&s, .me, d["bal"].double + interest, why: "Deposit matured")
                s.tax.interest += interest
            } else { kept.append(d) }
        }
        inv = s.rest["inv"] ?? inv
        inv["deposits"] = .array(kept)
        s.rest["inv"] = inv
    }

    /// Sell everything to cover debts, savings first, until `cash >= need`. Original: `liquidateInvestments`.
    public static func liquidate(_ s: inout GameState, need: Double, currency: Currency? = nil) {
        if s.savings > 0 {
            let v = s.savings
            Ledger.move(&s, .me, v, why: "Savings emptied to cover debts")
            s.savings = 0
        }
        if s.cash >= need { return }
        var inv = s.rest["inv"] ?? .object([:])
        for d in inv["deposits"].array { Ledger.move(&s, .me, d["bal"].double, why: "Fixed deposit broken to cover debts") }
        inv["deposits"] = .array([])
        s.rest["inv"] = inv
        if s.cash >= need { return }
        for k in (s.rest["inv"]?["funds"].object.keys.sorted() ?? []) { sell(&s, .fund, k, fraction: 1, currency: currency) }
        for k in (s.rest["inv"]?["stocks"].object.keys.sorted() ?? []) { sell(&s, .stock, k, fraction: 1, currency: currency) }
        for k in (s.rest["inv"]?["crypto"].object.keys.sorted() ?? []) { sell(&s, .crypto, k, fraction: 1, currency: currency) }
    }
}
