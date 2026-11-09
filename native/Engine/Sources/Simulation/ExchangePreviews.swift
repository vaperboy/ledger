import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

/// What an exchange order, a listing or a dividend would do, worked out on a copy of the game so that nothing in the real one changes.
/// Each preview carries the plain lines for "If you do this, this will happen".
public struct ExchangeOrderPreview: Equatable, Sendable {
    public var instrument: String
    public var side: ExchangeSide
    public var shares: Int
    public var limit: Double
    /// Shares times the limit price: the most the order can move.
    public var amount: Double
    /// The broker's fee when it fills.
    public var fee: Double
    /// Your cash now, and the lowest it can be once a buy fills in full at the limit.
    public var cashNow: Double
    public var cashAfterBuy: Double?
    /// The price band around the value per share, when the share is known.
    public var bandLow: Double?, bandHigh: Double?
    /// Why the order would be refused; nil when it would be placed.
    public var refusal: OrderRefusal?
    public var allowed: Bool { refusal == nil }
    public var lines: [String]
}

public struct ExchangeListingPreview: Equatable, Sendable {
    public var holdingID: Int
    public var outcome: ExchangeListOutcome
    /// What taking the holding public costs now (0 when it would be refused).
    public var fee: Double
    public var sharesInIssue: Int
    public var valuePerShare: Double
    public var allowed: Bool { outcome == .ok }
    public var lines: [String]
}

public struct ExchangeDividendPreview: Equatable, Sendable {
    public var holdingID: Int
    public var result: ExchangeDividendResult
    public var amount: Double
    public var perShare: Double
    /// The part that reaches you by your stake.
    public var yourShare: Double
    public var allowed: Bool { if case .ok = result { return true } else { return false } }
    public var lines: [String]
}

public extension GameEngine {
    /// What `placeExchangeOrder` would do. Nothing changes in this game.
    func previewOrder(instrument: String, side: ExchangeSide, shares: Int, limit: Double) -> ExchangeOrderPreview {
        var trial: GameEngine = self
        let cur: Currency = homeCurrency
        let px: Double = ExchangeRules.round4(limit)
        let amount: Double = Double(max(0, shares)) * max(0, px)
        let fee: Double = amount > 0 ? ExchangeRules.fee(amount, currency: cur) : 0
        let result: OrderResult = trial.placeExchangeOrder(instrument: instrument, side: side, shares: shares, limit: limit)
        var refusal: OrderRefusal?
        if case .refused(let r) = result { refusal = r }
        let row: ExchangeRow? = exchangeMarket.first { $0.id == instrument }
        let cash: Double = Payments.liquid(state)
        var lines: [String] = []
        if let why = refusal {
            lines.append(why.words)
        } else {
            let verb: String = side == .buy ? "buy" : "sell"
            lines.append("An order to \(verb) \(shares) at \(cur.display(px)) or better waits until the day's closing auction.")
            lines.append(side == .buy ? "At most \(cur.display(amount + fee)) leaves your cash, fee included, and only if it fills in full."
                                      : "If it fills you receive up to \(cur.display(amount - fee)) after the fee.")
            lines.append("If the price at the close is worse than your limit, nothing happens and you pay nothing. You can cancel until then.")
        }
        return ExchangeOrderPreview(instrument: instrument, side: side, shares: shares, limit: px, amount: amount, fee: fee, cashNow: cash,
                                    cashAfterBuy: side == .buy ? cash - amount - fee : nil, bandLow: row?.low, bandHigh: row?.high, refusal: refusal, lines: lines)
    }

    /// What `listOnExchange` would do and cost. Nothing changes in this game.
    func previewListing(holdingID: Int) -> ExchangeListingPreview {
        var trial: GameEngine = self
        let cur: Currency = homeCurrency
        let cash0: Double = state.cash
        let outcome: ExchangeListOutcome = trial.listOnExchange(holdingID: holdingID)
        let fee: Double = outcome == .ok ? max(0, cash0 - trial.state.cash) : 0
        let value: Double = state.company(holdingID).map { _ in Funding.holdingValue(state, holdingID: holdingID, data: data) } ?? 0
        let shares: Int = state.company(holdingID).map { CapTable.table($0).total } ?? 0
        let perShare: Double = shares > 0 ? ExchangeRules.round4(value / Double(shares)) : 0
        var lines: [String] = []
        switch outcome {
        case .ok:
            lines.append("You pay a listing fee of \(cur.display(fee)) from your cash, and it is not refunded.")
            lines.append("Its \(shares) shares start trading at \(cur.display(perShare)) each, the value per share today.")
            lines.append("You keep at least \(ExchangeRules.ownerFloorPercent)% of the shares, and cannot sell your own for \(ExchangeRules.lockUpDays) days.")
        case .notAHolding: lines.append("Only a holding company can be taken public.")
        case .alreadyListed: lines.append("This holding is already on the exchange.")
        case .tooSmall(let n): lines.append("It must be worth at least \(cur.display(n)) first.")
        case .tooYoung(let w): lines.append("It must have traded for \(ExchangeRules.minimumAgeWeeks) weeks: \(w) to go.")
        case .notEnoughMoney(let f): lines.append("You need \(cur.display(f)) in cash for the listing fee.")
        }
        return ExchangeListingPreview(holdingID: holdingID, outcome: outcome, fee: fee, sharesInIssue: shares, valuePerShare: perShare, lines: lines)
    }

    /// What `declareExchangeDividend` would do. Nothing changes in this game.
    func previewDividend(holdingID: Int, amount: Double) -> ExchangeDividendPreview {
        var trial: GameEngine = self
        let cur: Currency = homeCurrency
        let result: ExchangeDividendResult = trial.declareExchangeDividend(holdingID: holdingID, amount: amount)
        let co: Company? = state.company(holdingID)
        let mine: Double = co.map { amount * $0.ownership / 100 } ?? 0
        var perShare: Double = 0
        var lines: [String] = []
        switch result {
        case .ok(let dps):
            perShare = dps
            lines.append("The company pays out \(cur.display(amount)) in all, \(cur.display(dps)) a share, from its own cash.")
            lines.append("You receive \(cur.display(mine)) by your stake; the rest goes to the other shareholders. Dividend tax applies to what you receive.")
            lines.append("The share price drops by the dividend per share (ex-dividend). You cannot sell your own shares for a few days after declaring.")
        case .notListed: lines.append("This holding is not on the exchange.")
        case .tooSoon(let d): lines.append("A dividend can be declared once a quarter: \(d) more days.")
        case .nothingToPay: lines.append("Enter an amount above zero.")
        case .tooMuch(let m): lines.append("The most it can pay now is \(cur.display(m)).")
        case .refused(let why): lines.append(why)
        }
        return ExchangeDividendPreview(holdingID: holdingID, result: result, amount: amount, perShare: perShare, yourShare: result == .ok(perShare: perShare) ? mine : 0, lines: lines)
    }
}
