import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Investments
import Events
import Simulation

// The one door between the Market app and the engine's Market API (Simulation/Market*.swift): the portfolio of every owner with cost
// basis and results, marketQuote / marketBuy / marketSell, each company against its market, the rivals list and watchlist, the overview
// signals and the world reads. Screens read the small `MarketUI` value types made here, so a change of the API stays in this file.

/// The Market app's own value types, kept in one namespace so they never clash with engine types of the same idea.
enum MarketUI {
    /// The five parts of the app.
    enum Tab: String, CaseIterable, Hashable {
        case overview = "Overview", companies = "Companies", rivals = "Rivals", invest = "Invest", world = "World"
    }

    /// Who holds a position or pays for a purchase: you (`.player`) or a holding company's treasury (`.holding(id)`).
    typealias Owner = PortfolioOwner

    struct OwnerInfo: Identifiable, Hashable {
        var owner: Owner
        var name: String
        /// What this owner can spend now: current account and savings for you, the treasury cash for a holding.
        var cash: Double
        var id: String { owner.id }
    }

    /// What kind of thing a position is.
    enum AssetClass: String, Hashable {
        case crypto, fund, shares, deposit, startup, privateEquity, groupStake, partnership, managed
        init(_ k: MarketAssetKind) {
            switch k {
            case .indexFund, .bondFund, .moneyMarketFund: self = .fund
            case .crypto: self = .crypto
            case .stock: self = .shares
            case .managedFund: self = .managed
            case .fixedDeposit: self = .deposit
            case .startupStake: self = .startup
            case .privateEquity: self = .privateEquity
            case .groupStake: self = .groupStake
            case .companyStake: self = .partnership
            }
        }
        var word: String {
            switch self {
            case .crypto: return "Crypto"
            case .fund: return "Fund"
            case .shares: return "Shares"
            case .deposit: return "Fixed deposit"
            case .startup: return "Startup stake"
            case .privateEquity: return "Private equity"
            case .groupStake: return "Stake in a group"
            case .partnership: return "Company stake"
            case .managed: return "Fund manager"
            }
        }
        var glyph: String {
            switch self {
            case .crypto: return Glyph.luxury
            case .fund: return Glyph.invest
            case .shares: return Glyph.stats
            case .deposit: return Glyph.bank
            case .startup: return Glyph.ventures
            case .privateEquity, .groupStake, .partnership: return Glyph.group
            case .managed: return Glyph.person
            }
        }
        /// Units mean something to the player only for funds, crypto and shares.
        var countsUnits: Bool { self == .fund || self == .crypto || self == .shares }
    }

    /// One holding of one owner.
    struct Position: Identifiable, Hashable {
        var id: String
        var owner: Owner
        var ownerName: String
        var assetClass: AssetClass
        /// The asset behind it (for "Buy more"); nil for what cannot be bought here.
        var assetID: String?
        var name: String
        var symbol: String
        /// Units as the engine keeps them (a stake's ownership in percent), for selling.
        var engineUnits: Double
        var price: Double
        var cost: Double
        var costKnown: Bool
        var value: Double
        var pnl: Double
        var pnlShare: Double?
        var pnlWeek: Double
        var pnlToday: Double
        var allocation: Double
        var history: [Double]
        var risk: String
        var sellable: Bool
        var sellNote: String?
        /// A private equity stake sells in one piece on the secondary market.
        var wholeOnly: Bool
        /// Units to show (funds, crypto, shares); nil for stakes and deposits.
        var units: Double? { assetClass.countsUnits ? engineUnits : nil }
        /// The latest weekly price move, as a share.
        var weekChange: Double? {
            guard history.count >= 2, history[history.count - 2] > 0 else { return nil }
            return history[history.count - 1] / history[history.count - 2] - 1
        }
    }

    /// Something that can be bought here.
    struct Asset: Identifiable, Hashable {
        var id: String
        var kind: MarketAssetKind
        var symbol: String
        var name: String
        var price: Double
        var weekChange: Double?
        var history: [Double]
        var risk: String
        var note: String
        var holdingsMayBuy: Bool
    }

