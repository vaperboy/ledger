import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Investments
import Events
import Simulation

// The one door between the Market app and the engine. Every Market screen reads and trades through `MarketData`, so moving to the
// engine's own Market API (portfolio with cost basis, marketBuy/marketSell/marketQuote, per-company market comparison, rivals and the
// watchlist, overview signals, world reads) changes this file only. Each read that stands in for one of those is marked "Engine API:".

/// The Market app's own value types, kept in one namespace so they never clash with engine types of the same idea.
enum MarketUI {
    /// The five parts of the app.
    enum Tab: String, CaseIterable, Hashable {
        case overview = "Overview", companies = "Companies", rivals = "Rivals", invest = "Invest", world = "World"
    }

    /// Who holds a position or pays for a purchase: you personally, or one of your holding companies (its treasury).
    enum Owner: Hashable {
        case you
        case holding(Int)
        var key: String {
            switch self {
            case .you: return "you"
            case .holding(let id): return "h\(id)"
            }
        }
    }

    struct OwnerInfo: Identifiable, Hashable {
        var owner: Owner
        var name: String
        /// What this owner can spend now: current account and savings for you, the treasury cash for a holding.
        var cash: Double
        var id: String { owner.key }
    }

    /// What kind of thing a position is.
    enum AssetClass: String, Hashable {
        case crypto, fund, shares, startup, privateEquity, groupStake, partnership, managed
        var word: String {
            switch self {
            case .crypto: return "Crypto"
            case .fund: return "Fund"
            case .shares: return "Shares"
            case .startup: return "Startup stake"
            case .privateEquity: return "Private equity"
            case .groupStake: return "Stake in a group"
            case .partnership: return "Partnership stake"
            case .managed: return "Fund manager"
            }
        }
        var glyph: String {
            switch self {
            case .crypto: return Glyph.luxury
            case .fund: return Glyph.invest
            case .shares: return Glyph.stats
            case .startup: return Glyph.ventures
            case .privateEquity, .groupStake, .partnership: return Glyph.group
            case .managed: return Glyph.person
            }
        }
    }

    /// One holding of one owner.
    struct Position: Identifiable, Hashable {
        var id: String
        var owner: Owner
        var ownerName: String
        var assetClass: AssetClass
        /// The tradable asset behind it (for "Buy more"); nil for what cannot be bought again here.
        var assetID: String?
        var name: String
        var symbol: String
        var units: Double?
        var cost: Double
        /// False when the game kept no purchase price (a stake bought at a meeting): no gain or loss is shown.
        var costKnown: Bool
        var value: Double
        var weekChange: Double?
        var history: [Double]
        var sellable: Bool
        /// A private equity stake sells in one piece on the secondary market.
        var wholeOnly: Bool
        /// The engine's record id (stake, fund) for selling a private stake.
        var recordID: Int
        var pnl: Double { value - cost }
        var pnlShare: Double? { costKnown && cost > 0.5 ? (value - cost) / cost : nil }
    }

    /// Something that can be bought here.
    struct Asset: Identifiable, Hashable {
        var id: String
        var kind: Brokerage.Kind
        var symbol: String
        var name: String
        var price: Double
        var weekChange: Double?
        var history: [Double]
        var risk: String
        var note: String
        /// Holdings invest their treasury in the index fund only.
        var holdingsMayBuy: Bool
    }

    struct Portfolio {
        var positions: [Position]
        var value: Double { positions.reduce(0) { (a: Double, p: Position) -> Double in a + p.value } }
        var cost: Double { positions.filter { (p: Position) -> Bool in p.costKnown }.reduce(0) { (a: Double, p: Position) -> Double in a + p.cost } }
        var knownValue: Double { positions.filter { (p: Position) -> Bool in p.costKnown }.reduce(0) { (a: Double, p: Position) -> Double in a + p.value } }
        var pnl: Double { knownValue - cost }
        var pnlShare: Double? { cost > 0.5 ? pnl / cost : nil }
        /// The move over the last week of the positions that have a price history.
        var weekMove: Double? {
            let moving: [Position] = positions.filter { (p: Position) -> Bool in p.weekChange != nil }
            guard !moving.isEmpty else { return nil }
            return moving.reduce(0) { (a: Double, p: Position) -> Double in
                let w: Double = p.weekChange ?? 0
                return a + p.value - p.value / (1 + w)
            }
        }
        func only(_ owner: Owner?) -> Portfolio {
            guard let owner else { return self }
            return Portfolio(positions: positions.filter { (p: Position) -> Bool in p.owner == owner })
        }
    }

    /// What a trade would do, before it is made.
    struct TradePreview: Equatable {
        /// Buying: what is invested. Selling: the value sold.
        var amount: Double
        var fee: Double
        var units: Double
        /// Buying: what leaves the owner's cash. Selling: what reaches it.
        var cashChange: Double
        /// Buying: what the owner can spend.
        var available: Double
        var cashAfter: Double
        var minimum: Double
        /// Why it would not go through (nil when it would).
        var refusal: String?
    }

    enum Outcome { case done(String), refused(String) }

