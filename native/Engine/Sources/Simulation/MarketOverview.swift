import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

/// A big change of the latest period: the market share of one of your companies (monthly snapshots) or an investment (the week's price move).
public struct MarketMover: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case marketShare, investment }
    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    /// Share points (0...1 scale) for a market share, money for an investment.
    public var change: Double
    /// The change against where it started (0.1 = up a tenth); movers are ranked by its size.
    public var relativeChange: Double
    public var isGain: Bool
    public var companyID: Int?
    public var positionID: String?
}

public struct MarketOpportunity: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// A rival whose owner wants to sell, or one in money trouble that may sell cheaply.
        case rivalForSale, rivalInTrouble
        /// A city with strong demand for a trade you run and few rivals, where you have no company of that trade.
        case openCity
        /// A fund or coin down 5% or more over four weeks.
        case fundDip
    }
    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    public var companyID: Int?
    public var rivalID: Int?
    public var cityID: String?
    public var countryCode: String?
    public var tradeID: String?
    public var assetID: String?
    /// The rival's value, the estimated start cost, or the asset's price.
    public var amount: Double?
}

public struct MarketThreat: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// A rival selling at least 10% under you, or running a discount.
        case undercut
        /// A rival that opened in the last eight weeks.
        case newEntrant
        /// A cut-price newcomer working a loophole (it drags the whole market's prices).
        case cheapEntrant
        /// Your share fell two points or more in the latest month.
        case losingShare
    }
    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    public var companyID: Int
    public var rivalID: Int?
    /// 0...1, for ordering.
    public var severity: Double
}

/// The Market overview: your position across markets, everything invested, and what deserves a look.
public struct MarketOverview: Equatable {
    /// Your sales against all sales in your local markets together (nil without a local market).
    public var combinedShare: Double?
    public var markets: Int
    /// Markets where you sell the most.
    public var marketsLed: Int
    /// Your group's place by sales among the companies of your home country.
    public var groupRank: Int?
    public var groupRankOf: Int?
    public var invested: PortfolioTotals
    /// Total value invested at each week's end, oldest first.
    public var investedHistory: [Double]
    public var movers: [MarketMover]
    public var opportunities: [MarketOpportunity]
    public var threats: [MarketThreat]
}

/// A country as a place to do business.
public struct MarketCountry: Identifiable, Equatable, Sendable {
    public var id: String { code }
    public var code: String
    public var name: String, flag: String, region: String
    public var isHome: Bool
    public var populationMillions: Double
    /// How much people buy (1 = the reference economy), and the price, rent and wage levels against it.
    public var marketStrength: Double
    public var priceLevel: Double, rentLevel: Double, wageLevel: Double
    public var corporateTax: Double, vatStandard: Double, dividendTax: Double, employerSocial: Double
    public var cities: Int
    public var yourCompanies: Int
    /// A compliance desk at your head office makes registering there faster.
    public var hasDesk: Bool
}

/// A city as a place to open in. Levels are absolute (the country's level times the city's).
public struct MarketCity: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var countryCode: String
    /// Thousands of people.
    public var population: Double
    public var demand: Double
    public var priceLevel: Double, rentLevel: Double, wageLevel: Double
    public var touristIndex: Double
    /// For the trade asked about: customers an average company can expect (1 = an average place), the word for it, and the rivals there
    /// (the running market's count where you are, else the expected count).
    public var tradeID: String?
    public var tradeDemand: Double?
    public var tradeDemandLevel: CityMarket.DemandLevel?
    public var rivals: Int?
    public var yourCompanies: Int
    public var isHomeCity: Bool
}

public extension GameEngine {
    // MARK: Overview

    var marketOverview: MarketOverview {
        let positions = marketPositions()
        let pf = portfolio
        var mine = 0.0, total = 0.0
        var led = 0
        var seenMarkets = Set<String>()
        for p in positions where !seenMarkets.contains(p.marketKey) {
            seenMarkets.insert(p.marketKey)
            if !p.national { mine += p.competitors.filter { $0.isYours }.reduce(0) { $0 + $1.revenue }; total += p.marketSales }
            if p.competitors.first?.isYours == true { led += 1 }
        }
        let rank = yourRanking(scope: .country, metric: .revenue)
        return MarketOverview(combinedShare: total > 0 ? mine / total : nil, markets: seenMarkets.count, marketsLed: led, groupRank: rank?.rank, groupRankOf: rank?.of,
                              invested: pf.totals, investedHistory: pf.history, movers: marketMovers(positions: positions, portfolio: pf),
                              opportunities: marketOpportunities(), threats: marketThreats(positions: positions))
    }