    struct Portfolio {
        var positions: [Position]
        /// The engine's totals (nil for an owner with nothing yet).
        var totals: PortfolioTotals?
        var owners: [PortfolioOwnerSummary]
        /// Total value at each week's end, oldest first.
        var history: [Double]
        var value: Double { totals?.value ?? 0 }
        var cost: Double { totals?.costBasis ?? 0 }
        var pnl: Double { totals?.pnl ?? 0 }
        var pnlShare: Double? { totals?.pnlPercent }
        var pnlToday: Double { totals?.pnlToday ?? 0 }
        /// The week's move, nil while nothing is held.
        var weekMove: Double? { positions.isEmpty ? nil : totals?.pnlWeek }
        func only(_ owner: Owner?) -> Portfolio {
            guard let owner else { return self }
            let t: PortfolioTotals? = owners.first { (o: PortfolioOwnerSummary) -> Bool in o.owner == owner }?.totals
            return Portfolio(positions: positions.filter { (p: Position) -> Bool in p.owner == owner }, totals: t, owners: owners, history: [])
        }
        static let empty = Portfolio(positions: [], totals: nil, owners: [], history: [])
    }

    /// What a trade would do, before it is made (from `marketQuote` / `marketSellQuote`).
    struct TradePreview: Equatable {
        /// Buying: what is invested. Selling: the value sold.
        var amount: Double
        var fee: Double
        var feeLabel: String
        var units: Double
        /// Buying: what leaves the owner's cash. Selling: what reaches it.
        var cashChange: Double
        var available: Double
        var cashAfter: Double
        var minimum: Double
        /// Selling: the result realised (what reaches the account minus the cost of the units sold).
        var realizedGain: Double
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
        /// Your place by sales among everybody in this market.
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
        var watched: Bool
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

/// The reads and trades of the Market app, from the engine's Market API. Pure functions of the engine; trades go through `GameStore.act`.
enum MarketData {
    // MARK: Owners

    /// You, then every open holding, with what each can invest now.
    static func owners(_ e: GameEngine) -> [MarketUI.OwnerInfo] {
        e.marketOwners.map { (o: PortfolioOwnerSummary) -> MarketUI.OwnerInfo in MarketUI.OwnerInfo(owner: o.owner, name: o.name, cash: max(0, o.cash)) }
    }

    static func ownerName(_ e: GameEngine, _ o: MarketUI.Owner) -> String {
        switch o {
        case .player: return "You"
        case .holding(let id): return e.state.company(id)?.name ?? "Holding"
        }
    }

    // MARK: Portfolio

    static func position(_ p: PortfolioPosition) -> MarketUI.Position {
        let cls: MarketUI.AssetClass = MarketUI.AssetClass(p.kind)
        return MarketUI.Position(id: p.id, owner: p.owner, ownerName: p.ownerName, assetClass: cls, assetID: p.assetID, name: p.name.tidyText,
                                 symbol: p.symbol, engineUnits: p.units, price: p.price, cost: p.costBasis, costKnown: p.costBasis > 0.5, value: p.value,
                                 pnl: p.pnl, pnlShare: p.pnlPercent, pnlWeek: p.pnlWeek, pnlToday: p.pnlToday, allocation: p.allocation,
                                 history: p.history, risk: p.risk.rawValue + " risk", sellable: p.canSell && !p.delisted, sellNote: p.sellNote,
                                 wholeOnly: p.kind == .privateEquity)
    }

    /// Every position of every owner, with the engine's totals and weekly history.
    static func portfolio(_ e: GameEngine) -> MarketUI.Portfolio {
        let pf: Portfolio = e.portfolio
        return MarketUI.Portfolio(positions: pf.positions.map { (p: PortfolioPosition) -> MarketUI.Position in position(p) }, totals: pf.totals,
                                  owners: pf.owners, history: pf.history)
    }