    /// One of your companies against its market.
    struct CompanyLine: Identifiable, Hashable {
        var id: Int
        var name: String
        var trade: String
        var city: String
        var marketKey: String?
        var level: MarketMap.Knowledge.Level
        /// "18%", "12–15%" or words ("A fair slice"): who measures decides.
        var shareText: String
        /// Your share in percent, only when measured (an analyst draws it).
        var share: Double?
        /// Points gained or lost last month (measured only).
        var trend: Double?
        /// Your place among the businesses in this market, when an analyst estimates it.
        var rank: Int?
        var players: Int
        /// Your price against the rivals' average, as a share (+0.08 = 8% dearer).
        var priceGap: Double?
        var rating: Double?
        var ratingGap: Double?
    }

    /// A row of the "you against the field" table.
    struct CompareRow: Identifiable, Hashable {
        var id: String
        var name: String
        var mine: Bool
        var rivalID: Int?
        var shareText: String
        var priceText: String
        var rating: Double?
        var sizeWord: String
        var moneyWord: String
        var forSale: Bool
    }

    /// A rival business in one of your markets.
    struct RivalItem: Identifiable, Hashable {
        var companyID: Int
        var rivalID: Int
        var name: String
        var owner: String
        var trade: String
        var city: String
        var country: String
        var sizeWord: String
        var valuation: Double
        var moneyWord: String
        var forSale: Bool
        var inTrouble: Bool
        var groupID: String?
        var groupName: String?
        var shareText: String
        var yourCompany: String
        var id: String { "co\(companyID).r\(rivalID)" }
    }

    /// A rival group around you.
    struct GroupItem: Identifiable, Hashable {
        var id: String
        var name: String
        var owner: String
        var strategy: String
        var sites: Int
        var revenue: Double
        var profit: Double
        var inTrouble: Bool
        var countries: [String]
        var rivalsInYourMarkets: Int
    }

    /// A short card on the Overview.
    struct Signal: Identifiable, Hashable {
        enum Target: Hashable { case rival(Int, Int), company(Int), asset(String), country(String), nothing }
        var id: String
        var title: String
        var detail: String
        var tone: String
        var glyph: String
        var target: Target
    }

    /// A biggest move of the week.
    struct Mover: Identifiable, Hashable {
        var id: String
        var title: String
        var detail: String
        /// A share (0.04 = 4%) or points of market share when `points` is true.
        var change: Double
        var points: Bool
        var amount: Double?
    }

    /// A country on the World part.
    struct CountryLine: Identifiable, Hashable {
        var id: String
        var name: String
        var flag: String
        var region: String
        var population: Double
        var currency: String
        var corporateTax: Double
        var demand: Double
        var wages: Double
        var rents: Double
        var rivalGroups: Int
        var yourCompanies: Int
        var isHome: Bool
    }
}

/// The reads and trades of the Market app. Pure functions of the engine; the trades go through `GameStore.act`.
enum MarketData {
    // MARK: Owners

    /// You, then every open holding with its treasury cash.
    static func owners(_ e: GameEngine) -> [MarketUI.OwnerInfo] {
        var out: [MarketUI.OwnerInfo] = [MarketUI.OwnerInfo(owner: .you, name: "You", cash: Payments.liquid(e.state))]
        for h in e.holdingCompanies {
            out.append(MarketUI.OwnerInfo(owner: .holding(h.id), name: h.name, cash: max(0, h.cash)))
        }
        return out
    }

    static func ownerName(_ e: GameEngine, _ o: MarketUI.Owner) -> String {
        switch o {
        case .you: return "You"
        case .holding(let id): return e.state.company(id)?.name ?? "Holding"
        }
    }

    // MARK: Portfolio

