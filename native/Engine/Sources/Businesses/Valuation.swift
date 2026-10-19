import Foundation
import GameCore
import Finance

/// What a company is worth and what the player is worth. Originals: `companyValue`, `netWorth` in engine/money/money.js.
public struct NetWorth: Equatable, Sendable {
    /// Current account + savings
    public var personal: Double
    /// Stocks
    public var stocks: Double
    public var crypto: Double
    /// Funds, fixed deposits and any fund-manager account
    public var funds: Double
    /// The player's share of the value of their companies and startups
    public var companies: Double
    /// Luxury collection (cars, watches, houses ...) owned personally
    public var luxury: Double
    /// Private loans (company loans sit inside company values)
    public var debt: Double
    /// Tax assessed but not yet paid
    public var pendingTax: Double

    /// Everything the player owns, before debts
    public var totalAssets: Double { personal + stocks + crypto + funds + companies + luxury }
    /// Assets minus private debts and pending tax: the one number shown as "Net worth".
    public var total: Double { totalAssets - debt - pendingTax }
    /// Investments as the game shows them in one group
    public var investments: Double { stocks + crypto + funds }
}

public enum Valuation {
    /// The value of a company as a whole. Original: `companyValueCore`.
    /// = assets - debts, plus "goodwill" (a multiple of yearly profit, earned over two years of accounts).
    public static func companyValue(_ co: Company, state s: GameState, trades: any TradeCatalogProviding) -> Double {
        if !co.status.isLive { return 0 }
        guard let bd = trades.facts(for: co.type) else { return 0 }
        let fm = co.value("fm")
        if bd.family == "club", !fm.isNull, !fm["val"].isNull, fm["val"].double != 0 {
            return jsRound(fm["val"].double + co.cash)
        }
        let net = CompanyFigures.assets(co) - CompanyFigures.debts(co, loans: s.loans)
        let mult: Double = bd.family == "fin" ? 1.0 : bd.family == "rent" ? 0.0 : bd.family == "energy" ? 5 : (bd.margin > 0.2 ? 5 : 4)
        let prof = max(0, CompanyFigures.yearlyProfitEstimate(co, currentWeek: s.week))
        // Buyers pay for a track record: goodwill counts fully after two years of accounts, a quarter after six months.
        let trust = min(1, Double(co.monthlyHistory.count) / 24)
        let goodwill = (co.status == .open && (s.week - co.foundedWeek > 12))
            ? prof * mult * (0.6 + co.reputation / 200) * (co.managerID != nil ? 0.85 : 1) * trust : 0
        let adj: Double = co.form == .soleTrader ? 0.85 : 1
        var v = jsRound(net + goodwill * adj)
        // A club is worth its football value plus cash, minus what it owes. Original step: 'a club is worth ...'
        if co.type == "club", !fm.isNull {
            let owed = s.loans.filter { $0.companyID == co.id }.reduce(0) { $0 + $1.balance }
            v = jsRound(v - owed + fm["book"].double * 0.8)
        }
        return v
    }

    /// Net worth with every part named. Original: `netWorthCore` + the 'netWorth' steps.
    public static func netWorth(_ s: GameState, trades: any TradeCatalogProviding) -> NetWorth {
        var stocks = 0.0, crypto = 0.0, funds = 0.0
        let stockPrices = s.rest["stocks"]?.object ?? [:]
        let cryptoPrices = s.rest["crypto"]?.object ?? [:]
        let inv = s.rest["inv"] ?? .null
        for (sym, h) in inv["stocks"].object { stocks += h["q"].double * (stockPrices[sym]?["p"].double ?? 0) }
        for (sym, h) in inv["crypto"].object { crypto += h["q"].double * (cryptoPrices[sym]?["p"].double ?? 0) }
        for d in inv["deposits"].array { funds += d["bal"].double }
        let fundPx = s.rest["fundPx"]?.object ?? [:]
        for (k, h) in inv["funds"].object { funds += h["q"].double * (fundPx[k]?.double ?? 100) }
        if let fm = s.rest["fm"], !fm.isNull { funds += fm["bal"].double }
        // Private equity funds the player is invested in
        funds += (s.rest["pe56"]?["mine"].array ?? []).filter { $0["st"].string == "live" }.reduce(0) { $0 + $1["nav"].double }

        var companies = 0.0
        for st in s.rest["startups"]?.array ?? [] where st["st"].string == "live" { companies += st["val"].double * st["pct"].double / 100 }
        // Startups you founded (live ones, by your share) and shares you hold in other people's startups
        for f in s.rest["founded"]?.array ?? [] where f["st"].string == "live" { companies += f["val"].double * f["pct"].double / 100 }
        companies += (s.rest["stakes"]?.array ?? []).reduce(0) { $0 + $1["val"].double }
        for co in s.companies where co.status.isLive && co.holdingID == 0 && co.type != "hold" {
            companies += companyValue(co, state: s, trades: trades) * co.ownership / 100
        }
        let lux = (s.rest["lux"]?.array ?? []).filter { $0["co"].isNull || $0["co"].double == 0 }.reduce(0) { $0 + $1["val"].double }
        let debt = s.loans.filter { $0.companyID == 0 }.reduce(0) { $0 + $1.balance }
        return NetWorth(personal: s.cash + s.savings, stocks: stocks, crypto: crypto, funds: funds, companies: companies,
                        luxury: lux, debt: debt, pendingTax: s.tax.pending)
    }
}
