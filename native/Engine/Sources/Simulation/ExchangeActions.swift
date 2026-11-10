import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

extension GameEngine {
    mutating func runExchangeDay() {
        update { st, d, ctx in
            let look = st
            PublicExchange.runDay(&st, context: ctx) { id in look.company(id).map { Valuation.companyValue($0, state: look, trades: d.catalog) } }
            PublicCompany.results(&st, data: d, context: ctx)
        }
    }
}

public extension GameEngine {
    var exchangeMarket: [ExchangeRow] { PublicExchange.market(state, context: context) }
    var exchangeOrders: [ExchangeOpenOrder] { PublicExchange.openOrders(state) }
    func leaderboardSubmission(playerID: String) -> LeaderboardSubmission {
        Leaderboards.submission(state, trades: data.catalog, currency: homeCurrency, playerID: playerID)
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
}