    static func position(_ e: GameEngine, id: String) -> MarketUI.Position? {
        e.portfolio.positions.first { (p: PortfolioPosition) -> Bool in p.id == id }.map { (p: PortfolioPosition) -> MarketUI.Position in position(p) }
    }

    /// The portfolio's total value at each week's end (you and every holding), for the hero line.
    static func investedHistory(_ e: GameEngine) -> [Double] {
        Array(e.portfolio.history.suffix(52))
    }

    // MARK: What can be bought

    /// Funds, crypto and money for your fund manager; closed coins are left out.
    static func assets(_ e: GameEngine) -> [MarketUI.Asset] {
        e.marketAssets.filter { (a: MarketAsset) -> Bool in !a.closed }.map { (a: MarketAsset) -> MarketUI.Asset in
            MarketUI.Asset(id: a.id, kind: a.kind, symbol: a.symbol, name: a.name.tidyText, price: a.price, weekChange: a.weekChange,
                           history: Array(a.history.suffix(26)), risk: a.risk.rawValue + " risk", note: a.costNote.tidyText, holdingsMayBuy: a.holdingsMayBuy)
        }
    }

    static func asset(_ e: GameEngine, id: String) -> MarketUI.Asset? {
        assets(e).first { (a: MarketUI.Asset) -> Bool in a.id == id }
    }

    /// Why `owner` cannot hold `asset` at all (before any amount is chosen).
    static func refusal(_ asset: MarketUI.Asset, for owner: MarketUI.Owner) -> String? {
        if case .holding = owner, !asset.holdingsMayBuy { return "A holding's treasury holds funds only" }
        return nil
    }

    // MARK: Quotes and trades

    static func preview(_ q: MarketQuote) -> MarketUI.TradePreview {
        MarketUI.TradePreview(amount: q.amount, fee: q.fee + q.spreadCost, feeLabel: q.feeLabel, units: q.units, cashChange: abs(q.cashChange),
                              available: q.available, cashAfter: q.cashAfter, minimum: q.minimum, realizedGain: q.realizedGain, refusal: q.refusal)
    }

    /// Buying `amount` of `asset` for `owner`.
    static func buyPreview(_ e: GameEngine, _ asset: MarketUI.Asset, owner: MarketUI.Owner, amount: Double) -> MarketUI.TradePreview {
        var p: MarketUI.TradePreview = preview(e.marketQuote(asset: asset.id, owner: owner, amount: amount))
        if amount <= 0 { p.refusal = "Enter an amount." }
        return p
    }

    /// Selling `fraction` (0...1) of a position.
    static func sellPreview(_ e: GameEngine, _ p: MarketUI.Position, fraction: Double) -> MarketUI.TradePreview {
        let f: Double = p.wholeOnly ? 1 : min(max(fraction, 0), 1)
        return preview(e.marketSellQuote(position: p.id, units: p.engineUnits * f))
    }

    @MainActor static func buy(_ store: GameStore, _ asset: MarketUI.Asset, owner: MarketUI.Owner, amount: Double) -> MarketUI.Outcome {
        guard let e = store.engine else { return .refused("No game is open.") }
        let cur: Currency = e.homeCurrency
        guard let r = store.act({ (g: inout GameEngine) -> MarketTradeResult in g.marketBuy(asset: asset.id, owner: owner, amount: amount) }) else {
            return .refused("No game is open.")
        }
        if r.done { return .done("\(ownerName(e, owner) == "You" ? "Bought" : ownerName(e, owner) + " bought") \(cur.tidyDisplay(amount)) of \(asset.name).") }
        return .refused(r.refusal ?? "The purchase did not go through.")
    }