    /// Biggest changes first: market shares of your companies (latest month) and investments (latest week).
    func marketMovers(limit: Int = 4) -> [MarketMover] { marketMovers(positions: marketPositions(), portfolio: portfolio, limit: limit) }

    private func marketMovers(positions: [CompanyMarketPosition], portfolio pf: Portfolio, limit: Int = 4) -> [MarketMover] {
        var out: [MarketMover] = []
        for p in positions {
            guard let d = p.shareChange, abs(d) >= 0.001 else { continue }
            let start = (p.shareHistory.dropLast().last ?? 0)
            out.append(MarketMover(id: "share:\(p.companyID)", kind: .marketShare, title: p.name, detail: "\(p.tradeName) · \(p.cityName)", change: d,
                                   relativeChange: start > 0 ? d / start : d, isGain: d > 0, companyID: p.companyID, positionID: nil))
        }
        for p in pf.positions where p.pnlWeek != 0 {
            let start = p.value - p.pnlWeek
            out.append(MarketMover(id: "pos:\(p.id)", kind: .investment, title: p.name, detail: p.ownerName, change: p.pnlWeek,
                                   relativeChange: start > 0 ? p.pnlWeek / start : 0, isGain: p.pnlWeek > 0, companyID: nil, positionID: p.id))
        }
        return Array(out.sorted { (abs($0.relativeChange), $1.id) > (abs($1.relativeChange), $0.id) }.prefix(max(0, limit)))
    }

    // MARK: Opportunities

    /// Up to `limit` cards: a rival for sale (or in trouble), a city worth opening in, a dip in a fund.
    func marketOpportunities(limit: Int = 3) -> [MarketOpportunity] {
        var rivalCards: [MarketOpportunity] = []
        let rivals = marketRivals()
        for r in rivals.filter({ $0.forSale }).sorted(by: { ($0.share, $1.id) > ($1.share, $0.id) }) {
            rivalCards.append(MarketOpportunity(id: "sale:\(r.id)", kind: .rivalForSale, title: "\(r.name) is for sale",
                                                detail: "\(r.tradeName) in \(r.cityName), \(Int(saturating: (r.share * 100).rounded()))% of the market.", companyID: r.companyID,
                                                rivalID: r.id, cityID: r.cityID, countryCode: r.countryCode, tradeID: r.tradeID, assetID: nil, amount: r.valuation))
        }
        for r in rivals.filter({ $0.inTrouble && !$0.forSale }).sorted(by: { ($0.share, $1.id) > ($1.share, $0.id) }) {
            rivalCards.append(MarketOpportunity(id: "trouble:\(r.id)", kind: .rivalInTrouble, title: "\(r.name) is short of money",
                                                detail: "Its owner may sell cheaply. \(r.tradeName) in \(r.cityName).", companyID: r.companyID, rivalID: r.id,
                                                cityID: r.cityID, countryCode: r.countryCode, tradeID: r.tradeID, assetID: nil, amount: r.valuation))
        }
        var others: [MarketOpportunity] = []
        if let c = bestOpenCity() { others.append(c) }
        let dips = marketAssets.filter { !$0.closed && ($0.monthChange ?? 0) <= -0.05 }
        // A fund's dip first (steadier), else the deepest dip of a coin.
        let deepest: ([MarketAsset]) -> MarketAsset? = { $0.min { ($0.monthChange ?? 0, $0.id) < ($1.monthChange ?? 0, $1.id) } }
        if let d = deepest(dips.filter { $0.kind != .crypto }) ?? deepest(dips.filter { $0.kind == .crypto }) {
            others.append(MarketOpportunity(id: "dip:\(d.id)", kind: .fundDip, title: "\(d.name) is down \(Int(saturating: (abs(d.monthChange ?? 0) * 100).rounded()))%",
                                            detail: "Over the last four weeks. Risk: \(d.risk.rawValue.lowercased()).", companyID: nil, rivalID: nil, cityID: nil,
                                            countryCode: nil, tradeID: nil, assetID: d.id, amount: d.price))
        }
        // One of each kind first, then more rivals.
        var out = Array(rivalCards.prefix(1)) + others
        out += rivalCards.dropFirst()
        return Array(out.prefix(max(0, limit)))
    }