    /// Every position of every owner. Engine API: replace with the engine's portfolio (personal and holding positions, cost basis, P&L).
    static func portfolio(_ e: GameEngine) -> MarketUI.Portfolio {
        var out: [MarketUI.Position] = []
        for kind in [Brokerage.Kind.fund, .crypto, .stock] {
            for q in e.quotes(kind) where q.quantity > 0 && q.value > 0.5 {
                let cls: MarketUI.AssetClass = kind == .crypto ? .crypto : (kind == .fund ? .fund : .shares)
                out.append(MarketUI.Position(id: "you|\(q.id)", owner: .you, ownerName: "You", assetClass: cls, assetID: kind == .stock ? nil : q.id,
                                             name: q.name.tidyText, symbol: q.symbol, units: q.quantity, cost: q.costBasis, costKnown: true, value: q.value,
                                             weekChange: q.weekChange, history: Array(q.history.suffix(52)), sellable: !q.isDelisted, wholeOnly: false, recordID: 0))
            }
        }
        let indexPrice: Double = HoldingModel.indexPrice(e.state)
        for h in e.holdingCompanies {
            let fm: JSONValue = h.value("fm")
            let units: Double = fm["idxU"].double
            guard units > 0 else { continue }
            let value: Double = units * indexPrice
            // An older save kept no purchase price for a holding's index fund: today's value stands in as the basis (no gain or loss yet).
            let cost: Double = fm["idxCost"].double > 0 ? fm["idxCost"].double : value
            out.append(MarketUI.Position(id: "h\(h.id)|fund-\(HoldingModel.indexFundKey)", owner: .holding(h.id), ownerName: h.name, assetClass: .fund,
                                         assetID: "fund-\(HoldingModel.indexFundKey)", name: "Index fund", symbol: HoldingModel.indexFundKey, units: units,
                                         cost: cost, costKnown: true, value: value, weekChange: nil, history: [], sellable: true, wholeOnly: false, recordID: h.id))
        }
        for s in e.startupStakes where s.live && s.value > 0.5 {
            out.append(MarketUI.Position(id: "stake|\(s.id)", owner: .you, ownerName: "You", assetClass: .startup, assetID: nil, name: s.name,
                                         symbol: s.stageName, units: nil, cost: s.invested, costKnown: true, value: s.value, weekChange: nil, history: [],
                                         sellable: true, wholeOnly: false, recordID: s.id))
        }
        for f in e.privateEquityFunds where f.live && !f.sold {
            out.append(MarketUI.Position(id: "pe|\(f.id)", owner: .you, ownerName: "You", assetClass: .privateEquity, assetID: nil, name: f.name,
                                         symbol: f.style, units: nil, cost: f.paidIn, costKnown: true, value: f.nav, weekChange: nil, history: [],
                                         sellable: f.nav > 0.5, wholeOnly: true, recordID: f.id))
        }
        for g in e.groupStakes where g.value > 0.5 {
            out.append(MarketUI.Position(id: "grp|\(g.id)", owner: .you, ownerName: "You", assetClass: .groupStake, assetID: nil, name: g.name,
                                         symbol: pctText(g.ownership), units: nil, cost: g.cost, costKnown: g.cost > 0, value: g.value,
                                         weekChange: nil, history: [], sellable: false, wholeOnly: false, recordID: g.id))
        }
        for b in e.bigMeetingStakes where b.value > 0.5 {
            out.append(MarketUI.Position(id: "big|\(b.id)", owner: .you, ownerName: "You", assetClass: .partnership, assetID: nil, name: b.name,
                                         symbol: pctText(b.pct), units: nil, cost: 0, costKnown: false, value: b.value,
                                         weekChange: nil, history: [], sellable: false, wholeOnly: false, recordID: b.id))
        }
        if let m = e.fundManager, m.balance > 0.5 {
            out.append(MarketUI.Position(id: "managed|\(m.personID)", owner: .you, ownerName: "You", assetClass: .managed, assetID: nil, name: m.name,
                                         symbol: m.mandate.title, units: nil, cost: m.cost, costKnown: m.cost > 0, value: m.balance, weekChange: nil, history: [],
                                         sellable: false, wholeOnly: false, recordID: m.personID))
        }
        return MarketUI.Portfolio(positions: out.sorted { (a: MarketUI.Position, b: MarketUI.Position) -> Bool in a.value > b.value })
    }

    /// "25%" from a share kept either as a fraction (0.25) or as a percent (25).
    private static func pctText(_ v: Double) -> String {
        let pct: Double = v <= 1 ? v * 100 : v
        return "\(Int(pct.rounded()))%"
    }

    static func position(_ e: GameEngine, id: String) -> MarketUI.Position? {
        portfolio(e).positions.first { (p: MarketUI.Position) -> Bool in p.id == id }
    }

    /// Your personal invested value day by day, for the hero sparkline. Engine API: a series that includes the holdings' treasuries.
    @MainActor static func investedHistory(_ store: GameStore) -> [Double] {
        Array((store.dayHistoryNow?.invested ?? []).suffix(60))
    }

    // MARK: What can be bought

    /// Funds and crypto (listed shares are not offered any more: they can only be sold).
    static func assets(_ e: GameEngine) -> [MarketUI.Asset] {
        var out: [MarketUI.Asset] = []
        for q in e.quotes(.fund) {
            let risk: String
            let note: String
            switch q.symbol {
            case "idx": risk = "Medium risk"; note = "The whole stock market in one fund"
            case "bond": risk = "Low risk"; note = "Steady interest, small swings"
            default: risk = "Very low risk"; note = "Close to cash, a little interest"
            }
            out.append(MarketUI.Asset(id: q.id, kind: .fund, symbol: q.symbol, name: q.name.tidyText, price: q.price, weekChange: q.weekChange,
                                      history: Array(q.history.suffix(26)), risk: risk, note: note, holdingsMayBuy: q.symbol == HoldingModel.indexFundKey))
        }
        for q in e.quotes(.crypto) where !q.isDelisted {
            out.append(MarketUI.Asset(id: q.id, kind: .crypto, symbol: q.symbol, name: q.name.tidyText, price: q.price, weekChange: q.weekChange,
                                      history: Array(q.history.suffix(26)), risk: "Very high risk", note: "Can lose most of its value", holdingsMayBuy: false))
        }
        return out
    }

    static func asset(_ e: GameEngine, id: String) -> MarketUI.Asset? {
        assets(e).first { (a: MarketUI.Asset) -> Bool in a.id == id }
    }

