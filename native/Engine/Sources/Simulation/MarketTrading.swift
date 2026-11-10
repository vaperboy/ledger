import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Investments
import Events

public struct MarketAsset: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: MarketAssetKind
    public var symbol: String
    public var name: String
    public var price: Double
    public var weekChange: Double?
    public var monthChange: Double?
    public var history: [Double]
    public var risk: MarketRisk
    public var holdingsMayBuy: Bool
    public var closed: Bool
    public var costNote: String
}

public struct MarketQuote: Equatable, Sendable {
    public enum Side: String, Sendable { case buy, sell }
    public var side: Side
    public var assetID: String
    public var positionID: String?
    public var owner: PortfolioOwner
    public var amount: Double
    public var units: Double
    public var price: Double
    public var tradePrice: Double
    public var fee: Double
    public var spreadCost: Double
    public var feeLabel: String
    public var cashChange: Double
    public var available: Double
    public var cashAfter: Double
    public var minimum: Double
    public var costBasisSold: Double
    public var realizedGain: Double
    public var refusal: String?
}

public struct MarketTradeResult: Equatable, Sendable {
    public var done: Bool
    public var refusal: String?
    public var units: Double
    public var cashChange: Double
    public var fee: Double
    public var realizedGain: Double
}

public extension GameEngine {
    var marketAssets: [MarketAsset] {
        var out: [MarketAsset] = []
        let cur = homeCurrency
        func changes(_ h: [Double]) -> (Double?, Double?) {
            let n = h.count
            let w = n >= 2 && h[n - 2] > 0 ? h[n - 1] / h[n - 2] - 1 : nil
            let m = n >= 5 && h[n - 5] > 0 ? h[n - 1] / h[n - 5] - 1 : nil
            return (w, m)
        }
        let fundNote = "Broker fee 0.1%, at least \(cur.display(Brokerage.brokerFee(0, currency: cur))). A holding pays no fee to buy and 0.66% to sell."
        for sym in Markets.fundSymbols {
            let h = Markets.fundHistory(state, sym)
            let c = changes(h)
            out.append(MarketAsset(id: "fund:\(sym)", kind: MarketBook.fundKind(sym), symbol: sym, name: MarketBook.fundNames[sym] ?? sym,
                                   price: Brokerage.price(state, .fund, sym), weekChange: c.0, monthChange: c.1, history: h, risk: MarketBook.fundRisk(sym),
                                   holdingsMayBuy: true, closed: false, costNote: fundNote))
        }
        let book = state.rest["crypto"]?.object ?? [:]
        for sym in Markets.cryptoSymbols {
            guard let q = book[sym] else { continue }
            let h = q["h"].array.map { $0.double }
            let c = changes(h)
            out.append(MarketAsset(id: "crypto:\(sym)", kind: .crypto, symbol: sym, name: q["n"].string, price: q["p"].double, weekChange: c.0, monthChange: c.1,
                                   history: h, risk: MarketBook.cryptoRisk(q), holdingsMayBuy: false, closed: q["dead"].bool,
                                   costNote: "Fee 0.4% and a 0.8% spread each way."))
        }
        if let a = FinanceManager.account(state) {
            out.append(MarketAsset(id: "managed:fm", kind: .managedFund, symbol: a.mandate.title, name: "Managed by \(a.name)", price: 1, weekChange: nil, monthChange: nil,
                                   history: [], risk: a.mandate == .cautious ? .low : a.mandate == .balanced ? .medium : .high, holdingsMayBuy: false, closed: false,
                                   costNote: "A yearly fee of \(Currency.percent(a.fee, decimals: 1)) of the money managed."))
        }
        return out
    }

