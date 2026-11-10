import Foundation
import GameCore
import Finance

public struct NetWorth: Equatable, Sendable {
    public var personal: Double
    public var crypto: Double
    public var funds: Double
    public var companies: Double
    public var luxury: Double
    public var debt: Double
    public var pendingTax: Double
    public var exchange: Double = 0

    public var totalAssets: Double { personal + crypto + funds + companies + luxury + exchange }
    public var total: Double { totalAssets - debt - pendingTax }
    public var investments: Double { crypto + funds + exchange }
}

public enum Valuation {
    public static func companyValue(_ co: Company, state s: GameState, trades: any TradeCatalogProviding) -> Double {
        if !co.status.isLive { return 0 }
        guard let bd = trades.facts(for: co.type) else { return 0 }
        let fm = co.value("fm")
        if bd.family == "club", !fm.isNull, !fm["val"].isNull, fm["val"].double != 0 {
            let owed = s.loans.filter { $0.companyID == co.id }.reduce(0) { $0 + $1.balance }
            return jsRound(jsRound(fm["val"].double + co.cash) - owed + fm["book"].double * 0.8)
        }
        let net = CompanyFigures.assets(co) - CompanyFigures.debts(co, loans: s.loans)
        if bd.id == StartupModel.tradeID { return jsRound(max(0, StartupModel.value(co, state: s, net: net))) }
        let goodwill = goodwill(co, state: s, trades: trades)
        return max(0, jsRound(net + goodwill))
    }

    public static func goodwill(_ co: Company, state s: GameState, trades: any TradeCatalogProviding) -> Double {
        guard let bd = trades.facts(for: co.type) else { return 0 }
        let mult: Double = bd.family == "fin" ? 1.0 : bd.family == "rent" ? 0.0 : bd.family == "energy" ? 5 : (bd.margin > 0.2 ? 5 : 4)
        let ownerLabour = co.managerID == nil ? bd.ownerFTE * co.num("ownWage") * 12 : 0
        let prof = max(0, CompanyFigures.yearlyProfitEstimate(co, currentWeek: s.week) - ownerLabour)
        let trust = min(1, Double(co.monthlyHistory.count) / 24)
        return (co.status == .open && (s.week - co.foundedWeek > 12))
            ? prof * mult * (0.6 + co.reputation / 200) * (co.managerID != nil ? 0.85 : 1) * trust : 0
    }

    public static let youngCompanyWeeks = 8

    public static func netWorth(_ s: GameState, trades: any TradeCatalogProviding, forGoals: Bool = false) -> NetWorth {
        var crypto = 0.0, funds = 0.0
        let cryptoPrices = s.rest["crypto"]?.object ?? [:]
        let inv = s.rest["inv"] ?? .null
        for (sym, h) in inv["crypto"].object.sorted(by: { $0.key < $1.key }) { crypto += h["q"].double * (cryptoPrices[sym]?["p"].double ?? 0) }
        for d in inv["deposits"].array { funds += d["bal"].double }
        let fundPx = s.rest["fundPx"]?.object ?? [:]
        for (k, h) in inv["funds"].object.sorted(by: { $0.key < $1.key }) { funds += h["q"].double * (fundPx[k]?.double ?? 100) }
        if let fm = s.rest["fm"], !fm.isNull { funds += fm["bal"].double }
        funds += (s.rest["pe56"]?["mine"].array ?? []).filter { $0["st"].string == "live" }.reduce(0) { $0 + $1["nav"].double }

        var companies = 0.0
        for st in s.rest["startups"]?.array ?? [] where st["st"].string == "live" && st["hid"].int == 0 { companies += st["val"].double * st["pct"].double / 100 }
        companies += (s.rest["stakes"]?.array ?? []).reduce(0) { $0 + $1["val"].double }
        companies += GroupStakes.stakesValue(s)
        for co in s.companies where co.status.isLive && co.holdingID == 0 {
            var v = companyValue(co, state: s, trades: trades) + HeldMoney.remaining(s, companyID: co.id)
            if forGoals, s.week - co.foundedWeek < youngCompanyWeeks, co.ownerNetFlow > 0 { v = min(v, co.ownerNetFlow) }
            companies += v * co.ownership / 100
        }
        let lux = (s.rest["lux"]?.array ?? []).filter { $0["co"].isNull || $0["co"].double == 0 }.reduce(0) { $0 + $1["val"].double }
        let debt = s.loans.filter { $0.companyID == 0 }.reduce(0) { $0 + $1.balance }
        return NetWorth(personal: s.cash + HeldMoney.playerRemaining(s), crypto: crypto, funds: funds, companies: companies,
                        luxury: lux, debt: debt, pendingTax: s.tax.pending, exchange: PublicExchange.holdingsValue(s))
    }
}