    /// Whether `owner` may hold `asset`, and why not. Engine API: marketQuote answers this for any owner.
    static func refusal(_ asset: MarketUI.Asset, for owner: MarketUI.Owner) -> String? {
        if case .holding = owner, !asset.holdingsMayBuy { return "A holding invests its treasury in the index fund only." }
        return nil
    }

    // MARK: Quotes

    /// Buying `amount` of `asset` for `owner`. Engine API: marketQuote(asset, owner, amount).
    static func buyPreview(_ e: GameEngine, _ asset: MarketUI.Asset, owner: MarketUI.Owner, amount: Double) -> MarketUI.TradePreview {
        switch owner {
        case .you:
            let q: TradeQuote = e.buyQuote(asset.kind, symbol: asset.symbol, amount: amount)
            return MarketUI.TradePreview(amount: q.amount, fee: q.fee, units: q.units, cashChange: q.cashChange, available: q.available,
                                         cashAfter: q.cashAfter, minimum: q.minimumPurchase, refusal: amount <= 0 ? "Enter an amount." : q.refusal)
        case .holding(let id):
            let cash: Double = max(0, e.state.company(id)?.cash ?? 0)
            let price: Double = HoldingModel.indexPrice(e.state)
            let amt: Double = amount.rounded()
            var why: String? = refusal(asset, for: owner)
            if why == nil && amt <= 0 { why = "Enter an amount." }
            if why == nil && amt > cash { why = "The holding has \(e.homeCurrency.tidyDisplay(cash)) in its treasury." }
            return MarketUI.TradePreview(amount: amt, fee: 0, units: price > 0 ? amt / price : 0, cashChange: amt, available: cash,
                                         cashAfter: cash - amt, minimum: 0, refusal: why)
        }
    }

    /// Selling `fraction` (0...1) of a position. Engine API: marketQuote for a sale.
    static func sellPreview(_ e: GameEngine, _ p: MarketUI.Position, fraction: Double) -> MarketUI.TradePreview {
        let f: Double = p.wholeOnly ? 1 : min(max(fraction, 0), 1)
        switch p.assetClass {
        case .crypto, .fund, .shares:
            if case .holding(let id) = p.owner {
                let cash: Double = e.state.company(id)?.cash ?? 0
                let value: Double = p.value * f
                let fee: Double = value * 0.0066
                return MarketUI.TradePreview(amount: value, fee: fee, units: (p.units ?? 0) * f, cashChange: value - fee, available: cash,
                                             cashAfter: cash + value - fee, minimum: 0, refusal: value <= 0 ? "There is nothing held to sell." : nil)
            }
            let kind: Brokerage.Kind = p.assetClass == .crypto ? .crypto : (p.assetClass == .fund ? .fund : .stock)
            let q: TradeQuote = e.sellQuote(kind, symbol: p.symbol, fraction: f)
            return MarketUI.TradePreview(amount: q.amount, fee: q.fee, units: q.units, cashChange: q.cashChange, available: q.available,
                                         cashAfter: q.cashAfter, minimum: 0, refusal: p.sellable ? q.refusal : "Trading in \(p.symbol) has stopped.")
        case .startup:
            // A stake in someone else's startup sells at 72% of its fair value.
            let get: Double = p.value * f * 0.72
            let liquid: Double = Payments.liquid(e.state)
            return MarketUI.TradePreview(amount: p.value * f, fee: p.value * f - get, units: 0, cashChange: get, available: liquid,
                                         cashAfter: liquid + get, minimum: 0, refusal: nil)
        case .privateEquity:
            let get: Double = e.secondaryPrice(fundID: p.recordID)
            let liquid: Double = Payments.liquid(e.state)
            return MarketUI.TradePreview(amount: p.value, fee: max(0, p.value - get), units: 0, cashChange: get, available: liquid,
                                         cashAfter: liquid + get, minimum: 0, refusal: get > 0 ? nil : "No buyer on the secondary market right now.")
        case .groupStake, .partnership, .managed:
            return MarketUI.TradePreview(amount: 0, fee: 0, units: 0, cashChange: 0, available: 0, cashAfter: 0, minimum: 0,
                                         refusal: "This stake is not sold here.")
        }
    }

    // MARK: Trades

    /// Buys `amount` of `asset` for `owner`. Engine API: marketBuy(asset, owner, amount).
    @MainActor static func buy(_ store: GameStore, _ asset: MarketUI.Asset, owner: MarketUI.Owner, amount: Double) -> MarketUI.Outcome {
        guard let e = store.engine else { return .refused("No game is open.") }
        let cur: Currency = e.homeCurrency
        switch owner {
        case .you:
            switch store.act({ (g: inout GameEngine) -> Brokerage.BuyResult in g.buyInvestment(asset.kind, symbol: asset.symbol, amount: amount) }) {
            case .ok?: return .done("Bought \(cur.tidyDisplay(amount)) of \(asset.name).")
            case .tooSmall?: return .refused("That order is too small.")
            case .delisted?: return .refused("Trading in \(asset.symbol) has stopped.")
            default: return .refused("Not enough money for that.")
            }
        case .holding(let id):
            let name: String = ownerName(e, owner)
            let ok: Bool = store.act({ (g: inout GameEngine) -> Bool in g.holdingInvest(holdingID: id, amount: amount) }) ?? false
            return ok ? .done("\(name) invested \(cur.tidyDisplay(amount)) in the index fund.") : .refused("Not enough cash in \(name)'s treasury.")
        }
    }