    @MainActor static func sell(_ store: GameStore, _ p: MarketUI.Position, fraction: Double) -> MarketUI.Outcome {
        guard let e = store.engine else { return .refused("No game is open.") }
        let cur: Currency = e.homeCurrency
        let f: Double = p.wholeOnly ? 1 : min(max(fraction, 0), 1)
        guard let r = store.act({ (g: inout GameEngine) -> MarketTradeResult in g.marketSell(position: p.id, units: p.engineUnits * f) }) else {
            return .refused("No game is open.")
        }
        if r.done { return .done("Sold \(p.name): \(cur.tidyDisplay(r.cashChange)) received, result \(MarketFormat.money(r.realizedGain, cur)).") }
        return .refused(r.refusal ?? "The sale did not go through.")
    }

    // MARK: Your companies against their markets

    /// The businesses that have a market (open, not a holding).
    static func companies(_ e: GameEngine) -> [Company] {
        e.state.companies.filter { (c: Company) -> Bool in c.status == .open && c.type != "hold" }
    }

    private static func line(_ m: CompanyMarketPosition) -> MarketUI.CompanyLine {
        let measured: Bool = m.knowledge.canDrawShareGraph
        return MarketUI.CompanyLine(id: m.companyID, name: m.name, trade: m.tradeName, city: m.cityName, marketKey: m.marketKey, level: m.knowledge,
                                    shareText: m.shareText, share: measured ? m.share * 100 : nil, trend: measured ? m.shareChange.map { (c: Double) -> Double in c * 100 } : nil,
                                    rank: m.rank, players: m.of, priceGap: m.priceIndex.map { (x: Double) -> Double in x - 1 }, rating: m.rating,
                                    ratingGap: m.ratingVsMarket)
    }

    /// One line per company that has a market.
    static func companyLines(_ e: GameEngine) -> [MarketUI.CompanyLine] {
        e.marketPositions().map { (m: CompanyMarketPosition) -> MarketUI.CompanyLine in line(m) }
    }

    static func companyLine(_ e: GameEngine, _ co: Company) -> MarketUI.CompanyLine {
        if let m = e.marketPosition(companyID: co.id) { return line(m) }
        return MarketUI.CompanyLine(id: co.id, name: co.name, trade: e.tradeName(co), city: e.cityName(co), marketKey: nil, level: .feeling,
                                    shareText: "Not measured", share: nil, trend: nil, rank: nil, players: 1, priceGap: nil, rating: nil, ratingGap: nil)
    }

    /// Your share month by month in percent, only where it is measured.
    static func shareHistory(_ e: GameEngine, companyID: Int) -> [Double] {
        guard let m = e.marketPosition(companyID: companyID), m.knowledge.canDrawShareGraph else { return [] }
        return m.shareHistory.map { (s: Double) -> Double in s * 100 }
    }

    /// Everybody in the market, biggest first. Without an analyst a rival's share is a size word.
    static func compareRows(_ e: GameEngine, _ co: Company) -> [MarketUI.CompareRow] {
        guard let m = e.marketPosition(companyID: co.id) else { return [] }
        let measured: Bool = m.knowledge != .feeling
        return m.competitors.map { (c: MarketCompetitor) -> MarketUI.CompareRow in
            let share: String = c.isYours ? m.shareText : (measured ? pct(c.share) : c.sizeWord)
            let price: String = c.priceIndex.map { (x: Double) -> String in abs(x - 1) < 0.03 ? "Market price" : MarketFormat.percent(x - 1, decimals: 0) } ?? ""
            let growth: String = c.growth.map { (g: Double) -> String in MarketFormat.percent(g, decimals: 0) + " a year" } ?? ""
            return MarketUI.CompareRow(id: c.id, name: c.name, mine: c.isYours, rivalID: c.rivalID, shareText: share, priceText: price, rating: c.rating,
                                       sizeWord: c.isYours ? "You" : c.sizeWord, moneyWord: c.isYours ? growth : (c.groupName ?? ""), forSale: c.forSale)
        }
    }

    private static func pct(_ v: Double) -> String { v < 0.1 ? String(format: "%.1f%%", v * 100) : String(format: "%.0f%%", v * 100) }