    func marketQuote(asset: String, owner: PortfolioOwner, amount: Double) -> MarketQuote {
        let amt = amount.rounded()
        let parts = asset.split(separator: ":", maxSplits: 1).map(String.init)
        let kindKey = parts.first ?? "", sym = parts.count > 1 ? parts[1] : ""
        var q = MarketQuote(side: .buy, assetID: asset, positionID: nil, owner: owner, amount: amt, units: 0, price: 0, tradePrice: 0, fee: 0, spreadCost: 0,
                            feeLabel: "Broker fee", cashChange: -amt, available: 0, cashAfter: 0, minimum: 0, costBasisSold: 0, realizedGain: 0, refusal: nil)
        switch owner {
        case .player:
            let cur = homeCurrency
            q.available = Payments.liquid(state)
            switch kindKey {
            case "fund", "crypto":
                let kind: Brokerage.Kind = kindKey == "fund" ? .fund : .crypto
                let known = kind == .fund ? Markets.fundSymbols.contains(sym) : state.rest["crypto"]?[sym].isNull == false
                let t = buyQuote(kind, symbol: sym, amount: amt)
                q.price = Brokerage.price(state, kind, sym)
                q.tradePrice = kind == .crypto ? q.price * 1.008 : q.price
                q.fee = t.fee; q.units = t.units; q.cashChange = -(amt + t.fee); q.minimum = t.minimumPurchase
                q.spreadCost = max(0, amt - t.units * q.price)
                q.feeLabel = kind == .crypto ? "Fee" : "Broker fee"
                q.refusal = known ? t.refusal : "That is not something you can buy."
            case "managed":
                if FinanceManager.account(state) == nil { q.refusal = "You have no fund manager. Hire one first." }
                else if amt <= 0 { q.refusal = "Enter an amount." }
                else if state.cash < amt { q.refusal = "Your fund manager is paid from the current account, which holds \(cur.display(max(0, state.cash)))." }
                q.price = 1; q.tradePrice = 1; q.units = amt; q.feeLabel = "Yearly fee"
                q.available = state.cash
            default:
                q.refusal = "That is not something you can buy."
            }
            q.cashAfter = q.available + q.cashChange
        case .holding(let hid):
            guard let h = state.company(hid), h.type == "hold" else {
                q.refusal = "That holding no longer exists."
                return q
            }
            let cur = currency(for: h)
            q.available = h.cash
            q.minimum = Brokerage.minimumPurchase(cur)
            q.feeLabel = "No fee"
            if kindKey == "fund", HoldingModel.treasuryFunds.contains(sym) {
                q.price = HoldingModel.fundPrice(state, sym); q.tradePrice = q.price
                q.units = q.price > 0 ? amt / q.price : 0
                if h.status != .open { q.refusal = "\(h.name) is not open." }
                else if amt < q.minimum { q.refusal = "The smallest order is \(cur.display(q.minimum))." }
                else if h.cash < amt { q.refusal = "\(h.name) has \(cur.display(max(0, h.cash))) in cash." }
            } else {
                q.refusal = "A holding's treasury holds funds only: the index, bond and money-market funds."
            }
            q.cashAfter = h.cash + q.cashChange
        }
        return q
    }

    func marketSellQuote(position: String, units: Double) -> MarketQuote {
        guard let p = portfolio.positions.first(where: { $0.id == position }) else { return Self.noPosition(position) }
        return sellQuote(p, fraction: p.units > 0 ? units / p.units : 0)
    }

    func marketSellQuote(position: String, amount: Double) -> MarketQuote {
        guard let p = portfolio.positions.first(where: { $0.id == position }) else { return Self.noPosition(position) }
        return sellQuote(p, fraction: p.value > 0 ? amount / p.value : 0)
    }

    private static func noPosition(_ id: String) -> MarketQuote {
        MarketQuote(side: .sell, assetID: "", positionID: id, owner: PortfolioOwner(id: String(id.split(separator: ":").first ?? "")) ?? .player, amount: 0, units: 0,
                    price: 0, tradePrice: 0, fee: 0, spreadCost: 0, feeLabel: "", cashChange: 0, available: 0, cashAfter: 0, minimum: 0, costBasisSold: 0,
                    realizedGain: 0, refusal: "There is nothing held to sell.")
    }