    /// Sells `fraction` of a position. Engine API: marketSell(position, fraction).
    @MainActor static func sell(_ store: GameStore, _ p: MarketUI.Position, fraction: Double) -> MarketUI.Outcome {
        guard let e = store.engine else { return .refused("No game is open.") }
        let cur: Currency = e.homeCurrency
        let f: Double = p.wholeOnly ? 1 : min(max(fraction, 0), 1)
        switch p.assetClass {
        case .crypto, .fund, .shares:
            if case .holding(let id) = p.owner {
                // Selling everything asks for more than is held, so no sliver is left behind by rounding.
                let amount: Double = f >= 0.999 ? p.value * 2 : p.value * f
                let ok: Bool = store.act({ (g: inout GameEngine) -> Bool in g.holdingDivest(holdingID: id, amount: amount) }) ?? false
                return ok ? .done("\(p.ownerName) sold \(cur.tidyDisplay(min(amount, p.value))) of the index fund.") : .refused("Nothing was sold.")
            }
            let kind: Brokerage.Kind = p.assetClass == .crypto ? .crypto : (p.assetClass == .fund ? .fund : .stock)
            let before: Double = p.value
            store.act { (g: inout GameEngine) -> Void in g.sellInvestment(kind, symbol: p.symbol, fraction: f) }
            let after: Double = store.engine?.quotes(kind).first { (q: Quote) -> Bool in q.symbol == p.symbol }?.value ?? 0
            return after < before ? .done("Sold \(cur.tidyDisplay(before - after)) of \(p.name).") : .refused("Nothing was sold: trading in \(p.symbol) has stopped.")
        case .startup:
            let got: Double = store.act({ (g: inout GameEngine) -> Double in g.sellStartupStake(stakeID: p.recordID, fraction: f) }) ?? 0
            return got > 0 ? .done("Sold shares in \(p.name) for \(cur.tidyDisplay(got)).") : .refused("That stake could not be sold.")
        case .privateEquity:
            let got: Double? = store.act({ (g: inout GameEngine) -> Double? in g.sellFundStake(fundID: p.recordID) }) ?? nil
            if let got { return .done("Sold your stake in \(p.name) for \(cur.tidyDisplay(got)).") }
            return .refused("That stake could not be sold.")
        case .groupStake, .partnership, .managed:
            return .refused("This stake is not sold here.")
        }
    }

    // MARK: Your companies against their markets

    /// The businesses that have a market (open, not a holding).
    static func companies(_ e: GameEngine) -> [Company] {
        e.state.companies.filter { (c: Company) -> Bool in c.status == .open && c.type != "hold" }
    }

    private static func market(_ e: GameEngine, companyID: Int) -> MarketMap.Market? {
        MarketMap.markets(e.state, data: e.data).first { (m: MarketMap.Market) -> Bool in m.companyIDs.contains(companyID) }
    }

    /// One line per company. Engine API: the per-company market comparison read (share, rank, price and rating against the average, history).
    static func companyLines(_ e: GameEngine) -> [MarketUI.CompanyLine] {
        let board: [ReviewGroup] = e.reviewBoard()
        return companies(e).map { (co: Company) -> MarketUI.CompanyLine in companyLine(e, co, board: board) }
    }

    static func companyLine(_ e: GameEngine, _ co: Company, board: [ReviewGroup]? = nil) -> MarketUI.CompanyLine {
        let m: MarketMap.Market? = market(e, companyID: co.id)
        let rivals: [RivalRow] = e.rivalRows(co)
        var level: MarketMap.Knowledge.Level = .feeling
        var shareText: String = "Not measured"
        var share: Double?
        var trend: Double?
        var rank: Int?
        var players: Int = rivals.count + 1
        if let m {
            let truth: MarketMap.Truth = MarketMap.truth(e.state, m, data: e.data)
            let know: MarketMap.Knowledge = MarketMap.knowledge(e.state, m)
            let mine: MarketMap.Estimate = MarketMap.estimate(truth.share, key: "my" + m.id, know, seed: e.state.seed, week: e.state.week)
            level = know.level
            shareText = MarketMap.text(mine)
            players = max(players, truth.players.count + 1)
            if know.level.canDrawShareGraph {
                let hist: [Double] = MarketMap.history(e.state, key: m.id).map { (h: (month: Int, share: Double, total: Double)) -> Double in h.share * 100 }
                share = mine.center * 100
                if hist.count >= 2 { trend = hist[hist.count - 1] - hist[hist.count - 2] }
            }
            if know.level != .feeling {
                let above: Int = rivals.filter { (r: RivalRow) -> Bool in (r.share?.center ?? 0) > mine.center }.count
                rank = above + 1
            }
        }
        var gap: Double?
        if let pm = e.priceMoves(co), let avg = pm.rivalsAverage, avg > 0 { gap = pm.yourTicket / avg - 1 }
        var rating: Double?
        var ratingGap: Double?
        let groups: [ReviewGroup] = board ?? e.reviewBoard()
        if let g = groups.first(where: { (g: ReviewGroup) -> Bool in g.rows.contains { (r: ReviewRow) -> Bool in r.companyID == co.id } }),
           let me = g.rows.first(where: { (r: ReviewRow) -> Bool in r.companyID == co.id }), me.count >= Reviews.minimumShown {
            rating = me.rating
            let others: [ReviewRow] = g.rows.filter { (r: ReviewRow) -> Bool in !r.mine && r.count >= Reviews.minimumShown }
            if !others.isEmpty { ratingGap = me.rating - others.reduce(0) { (a: Double, r: ReviewRow) -> Double in a + r.rating } / Double(others.count) }
        }
        return MarketUI.CompanyLine(id: co.id, name: co.name, trade: e.tradeName(co), city: e.cityName(co), marketKey: m?.id, level: level,
                                    shareText: shareText, share: share, trend: trend, rank: rank, players: players, priceGap: gap,
                                    rating: rating, ratingGap: ratingGap)
    }