    static func whatWins(_ e: GameEngine, _ co: Company) -> [String] {
        var out: [String] = []
        if let t = e.data.catalog[co.type] {
            if t.elasticity >= 1.4 { out.append("Price decides") }
            else if t.elasticity <= 0.8 { out.append("Quality and name beat price") }
            else { out.append("Price and quality weigh the same") }
        }
        out.append("Name: " + StandingWords.awareness(co.awareness).lowercased())
        out.append("Reputation: " + StandingWords.reputation(co.reputation).lowercased())
        if let m = MarketMap.markets(e.state, data: e.data).first(where: { (x: MarketMap.Market) -> Bool in x.companyIDs.contains(co.id) }) {
            let know: MarketMap.Knowledge = MarketMap.knowledge(e.state, m)
            if know.level != .feeling { out.append(contentsOf: MarketMap.report(e.state, m, know, data: e.data).prefix(2).map { (s: String) -> String in s.tidyText }) }
        }
        return out
    }

    static func marketKey(_ e: GameEngine, companyID: Int) -> String? { e.marketPosition(companyID: companyID)?.marketKey }

    // MARK: Rivals

    /// Every rival in your markets, for sale first, then the most valuable.
    static func rivals(_ e: GameEngine) -> [MarketUI.RivalItem] {
        let names: [Int: String] = Dictionary(uniqueKeysWithValues: e.state.companies.map { (c: Company) -> (Int, String) in (c.id, c.name) })
        let list: [MarketUI.RivalItem] = e.marketRivals().map { (r: MarketRivalRow) -> MarketUI.RivalItem in
            MarketUI.RivalItem(companyID: r.companyID, rivalID: r.id, name: r.name, owner: r.owner, trade: r.tradeName, city: r.cityName,
                               country: e.data.countries[r.countryCode]?.name ?? r.countryCode, sizeWord: r.sizeWord, valuation: r.valuation,
                               moneyWord: r.isNewEntrant ? "New" : r.strategy, forSale: r.forSale, inTrouble: r.inTrouble, groupID: r.groupID,
                               groupName: r.groupName, shareText: pct(r.share), yourCompany: names[r.companyID] ?? "", watched: r.watched)
        }
        return list.sorted { (a: MarketUI.RivalItem, b: MarketUI.RivalItem) -> Bool in
            if a.forSale != b.forSale { return a.forSale }
            return a.valuation > b.valuation
        }
    }

    /// The rival groups that compete where you are.
    static func groups(_ e: GameEngine) -> [MarketUI.GroupItem] {
        e.marketRivalGroups().map { (g: MarketGroupRow) -> MarketUI.GroupItem in
            MarketUI.GroupItem(id: g.id, name: g.name, owner: g.owner, strategy: g.strategyName, sites: g.branches, revenue: g.revenue, profit: g.profit,
                               inTrouble: g.inTrouble, countries: g.countries.map { (c: String) -> String in e.data.countries[c]?.name ?? c },
                               rivalsInYourMarkets: g.rivalIDs.count)
        }.sorted { (a: MarketUI.GroupItem, b: MarketUI.GroupItem) -> Bool in a.revenue > b.revenue }
    }

    static func isWatched(_ e: GameEngine, rivalID: Int) -> Bool { e.isWatched(rivalID: rivalID) }

    @MainActor static func toggleWatch(_ store: GameStore, rivalID: Int) {
        _ = store.act { (g: inout GameEngine) -> Bool in g.toggleWatch(rivalID: rivalID) }
    }

    // MARK: Overview

    /// Your sales against all sales of your local markets together; nil without a local market or while no analyst measures.
    static func combinedShare(_ e: GameEngine) -> Double? {
        guard e.marketPositions().contains(where: { (m: CompanyMarketPosition) -> Bool in m.knowledge != .feeling }) else { return nil }
        return e.marketOverview.combinedShare
    }