    private func sellQuote(_ p: PortfolioPosition, fraction f0: Double) -> MarketQuote {
        let f = min(max(f0, 0), 1)
        var q = MarketQuote(side: .sell, assetID: p.assetID ?? "", positionID: p.id, owner: p.owner, amount: p.value * f, units: p.units * f, price: p.price,
                            tradePrice: p.price, fee: 0, spreadCost: 0, feeLabel: "Broker fee", cashChange: 0, available: 0, cashAfter: 0, minimum: 0,
                            costBasisSold: p.costBasis * f, realizedGain: 0, refusal: nil)
        let parts = p.id.split(separator: ":").map(String.init)
        let key = parts.count > 1 ? parts[1] : "", sym = parts.count > 2 ? parts[2] : ""
        switch p.owner {
        case .player:
            q.available = Payments.liquid(state)
            switch key {
            case "fund", "crypto":
                let kind = Brokerage.Kind(rawValue: key) ?? .fund
                let t = sellQuote(kind, symbol: sym, fraction: f)
                q.tradePrice = kind == .crypto ? p.price * 0.992 : p.price
                q.fee = t.fee; q.feeLabel = kind == .crypto ? "Fee" : "Broker fee"
                q.spreadCost = max(0, q.amount - t.amount)
                q.cashChange = t.amount - t.fee
                if q.units > 0, t.amount <= t.fee { q.refusal = "That sale is smaller than the fee of \(homeCurrency.display(t.fee))." }
                if p.delisted { q.refusal = "Trading in \(p.symbol) has stopped." }
            case "managed":
                q.feeLabel = "No fee"
                q.cashChange = q.amount
            case "startup":
                q.feeLabel = "Private sale discount"
                q.cashChange = q.amount * 0.72
                q.fee = q.amount - q.cashChange
            case "pe":
                q.feeLabel = "Secondary market discount"
                let id = Int(sym) ?? 0
                q.units = p.units; q.amount = p.value; q.costBasisSold = p.costBasis
                q.cashChange = PrivateEquity.secondaryPrice(state, fundID: id)
                q.fee = max(0, p.value - q.cashChange)
                if f < 1 { q.refusal = "A private equity stake is sold whole." }
            default:
                q.refusal = p.sellNote ?? "This cannot be sold."
            }
        case .holding(let hid):
            q.available = state.company(hid)?.cash ?? 0
            q.feeLabel = "Sale cost"
            q.fee = q.amount * HoldingModel.divestCost
            q.cashChange = q.amount - q.fee
            if state.company(hid)?.status != .open { q.refusal = "The holding is not open." }
        }
        if !p.canSell, q.refusal == nil { q.refusal = p.sellNote ?? "This cannot be sold." }
        if q.units <= 1e-12, q.refusal == nil { q.refusal = "Choose how much to sell." }
        q.realizedGain = q.cashChange - q.costBasisSold
        q.cashAfter = q.available + q.cashChange
        return q
    }

    @discardableResult
    mutating func marketBuy(asset: String, owner: PortfolioOwner, amount: Double) -> MarketTradeResult {
        let q = marketQuote(asset: asset, owner: owner, amount: amount)
        if let why = q.refusal { return MarketTradeResult(done: false, refusal: why, units: 0, cashChange: 0, fee: 0, realizedGain: 0) }
        let before = ownerCash(owner)
        let parts = asset.split(separator: ":", maxSplits: 1).map(String.init)
        let key = parts[0], sym = parts.count > 1 ? parts[1] : ""
        var ok = false
        switch owner {
        case .player:
            if key == "managed" {
                update { s, _, _ in ok = FinanceManager.add(&s, amount: q.amount) }
            } else {
                let kind: Brokerage.Kind = key == "fund" ? .fund : .crypto
                update { s, _, ctx in ok = Brokerage.buy(&s, kind, sym, amount: q.amount, currency: ctx.homeCurrency(s)) == .ok }
            }
        case .holding(let hid):
            update { s, d, _ in
                ok = HoldingModel.invest(&s, holdingID: hid, amount: q.amount, fund: sym)
                if ok { HoldingModel.refreshAssets(&s, holdingID: hid, data: d) }
            }
        }
        if !ok { return MarketTradeResult(done: false, refusal: "The purchase did not go through.", units: 0, cashChange: 0, fee: 0, realizedGain: 0) }
        return MarketTradeResult(done: true, refusal: nil, units: q.units, cashChange: ownerCash(owner) - before, fee: q.fee, realizedGain: 0)
    }