    /// Your share month by month in percent, only where it is measured.
    static func shareHistory(_ e: GameEngine, companyID: Int) -> [Double] {
        guard let m = market(e, companyID: companyID), MarketMap.knowledge(e.state, m).level.canDrawShareGraph else { return [] }
        return MarketMap.history(e.state, key: m.id).map { (h: (month: Int, share: Double, total: Double)) -> Double in h.share * 100 }
    }

    /// You and your rivals, biggest first. Engine API: the comparison table of the per-company market read.
    static func compareRows(_ e: GameEngine, _ co: Company) -> [MarketUI.CompareRow] {
        let line: MarketUI.CompanyLine = companyLine(e, co)
        let rivals: [RivalRow] = e.rivalRows(co).sorted { (a: RivalRow, b: RivalRow) -> Bool in (a.share?.center ?? -1) > (b.share?.center ?? -1) }
        let groups: [ReviewGroup] = e.reviewBoard()
        let g: ReviewGroup? = groups.first { (g: ReviewGroup) -> Bool in g.rows.contains { (r: ReviewRow) -> Bool in r.companyID == co.id } }
        func ratingOf(_ rid: Int) -> Double? {
            guard let r = g?.rows.first(where: { (x: ReviewRow) -> Bool in x.rivalID == rid }), r.count >= Reviews.minimumShown else { return nil }
            return r.rating
        }
        var out: [MarketUI.CompareRow] = [MarketUI.CompareRow(id: "me", name: co.name, mine: true, rivalID: nil, shareText: line.shareText, priceText: "Your price",
                                                              rating: line.rating, sizeWord: "You", moneyWord: "", forSale: false)]
        for r in rivals {
            let same: Bool = abs(r.priceGap) < 0.03
            let pct: Int = Int((abs(r.priceGap) * 100).rounded())
            let price: String = same ? "Same price" : (r.priceGap > 0 ? "+\(pct)%" : "\u{2212}\(pct)%")
            out.append(MarketUI.CompareRow(id: "r\(r.id)", name: r.rival.name, mine: false, rivalID: r.id, shareText: r.share.map { (s: MarketMap.Estimate) -> String in MarketMap.text(s) } ?? r.feel,
                                           priceText: price, rating: ratingOf(r.id), sizeWord: r.sizeWord, moneyWord: r.feel, forSale: r.rival.forSale))
        }
        return out
    }

    /// What decides who wins customers in this market. Engine API: the market read's own "what wins" lines.
    static func whatWins(_ e: GameEngine, _ co: Company) -> [String] {
        var out: [String] = []
        if let t = e.data.catalog[co.type] {
            if t.elasticity >= 1.4 { out.append("Price decides") }
            else if t.elasticity <= 0.8 { out.append("Quality and name beat price") }
            else { out.append("Price and quality weigh the same") }
        }
        out.append("Known by \(Int(co.awareness.rounded()))% of people")
        out.append("Reputation \(Int(co.reputation.rounded())) of 100")
        if let m = market(e, companyID: co.id) {
            let know: MarketMap.Knowledge = MarketMap.knowledge(e.state, m)
            if know.level != .feeling { out.append(contentsOf: MarketMap.report(e.state, m, know, data: e.data).prefix(2).map { (s: String) -> String in s.tidyText }) }
        }
        return out
    }

    static func marketKey(_ e: GameEngine, companyID: Int) -> String? { market(e, companyID: companyID)?.id }

    // MARK: Rivals

    /// Every rival in your markets, for sale first, then the most valuable. Engine API: the rivals list read.
    static func rivals(_ e: GameEngine) -> [MarketUI.RivalItem] {
        var out: [MarketUI.RivalItem] = []
        for co in companies(e) {
            let country: String = e.data.countries[co.countryCode]?.name ?? co.countryCode
            for r in e.rivalRows(co) {
                let g: RivalGroups.Group? = RivalGroups.group(e.state, id: r.rival.groupID)
                out.append(MarketUI.RivalItem(companyID: co.id, rivalID: r.id, name: r.rival.name, owner: r.rival.owner, trade: e.tradeName(co), city: e.cityName(co),
                                              country: country, sizeWord: r.sizeWord, valuation: e.rivalValue(companyID: co.id, rivalID: r.id), moneyWord: r.feel,
                                              forSale: r.rival.forSale, inTrouble: r.rival.fortune < 0 || (g?.inTrouble ?? false), groupID: g?.id, groupName: g?.name,
                                              shareText: r.share.map { (s: MarketMap.Estimate) -> String in MarketMap.text(s) } ?? r.feel, yourCompany: co.name))
            }
        }
        return out.sorted { (a: MarketUI.RivalItem, b: MarketUI.RivalItem) -> Bool in
            if a.forSale != b.forSale { return a.forSale }
            return a.valuation > b.valuation
        }
    }