    /// The city with the most demand per rival for a trade you run, where you have no company of that trade (home country and countries you are in).
    private func bestOpenCity() -> MarketOpportunity? {
        let trades = Array(Set(MarketMap.markets(state, data: data).filter { $0.kind == .local }.map { $0.type })).sorted()
        let codes = Array(Set(state.companies.filter { $0.status.isLive }.map { $0.countryCode } + [state.homeCountryCode])).sorted()
        let tables = data.balance.cityMarket
        var best: (score: Double, trade: Trade, country: Country, city: Country.City, demand: Double, rivals: Int)?
        for code in codes {
            guard let country = data.countries[code] else { continue }
            for t in trades {
                guard let bd = data.catalog[t], CompanySetup.banReason(t, country: country) == nil else { continue }
                for city in country.cities {
                    if state.companies.contains(where: { $0.status.isLive && $0.type == t && $0.cityID == city.id && $0.countryCode == code }) { continue }
                    let demand = CityMarket.demandIndex(trade: t, country: country, city: city, tables: tables)
                    guard demand >= CityMarket.demandHighFrom else { continue }
                    let mk = state.rest["mk"]?[t + "|" + city.id]
                    let rivals = Int(saturating: jsRound(mk == nil || mk!.isNull ? CityMarket.expectedRivals(trade: bd, country: country, city: city, tables: tables) : mk!["n"].double))
                    let score = demand / Double(max(1, rivals))
                    if best == nil || score > best!.score { best = (score, bd, country, city, demand, rivals) }
                }
            }
        }
        guard let b = best else { return nil }
        let cost = CompanySetup.estimate(tradeID: b.trade.id, cityID: b.city.id, form: .limited, size: 1, countryCode: b.country.code, state: state, data: data)?.total
        return MarketOpportunity(id: "city:\(b.trade.id):\(b.city.id)", kind: .openCity, title: "\(b.trade.name) in \(b.city.name)",
                                 detail: "High demand and \(b.rivals) rival\(b.rivals == 1 ? "" : "s").", companyID: nil, rivalID: nil, cityID: b.city.id,
                                 countryCode: b.country.code, tradeID: b.trade.id, assetID: nil, amount: cost)
    }

    // MARK: Threats

    func marketThreats(limit: Int = 4) -> [MarketThreat] { marketThreats(positions: marketPositions(), limit: limit) }

    private func marketThreats(positions: [CompanyMarketPosition], limit: Int = 4) -> [MarketThreat] {
        var out: [MarketThreat] = []
        let rows = marketRivals()
        for p in positions where !p.national {
            guard let co = state.company(p.companyID) else { continue }
            let rivals = Rivals.rivals(state, for: co)
            if let mine = p.priceIndex {
                let under = p.competitors.filter { c in
                    guard let id = c.rivalID, let pi = c.priceIndex else { return false }
                    return pi <= mine * 0.9 || rivals.first { $0.id == id }?.discountPercent != nil
                }.max { $0.share < $1.share }
                if let u = under, let id = u.rivalID {
                    let gap = mine > 0 ? 1 - (u.priceIndex ?? mine) / mine : 0
                    let disc = rivals.first { $0.id == id }?.discountPercent
                    out.append(MarketThreat(id: "under:\(p.companyID):\(id)", kind: .undercut, title: "\(u.name) undercuts \(p.name)",
                                            detail: disc.map { "Running \($0)% off." } ?? "About \(Int(saturating: (gap * 100).rounded()))% cheaper than you.",
                                            companyID: p.companyID, rivalID: id, severity: clamp(u.share + max(0, gap), 0, 1)))
                }
            }
            for r in rows where r.marketKey == p.marketKey && r.companyID == p.companyID && r.isNewEntrant {
                out.append(MarketThreat(id: "new:\(r.id)", kind: .newEntrant, title: "\(r.name) opened near \(p.name)", detail: "\(r.strategy) rival, new in \(r.cityName).",
                                        companyID: p.companyID, rivalID: r.id, severity: clamp(0.3 + r.share, 0, 1)))
            }
            let dis = state.rest["mk"]?[p.marketKey]["dis"] ?? .null
            if !dis.isNull {
                out.append(MarketThreat(id: "cheap:\(p.marketKey)", kind: .cheapEntrant, title: "\(dis["name"].string) sells far below normal prices",
                                        detail: "In \(p.cityName): it \(dis["why"].string).", companyID: p.companyID, rivalID: nil, severity: clamp(0.4 + dis["depth"].double, 0, 1)))
            }
        }
        for p in positions {
            if let d = p.shareChange, d <= -0.02 {
                out.append(MarketThreat(id: "lose:\(p.companyID)", kind: .losingShare, title: "\(p.name) is losing customers",
                                        detail: "Market share down \(String(format: "%.1f", abs(d) * 100)) points last month.", companyID: p.companyID, rivalID: nil,
                                        severity: clamp(abs(d) * 5, 0, 1)))
            }
        }
        var seen = Set<String>()
        return Array(out.filter { seen.insert($0.id).inserted }.sorted { ($0.severity, $1.id) > ($1.severity, $0.id) }.prefix(max(0, limit)))
    }

