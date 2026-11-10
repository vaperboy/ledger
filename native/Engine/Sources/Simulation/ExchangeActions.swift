import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

public enum ExchangeListOutcome: Equatable, Sendable {
    case ok, notAHolding, alreadyListed
    case tooSmall(needed: Double)
    case tooYoung(weeksLeft: Int)
    case notEnoughMoney(Double)
}

extension GameEngine {
    mutating func runExchangeDay() {
        update { st, d, ctx in
            for co in st.companies where Funding.isListed(co) && co.status.isLive && !PublicExchange.isRegistered(st, holdingID: co.id) {
                let v = Funding.holdingValue(st, holdingID: co.id, data: d)
                PublicExchange.register(&st, holdingID: co.id, value: v)
            }
            let look = st
            PublicExchange.runDay(&st, context: ctx) { id in Funding.holdingValue(look, holdingID: id, data: d) }
        }
    }
}

public extension GameEngine {
    var exchangeMarket: [ExchangeRow] { PublicExchange.market(state, context: context) }
    var exchangeOrders: [ExchangeOpenOrder] { PublicExchange.openOrders(state) }
    func leaderboardSubmission(playerID: String) -> LeaderboardSubmission {
        Leaderboards.submission(state, trades: data.catalog, currency: homeCurrency, playerID: playerID)
    }

    func exchangeListingCheck(holdingID: Int) -> ExchangeListOutcome {
        guard let co = state.company(holdingID), co.type == "hold", co.status.isLive else { return .notAHolding }
        if Funding.isListed(co) { return .alreadyListed }
        switch ExchangeRules.listingCheck(value: Funding.holdingValue(state, holdingID: holdingID, data: data), minimum: Funding.listingMinimum(state, context), ageWeeks: state.week - co.foundedWeek) {
        case .tooYoung(let w): return .tooYoung(weeksLeft: w)
        case .tooSmall(let n): return .tooSmall(needed: n)
        case .ok: return .ok
        }
    }

    @discardableResult
    mutating func listOnExchange(holdingID: Int) -> ExchangeListOutcome {
        let check = exchangeListingCheck(holdingID: holdingID)
        if check != .ok { return check }
        let value = Funding.holdingValue(state, holdingID: holdingID, data: data)
        var r = Funding.ListResult.notAHolding
        update { s, d, ctx in r = Funding.listHolding(&s, holdingID: holdingID, data: d, context: ctx) }
        switch r {
        case .ok:
            update { s, _, _ in PublicExchange.register(&s, holdingID: holdingID, value: value) }
            return .ok
        case .notEnoughMoney(let fee): return .notEnoughMoney(fee)
        case .tooSmall(let n): return .tooSmall(needed: n)
        case .alreadyListed: return .alreadyListed
        case .notAHolding: return .notAHolding
        }
    }

    @discardableResult
    mutating func placeExchangeOrder(instrument: String, side: ExchangeSide, shares: Int, limit: Double) -> OrderResult {
        var r = OrderResult.refused(.unknown)
        update { s, _, ctx in r = PublicExchange.placeOrder(&s, instrument: instrument, side: side, shares: shares, limit: limit, currency: ctx.homeCurrency(s)) }
        return r
    }

    @discardableResult
    mutating func cancelExchangeOrder(id: Int) -> Bool {
        var ok = false
        update { s, _, _ in ok = PublicExchange.cancelOrder(&s, orderID: id) }
        return ok
    }

    @discardableResult
    mutating func declareExchangeDividend(holdingID: Int, amount: Double) -> ExchangeDividendResult {
        if let why = JointVenture.payoutBlock(state, companyID: holdingID) { return .refused(why) }
        var r = ExchangeDividendResult.notListed
        update { s, _, ctx in r = PublicExchange.declareDividend(&s, holdingID: holdingID, amount: amount, context: ctx) }
        return r
    }
}