    /// The rival groups that compete where you are.
    static func groups(_ e: GameEngine) -> [MarketUI.GroupItem] {
        var seen: Set<String> = []
        var out: [MarketUI.GroupItem] = []
        for g in e.rivalGroupsAround() where !seen.contains(g.id) {
            seen.insert(g.id)
            out.append(MarketUI.GroupItem(id: g.id, name: g.name, owner: g.owner, strategy: g.strategyName, sites: g.branches, revenue: g.revenue, profit: g.profit,
                                          inTrouble: g.inTrouble, countries: g.countries.map { (c: String) -> String in e.data.countries[c]?.name ?? c },
                                          rivalsInYourMarkets: e.rivalsOfGroup(g.id).count))
        }
        return out.sorted { (a: MarketUI.GroupItem, b: MarketUI.GroupItem) -> Bool in a.revenue > b.revenue }
    }

    // MARK: Overview

    /// Your share of everything you sell into, weighted by market size, where it is at least estimated; nil when nothing is measured.
    /// Engine API: the overview's combined share.
    static func combinedShare(_ e: GameEngine) -> Double? {
        var have: Double = 0
        var total: Double = 0
        for m in MarketMap.markets(e.state, data: e.data) {
            let know: MarketMap.Knowledge = MarketMap.knowledge(e.state, m)
            guard know.level != .feeling else { continue }
            let truth: MarketMap.Truth = MarketMap.truth(e.state, m, data: e.data)
            let est: MarketMap.Estimate = MarketMap.estimate(truth.share, key: "my" + m.id, know, seed: e.state.seed, week: e.state.week)
            have += est.center * truth.total
            total += truth.total
        }
        return total > 0 ? have / total : nil
    }

    /// The week's biggest moves: a position that moved, a market share that moved. Engine API: overview movers.
    static func movers(_ e: GameEngine) -> [MarketUI.Mover] {
        var out: [MarketUI.Mover] = []
        for p in portfolio(e).positions {
            guard let w = p.weekChange, abs(w) >= 0.005 else { continue }
            out.append(MarketUI.Mover(id: p.id, title: p.name, detail: p.ownerName == "You" ? p.assetClass.word : p.ownerName, change: w, points: false,
                                      amount: p.value - p.value / (1 + w)))
        }
        for l in companyLines(e) {
            guard let t = l.trend, abs(t) >= 0.3 else { continue }
            out.append(MarketUI.Mover(id: "co\(l.id)", title: l.name, detail: "Market share last month", change: t, points: true, amount: nil))
        }
        return Array(out.sorted { (a: MarketUI.Mover, b: MarketUI.Mover) -> Bool in abs(a.amount ?? a.change * 1000) > abs(b.amount ?? b.change * 1000) }.prefix(3))
    }

    /// Up to three openings: a rival for sale or in trouble, a busy city where you are not, an asset that fell. Engine API: overview opportunities.
    static func opportunities(_ e: GameEngine) -> [MarketUI.Signal] {
        var out: [MarketUI.Signal] = []
        let cur: Currency = e.homeCurrency
        if let r = rivals(e).first(where: { (r: MarketUI.RivalItem) -> Bool in r.forSale || r.inTrouble }) {
            out.append(MarketUI.Signal(id: "rival", title: r.forSale ? "\(r.name) is for sale" : "\(r.name) is short of money",
                                       detail: "\(r.trade) in \(r.city) \u{00B7} worth about \(cur.tidyShort(r.valuation))", tone: "gold", glyph: Glyph.market,
                                       target: .rival(r.companyID, r.rivalID)))
        }
        if let c = busyCity(e) {
            out.append(MarketUI.Signal(id: "city", title: "\(c.city) wants more \(c.trade.lowercased())", detail: c.detail, tone: "n", glyph: Glyph.world, target: .country(c.country)))
        }
        if let a = assets(e).filter({ (a: MarketUI.Asset) -> Bool in (a.weekChange ?? 0) <= -0.05 }).min(by: { (a: MarketUI.Asset, b: MarketUI.Asset) -> Bool in (a.weekChange ?? 0) < (b.weekChange ?? 0) }) {
            let pct: Int = Int((abs(a.weekChange ?? 0) * 100).rounded())
            out.append(MarketUI.Signal(id: "dip", title: "\(a.name) is down \(pct)% this week", detail: a.risk + " \u{00B7} " + a.note, tone: "n", glyph: Glyph.invest, target: .asset(a.id)))
        }
        return Array(out.prefix(3))
    }