    // MARK: World

    /// Every country: home first, then those you are in, then by name.
    func marketCountries() -> [MarketCountry] {
        let live = state.companies.filter { $0.status.isLive }
        let rows = data.countries.countries.map { c in
            MarketCountry(code: c.code, name: c.name, flag: c.flag, region: c.region, isHome: c.code == state.homeCountryCode, populationMillions: c.populationMillions,
                          marketStrength: c.marketStrength, priceLevel: c.priceLevel, rentLevel: c.rentLevel, wageLevel: c.wageLevel, corporateTax: c.corporateTax,
                          vatStandard: c.vat.standard, dividendTax: c.dividendTax, employerSocial: c.employerSocial, cities: c.cities.count,
                          yourCompanies: live.filter { $0.countryCode == c.code }.count, hasDesk: Abroad.hasDesk(state, country: c.code))
        }
        return rows.sorted { ($0.isHome ? 0 : $0.yourCompanies > 0 ? 1 : 2, $0.name) < ($1.isHome ? 0 : $1.yourCompanies > 0 ? 1 : 2, $1.name) }
    }

    /// The cities of a country, biggest first; with `tradeID`, the demand and rivals for that trade in each.
    func marketCities(countryCode: String, tradeID: String? = nil) -> [MarketCity] {
        guard let c = data.countries[countryCode] else { return [] }
        let tables = data.balance.cityMarket
        let bd = tradeID.flatMap { data.catalog[$0] }
        let live = state.companies.filter { $0.status.isLive && $0.countryCode == countryCode }
        return c.cities.sorted { ($0.population, $1.id) > ($1.population, $0.id) }.map { city in
            var demand: Double?, level: CityMarket.DemandLevel?, rivals: Int?
            if let bd {
                demand = CityMarket.demandIndex(trade: bd.id, country: c, city: city, tables: tables)
                level = CityMarket.demandLevel(trade: bd.id, country: c, city: city, tables: tables)
                let mk = state.rest["mk"]?[bd.id + "|" + city.id]
                rivals = Int(saturating: jsRound(mk == nil || mk!.isNull ? CityMarket.expectedRivals(trade: bd, country: c, city: city, tables: tables) : mk!["n"].double))
            }
            return MarketCity(id: city.id, name: city.name, countryCode: c.code, population: city.population, demand: city.demand,
                              priceLevel: c.priceLevel * city.price, rentLevel: c.rentLevel * city.rent, wageLevel: c.wageLevel * city.wage, touristIndex: city.touristIndex,
                              tradeID: bd?.id, tradeDemand: demand, tradeDemandLevel: level, rivals: rivals,
                              yourCompanies: live.filter { $0.cityID == city.id }.count, isHomeCity: countryCode == state.homeCountryCode && city.id == state.player.cityID)
        }
    }

    /// One city's market in detail: households, incomes, demand and rivals per trade.
    func marketCityProfile(cityID: String, countryCode: String) -> CityMarket.Profile? {
        CityMarket.profile(cityID: cityID, countryCode: countryCode, state: state, data: data)
    }

    // MARK: Rankings

    /// The rich list of your home country, where you stand on it and the top of it.
    var richListStanding: RichList.Standing { RichList.standing(state, data: data, context: context) }
    /// The business awards year by year.
    var awardYears: [Awards.Year] { Awards.years(state) }
}