    static func movers(_ e: GameEngine) -> [MarketUI.Mover] {
        e.marketMovers(limit: 3).map { (m: MarketMover) -> MarketUI.Mover in
            switch m.kind {
            case .marketShare:
                return MarketUI.Mover(id: m.id, title: m.title.tidyText, detail: m.detail.tidyText, change: m.change * 100, points: true, amount: nil)
            case .investment:
                return MarketUI.Mover(id: m.id, title: m.title.tidyText, detail: m.detail.tidyText, change: m.relativeChange, points: false, amount: m.change)
            }
        }
    }

    static func opportunities(_ e: GameEngine) -> [MarketUI.Signal] {
        e.marketOpportunities(limit: 3).map { (o: MarketOpportunity) -> MarketUI.Signal in
            let target: MarketUI.Signal.Target
            let glyph: String
            switch o.kind {
            case .rivalForSale, .rivalInTrouble:
                glyph = Glyph.market
                if let c = o.companyID, let r = o.rivalID { target = .rival(c, r) } else { target = .nothing }
            case .openCity:
                glyph = Glyph.world
                target = o.countryCode.map { (c: String) -> MarketUI.Signal.Target in .country(c) } ?? .nothing
            case .fundDip:
                glyph = Glyph.invest
                target = o.assetID.map { (a: String) -> MarketUI.Signal.Target in .asset(a) } ?? .nothing
            }
            return MarketUI.Signal(id: o.id, title: o.title.tidyText, detail: o.detail.tidyText, tone: o.kind == .rivalForSale ? "gold" : "n",
                                   glyph: glyph, target: target)
        }
    }

    static func threats(_ e: GameEngine) -> [MarketUI.Signal] {
        e.marketThreats(limit: 3).map { (t: MarketThreat) -> MarketUI.Signal in
            let target: MarketUI.Signal.Target = t.rivalID.map { (r: Int) -> MarketUI.Signal.Target in .rival(t.companyID, r) } ?? .company(t.companyID)
            return MarketUI.Signal(id: t.id, title: t.title.tidyText, detail: t.detail.tidyText, tone: "bad", glyph: Glyph.warning, target: target)
        }
    }

    // MARK: World

    /// Every country, home first, then yours, then by name.
    static func countries(_ e: GameEngine) -> [MarketUI.CountryLine] {
        let lines: [MarketUI.CountryLine] = e.marketCountries().map { (c: MarketCountry) -> MarketUI.CountryLine in
            MarketUI.CountryLine(id: c.code, name: c.name, flag: c.flag, region: c.region, population: c.populationMillions,
                                 currency: e.data.countries[c.code]?.currencyCode ?? "", corporateTax: c.corporateTax, demand: c.marketStrength,
                                 wages: c.wageLevel, rents: c.rentLevel, rivalGroups: RivalGroups.groups(e.state, country: c.code).count,
                                 yourCompanies: c.yourCompanies, isHome: c.isHome)
        }
        return lines.sorted { (a: MarketUI.CountryLine, b: MarketUI.CountryLine) -> Bool in
            if a.isHome != b.isHome { return a.isHome }
            if (a.yourCompanies > 0) != (b.yourCompanies > 0) { return a.yourCompanies > 0 }
            return a.name < b.name
        }
    }

    /// The cities of a country, biggest first, with demand and rivals for `tradeID` when one is given.
    static func cities(_ e: GameEngine, country: String, tradeID: String? = nil) -> [MarketCity] {
        e.marketCities(countryCode: country, tradeID: tradeID).sorted { (a: MarketCity, b: MarketCity) -> Bool in a.population > b.population }
    }

    /// Your companies that could open in `country`.
    static func expanders(_ e: GameEngine, country: String) -> [Company] {
        e.state.companies.filter { (co: Company) -> Bool in
            co.status == .open && co.type != "hold" && e.abroadOptions(companyID: co.id).contains { (o: Abroad.Option) -> Bool in o.countryCode == country }
        }
    }
}