    private struct BusyCity { var city: String; var trade: String; var country: String; var detail: String }

    /// The city with the strongest demand in a country you are in, for one of your trades, where you have no company of that trade.
    private static func busyCity(_ e: GameEngine) -> BusyCity? {
        var best: (score: Double, pick: BusyCity)?
        for co in companies(e) {
            guard let country = e.data.countries[co.countryCode] else { continue }
            let taken: Set<String> = Set(e.state.companies.filter { (c: Company) -> Bool in c.type == co.type && c.status.isLive }.map { (c: Company) -> String in c.cityID })
            for city in country.coreCities where !taken.contains(city.id) {
                let score: Double = city.demand * city.population
                if best == nil || score > (best?.score ?? 0) {
                    let demand: String = city.demand >= 1.1 ? "Strong demand" : city.demand >= 0.95 ? "Average demand" : "Quieter demand"
                    best = (score, BusyCity(city: city.name, trade: e.tradeName(co), country: country.code,
                                            detail: "\(demand) \u{00B7} \(Int(city.population.rounded()).formatted())k people"))
                }
            }
        }
        return best?.pick
    }

    /// Rivals cutting their prices on you and new entrants. Engine API: overview threats.
    static func threats(_ e: GameEngine) -> [MarketUI.Signal] {
        var out: [MarketUI.Signal] = []
        for co in companies(e) {
            for r in e.rivalRows(co) {
                guard let cut = e.rivalPriceCut(companyID: co.id, rivalID: r.id), cut.answered == nil else { continue }
                out.append(MarketUI.Signal(id: "cut\(co.id).\(r.id)", title: "\(r.rival.name) cut prices \(cut.pct)%", detail: "Against \(co.name) \u{00B7} until week \(cut.end)",
                                           tone: "bad", glyph: Glyph.warning, target: .rival(co.id, r.id)))
            }
        }
        for m in e.marketEvents(limit: 20) where m.kind == .competitorLaunch || (m.kind == .priceResponse && m.tone == "bad") {
            let target: MarketUI.Signal.Target = m.companyID.map { (id: Int) -> MarketUI.Signal.Target in .company(id) } ?? .nothing
            guard !out.contains(where: { (s: MarketUI.Signal) -> Bool in s.title == m.title.tidyText }) else { continue }
            out.append(MarketUI.Signal(id: "ev\(m.id)", title: m.title.tidyText, detail: MarketEventRows.impact(m),
                                       tone: "bad", glyph: Glyph.market, target: target))
        }
        return Array(out.prefix(3))
    }

    // MARK: World

    /// Every country, yours first. Engine API: the world read (demand, competition, costs and tax per country).
    static func countries(_ e: GameEngine) -> [MarketUI.CountryLine] {
        let live: [Company] = e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }
        let lines: [MarketUI.CountryLine] = e.data.countries.countries.map { (c: Country) -> MarketUI.CountryLine in
            MarketUI.CountryLine(id: c.code, name: c.name, flag: c.flag, region: c.region, population: c.populationMillions, currency: c.currencyCode,
                                 corporateTax: c.corporateTax, demand: c.marketStrength, wages: c.wageLevel, rents: c.rentLevel,
                                 rivalGroups: RivalGroups.groups(e.state, country: c.code).count,
                                 yourCompanies: live.filter { (co: Company) -> Bool in co.countryCode == c.code }.count, isHome: c.code == e.state.homeCountryCode)
        }
        return lines.sorted { (a: MarketUI.CountryLine, b: MarketUI.CountryLine) -> Bool in
            if a.isHome != b.isHome { return a.isHome }
            if (a.yourCompanies > 0) != (b.yourCompanies > 0) { return a.yourCompanies > 0 }
            return a.name < b.name
        }
    }

    /// Your companies that could open in `country` (a home-country company opens a branch abroad; at home a new company starts).
    static func expanders(_ e: GameEngine, country: String) -> [Company] {
        companies(e).filter { (co: Company) -> Bool in e.abroadOptions(companyID: co.id).contains { (o: Abroad.Option) -> Bool in o.countryCode == country } }
    }
}

/// Rivals you follow, kept on this device per game (`@AppStorage(MarketWatchlist.key)` holds "seed|id" entries) until the engine keeps a
/// watchlist. Engine API: the engine's rival watchlist.
enum MarketWatchlist {
    static let key = "market.watch"

    static func ids(_ raw: String, seed: Int) -> Set<String> {
        let prefix: String = "\(seed)|"
        let mine: [String] = raw.split(separator: ",").map { (s: Substring) -> String in String(s) }.filter { (s: String) -> Bool in s.hasPrefix(prefix) }
        return Set(mine.map { (s: String) -> String in String(s.dropFirst(prefix.count)) })
    }

    /// The stored text with `id` added, or removed when it was there.
    static func toggled(_ raw: String, seed: Int, id: String) -> String {
        let entry: String = "\(seed)|\(id)"
        var all: [String] = raw.split(separator: ",").map { (s: Substring) -> String in String(s) }
        if let i = all.firstIndex(of: entry) { all.remove(at: i) } else { all.append(entry) }
        return all.joined(separator: ",")
    }
}