    @discardableResult
    mutating func marketSell(position: String, units: Double) -> MarketTradeResult {
        guard let p = portfolio.positions.first(where: { $0.id == position }) else { return Self.refused("There is nothing held to sell.") }
        return sell(p, fraction: p.units > 0 ? units / p.units : 0)
    }

    @discardableResult
    mutating func marketSell(position: String, amount: Double) -> MarketTradeResult {
        guard let p = portfolio.positions.first(where: { $0.id == position }) else { return Self.refused("There is nothing held to sell.") }
        return sell(p, fraction: p.value > 0 ? amount / p.value : 0)
    }

    private static func refused(_ why: String) -> MarketTradeResult { MarketTradeResult(done: false, refusal: why, units: 0, cashChange: 0, fee: 0, realizedGain: 0) }

    private func ownerCash(_ o: PortfolioOwner) -> Double {
        switch o {
        case .player: return state.cash
        case .holding(let h): return state.company(h)?.cash ?? 0
        }
    }

    private mutating func sell(_ p: PortfolioPosition, fraction f0: Double) -> MarketTradeResult {
        let f = min(max(f0, 0), 1)
        let q = sellQuote(p, fraction: f)
        if let why = q.refusal { return Self.refused(why) }
        let before = ownerCash(p.owner)
        let parts = p.id.split(separator: ":").map(String.init)
        let key = parts[1], sym = parts.count > 2 ? parts[2] : ""
        let whole = f > 0.9999
        switch p.owner {
        case .player:
            switch key {
            case "fund", "crypto":
                let kind = Brokerage.Kind(rawValue: key) ?? .fund
                update { s, _, ctx in Brokerage.sell(&s, kind, sym, fraction: whole ? 1 : f, currency: ctx.homeCurrency(s)) }
            case "managed": update { s, _, _ in _ = FinanceManager.withdraw(&s, amount: whole ? p.value : q.amount) }
            case "startup": update { s, _, _ in Startups.sellStake(&s, stakeID: Int(sym) ?? 0, fraction: whole ? 1 : f) }
            case "pe": update { s, _, _ in _ = PrivateEquity.sellStake(&s, fundID: Int(sym) ?? 0) }
            default: return Self.refused(p.sellNote ?? "This cannot be sold.")
            }
        case .holding(let hid):
            update { s, d, _ in
                let pos = s.company(hid).map { HoldingModel.fundPosition($0, sym) } ?? (units: 0, cost: 0)
                HoldingModel.divestAmount(&s, holdingID: hid, amount: whole ? pos.units * HoldingModel.fundPrice(s, sym) : q.amount, fund: sym)
                HoldingModel.refreshAssets(&s, holdingID: hid, data: d)
            }
        }
        let change = ownerCash(p.owner) - before
        if change == 0 && q.cashChange != 0 { return Self.refused("The sale did not go through.") }
        if case .player = p.owner { update { s, _, ctx in PersonalFinance.withholdNow(&s, context: ctx) } }
        return MarketTradeResult(done: true, refusal: nil, units: q.units, cashChange: change, fee: q.fee, realizedGain: change - q.costBasisSold)
    }
}
