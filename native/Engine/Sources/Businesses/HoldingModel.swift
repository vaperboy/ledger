import Foundation
import GameCore
import Countries
import Finance

public enum HoldingModel {
    public static let indexFundKey = "idx"
    public static let treasuryFunds = ["idx", "bond", "mm"]

    public static func indexPrice(_ s: GameState) -> Double { fundPrice(s, indexFundKey) }
    public static func fundPrice(_ s: GameState, _ sym: String) -> Double {
        s.rest["fundPx"]?[sym].isNull == false ? s.rest["fundPx"]![sym].double : 100
    }

    public static func fundPosition(_ h: Company, _ sym: String) -> (units: Double, cost: Double) {
        let fm = h.value("fm")
        if sym == indexFundKey { return (fm["idxU"].double, fm["idxCost"].double) }
        return (fm["fx"][sym]["q"].double, fm["fx"][sym]["cost"].double)
    }
    public static func fundLastBuy(_ h: Company, _ sym: String) -> (week: Int, units: Double)? {
        let fm = h.value("fm")
        let rec = sym == indexFundKey ? fm["idxBuy"] : fm["fx"][sym]["buy"]
        return rec.isNull ? nil : (rec["w"].int, rec["q"].double)
    }
    public static func fundValue(_ h: Company, _ s: GameState, _ sym: String) -> Double { fundPosition(h, sym).units * fundPrice(s, sym) }
    public static func treasuryValue(_ h: Company, _ s: GameState) -> Double { treasuryFunds.reduce(0) { $0 + fundValue(h, s, $1) } }

    static func setFundPosition(_ fm: inout JSONValue, _ sym: String, units: Double, cost: Double) {
        if sym == indexFundKey { fm["idxU"] = .number(units); fm["idxCost"] = .number(cost); return }
        var fx = fm["fx"].isNull ? JSONValue.object([:]) : fm["fx"]
        var p = fx[sym].isNull ? JSONValue.object([:]) : fx[sym]
        p["q"] = .number(units); p["cost"] = .number(cost)
        fx[sym] = p
        fm["fx"] = fx
    }

    static func recordBuy(_ fm: inout JSONValue, _ sym: String, units: Double, week: Int) {
        let path = sym == indexFundKey ? fm["idxBuy"] : fm["fx"][sym]["buy"]
        let q = !path.isNull && path["w"].int == week ? path["q"].double + units : units
        let rec = JSONValue.object(["w": .number(Double(week)), "q": .number(q)])
        if sym == indexFundKey { fm["idxBuy"] = rec } else { fm["fx"][sym]["buy"] = rec }
    }

    public static func subsidiaries(of holdingID: Int, in s: GameState) -> [Company] {
        s.companies.filter { $0.status.isLive && ($0.holdingID == holdingID || HoldingStakes.sharePercent(of: $0, holdingID: holdingID) > HoldingStakes.controlAbove) }
    }

    public static func holdings(in s: GameState, openOnly: Bool = true) -> [Company] {
        s.companies.filter { $0.type == "hold" && (openOnly ? $0.status == .open : $0.status.isLive) }
    }

    public static func indexValue(_ h: Company, _ s: GameState) -> Double { fundValue(h, s, indexFundKey) }

    static func context(_ s: inout GameState, _ i: Int, _ data: GameData) -> CompanyWeek.WeekContext {
        let h = s.companies[i]
        refreshAssets(&s, holdingID: h.id, data: data)
        return CompanyWeek.WeekContext(units: 0, rev: 0, cogs: 0, D: 0, cap: 0, util: 0, price: 1, paidDuringWeek: 0)
    }

    public static func refreshAssets(_ s: inout GameState, holdingID: Int, data: GameData) {
        guard let i = s.companyIndex(holdingID), s.companies[i].type == "hold" else { return }
        let rivals = HoldingStakes.revalueRivals(&s, holdingID: holdingID, data: data)
        let h = s.companies[i]
        let held = HoldingStakes.stakeCompanies(of: h.id, in: s).reduce(0) { $0 + Valuation.companyValue($1, state: s, trades: data.catalog) * HoldingStakes.sharePercent(of: $1, holdingID: h.id) / 100 } + rivals + HoldingStartups.value(s, holdingID: h.id)
        var fm = h.value("fm")
        fm["assets"] = .number(treasuryValue(h, s) + held)
        s.companies[i].set("fm", fm)
    }

    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        HoldingStakes.weekly(&s)
        for hi in s.companies.indices where s.companies[hi].type == "hold" && s.companies[hi].status == .open {
            let h = s.companies[hi]
            let wc = max(fc.currency(h.countryCode, s).scaledPrice(1500), fc.weeklyCost(h, s))
            if h.cash >= wc * 4 { continue }
            let need = wc * 13 - h.cash
            let subs = s.companies.filter { $0.holdingID == h.id && $0.status == .open }.sorted { $0.cash > $1.cash }
            for sub in subs {
                let spare = sub.cash - fc.weeklyCost(sub, s) * 6
                if spare <= 0 { continue }
                let g = need / max(0.01, sub.ownership / 100)
                let mag = pow(10, floor(log10(max(1, g))))
                let amt = min(spare, ([1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10].first { $0 * mag >= g } ?? 10) * mag)
                if Payments.payDividend(&s, companyID: sub.id, amount: jsRound(amt), context: fc) == .ok {
                    s.note("\(h.name) took a dividend of \(fc.currency(h.countryCode, s).short(amt)) from \(sub.name) to pay its own costs.", tone: "n", companyID: h.id)
                    break
                }
            }
        }
    }

    public enum Failure: Error, Equatable { case notEnoughCash, notAllowed }

    public struct StakeInput: Equatable, Sendable {
        public var companyID: Int
        public var percent: Double
        public init(companyID: Int, percent: Double) { self.companyID = companyID; self.percent = percent }
    }

    public static func create(_ s: inout GameState, name: String?, accountantID: Int? = nil, companies: [Int] = [], stakes: [StakeInput] = [], data: GameData, context fc: FinanceContext) -> Result<Int, Failure> {
        let code = s.homeCountryCode
        guard let country = data.countries[code] else { return .failure(.notAllowed) }
        let city = s.player.cityID
        let nm = (name?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? "\(s.player.name.split(separator: " ").last.map(String.init) ?? "My") Holding"
        let r = CompanySetup.create(&s, tradeID: "hold", cityID: city, size: 1, name: nm, countryCode: code, accountantID: accountantID, data: data, context: fc)
        guard case .success(let id) = r, let i = s.companyIndex(id) else {
            if case .failure(.notEnoughCash) = r { return .failure(.notEnoughCash) }
            return .failure(.notAllowed)
        }
        s.companies[i].status = .open
        s.companies[i].openedWeek = s.week
        var docs = s.companies[i].value("docs")
        for d in ["registration", "accountant_agreement"] { docs[d] = .object(["st": "ok", "ok": .number(Double(s.week)), "done": .number(Double(s.week))]) }
        s.companies[i].set("docs", docs)
        s.companies[i].set("fm", .object(["idxU": 0, "idxCost": 0, "assets": 0]))
        s.companies[i].set("ownerHours", 0)
        s.companies[i].ownerHours = 0
        for c in companies { _ = move(&s, companyID: c, into: id, data: data) }
        for st in stakes {
            if case .failure(let f) = HoldingStakes.moveShare(&s, companyID: st.companyID, into: id, percent: st.percent, data: data) {
                s.note("\(s.company(st.companyID)?.name ?? "A company") was not put under \(nm): \(f.reason)", tone: "warn", companyID: id)
            }
        }
        _ = country
        s.note("\(nm) is registered.", tone: "good", companyID: id)
        return .success(id)
    }

    @discardableResult
    public static func move(_ s: inout GameState, companyID: Int, into holdingID: Int, data: GameData? = nil) -> Bool {
        guard let ci = s.companyIndex(companyID), let hi = s.companyIndex(holdingID) else { return false }
        let h = s.companies[hi], c = s.companies[ci]
        guard h.type == "hold", h.status.isLive, c.type != "hold", c.status.isLive else { return false }
        let before = c.holdingID
        s.companies[ci].holdingID = holdingID
        if let data = data {
            refreshAssets(&s, holdingID: holdingID, data: data)
            if before != 0 && before != holdingID { refreshAssets(&s, holdingID: before, data: data) }
        }
        return true
    }

    @discardableResult
    public static func release(_ s: inout GameState, companyID: Int, data: GameData? = nil) -> Bool {
        guard let ci = s.companyIndex(companyID), s.companies[ci].holdingID != 0, !HoldingStakes.isDivision(s.companies[ci]), HoldingStakes.divisions(of: companyID, in: s).isEmpty else { return false }
        let before = s.companies[ci].holdingID
        s.companies[ci].holdingID = 0
        if let data = data { refreshAssets(&s, holdingID: before, data: data) }
        return true
    }

    @discardableResult
    public static func invest(_ s: inout GameState, holdingID: Int, amount: Double, fund sym: String = indexFundKey) -> Bool {
        guard treasuryFunds.contains(sym), let i = s.companyIndex(holdingID), s.companies[i].type == "hold", amount > 0, s.companies[i].cash >= amount else { return false }
        Ledger.moveRaw(&s, .company(holdingID), -amount)
        var fm = s.companies[i].value("fm")
        let pos = fundPosition(s.companies[i], sym)
        let units = amount / fundPrice(s, sym)
        setFundPosition(&fm, sym, units: pos.units + units, cost: pos.cost + amount)
        recordBuy(&fm, sym, units: units, week: s.week)
        s.companies[i].set("fm", fm)
        return true
    }

    public static let divestCost = 0.0066

    @discardableResult
    public static func divestAmount(_ s: inout GameState, holdingID: Int, amount: Double, fund sym: String = indexFundKey) -> Double {
        guard treasuryFunds.contains(sym), let i = s.companyIndex(holdingID), s.companies[i].type == "hold" else { return 0 }
        var fm = s.companies[i].value("fm")
        let pos = fundPosition(s.companies[i], sym)
        let v = pos.units * fundPrice(s, sym)
        let amt = min(amount, v)
        if amt <= 0 { return 0 }
        let fr = amt / v
        setFundPosition(&fm, sym, units: pos.units * (1 - fr), cost: pos.cost * (1 - fr))
        s.companies[i].set("fm", fm)
        let cash = amt * (1 - divestCost)
        Ledger.moveRaw(&s, .company(holdingID), cash)
        return cash
    }

    @discardableResult
    public static func divest(_ s: inout GameState, holdingID: Int, amount: Double, fund sym: String = indexFundKey) -> Bool {
        divestAmount(&s, holdingID: holdingID, amount: amount, fund: sym) > 0
    }

    public static func backfillCostBasis(_ s: inout GameState) {
        for i in s.companies.indices where s.companies[i].type == "hold" {
            var fm = s.companies[i].value("fm")
            guard !fm.isNull else { continue }
            let units = fm["idxU"].double
            if units > 0, fm["idxCost"].isNull || fm["idxCost"].double <= 0 {
                fm["idxCost"] = .number(jsRound(units * indexPrice(s) * 100) / 100)
                s.companies[i].set("fm", fm)
            }
        }
    }

    public static func holdingFailed(_ s: inout GameState, holdingID: Int) {
        HoldingStakes.releaseLines(&s, holdingID: holdingID)
        for j in s.companies.indices where s.companies[j].holdingID == holdingID {
            s.companies[j].holdingID = 0
            s.companies[j].set("div", .null)
            s.note("\(s.companies[j].name) is owned by you directly now.", tone: "n", companyID: s.companies[j].id)
        }
    }

    public static func taxGroup(of co: Company, in s: GameState) -> [Company]? {
        let h: Company?
        if co.type == "hold" { h = co } else if co.holdingID != 0 { h = s.company(co.holdingID) } else { h = HoldingStakes.controllingHolding(of: co, in: s) }
        guard let hold = h, hold.status.isLive else { return nil }
        let members = [hold] + s.companies.filter {
            $0.id != hold.id && $0.status.isLive && $0.status != .setup && HoldingStakes.sharePercent(of: $0, holdingID: hold.id) >= HoldingStakes.squeezeOutFrom
                && $0.countryCode == hold.countryCode
        }
        return members.count > 1 && members.contains(where: { $0.id == co.id }) ? members : nil
    }

    public static func groupContribution(_ co: Company, in s: GameState) -> (out: Double, in: Double) {
        guard let group = taxGroup(of: co, in: s) else { return (0, 0) }
        func p(_ c: Company) -> Double { max(0, c.yearProfitSoFar - (c.lossCarryAtYearStart ?? 0)) }
        func l(_ c: Company) -> Double { max(0, -c.yearProfitSoFar) }
        let tp = group.reduce(0) { $0 + p($1) }, tl = group.reduce(0) { $0 + l($1) }
        let used = min(tp, tl)
        if used <= 0 { return (0, 0) }
        return (p(co) / tp * used, l(co) / tl * used)
    }

    public struct Subsidiary: Identifiable, Equatable {
        public var id: Int
        public var name: String, trade: String
        public var ownership: Double
        public var value: Double, share: Double
        public var revenueTTM: Double, profitTTM: Double
        public var cash: Double
        public var inTaxGroup: Bool
    }

    public struct Consolidated: Equatable {
        public var holdingCash = 0.0, indexFund = 0.0, indexCost = 0.0
        public var otherFunds = 0.0, otherFundsCost = 0.0
        public var holdingValue = 0.0
        public var subsidiaries: [Subsidiary] = []
        public var revenueTTM = 0.0, profitTTM = 0.0
        public var cashInGroup = 0.0, debtInGroup = 0.0
        public var companiesValue: Double { subsidiaries.reduce(0) { $0 + $1.share } }
        public var rivalStakes = 0.0
        public var dividendsThisYear = 0.0
        public var taxSaved = 0.0
        public var groupCovered = 0.0
    }

    public static func consolidated(_ h: Company, _ s: GameState, trades: any TradeCatalogProviding) -> Consolidated {
        var c = Consolidated()
        c.holdingCash = h.cash
        c.indexFund = indexValue(h, s)
        c.indexCost = h.value("fm")["idxCost"].double
        for sym in treasuryFunds where sym != indexFundKey {
            c.otherFunds += fundValue(h, s, sym)
            c.otherFundsCost += fundPosition(h, sym).cost
        }
        let group = taxGroup(of: h, in: s) ?? []
        for k in HoldingStakes.stakeCompanies(of: h.id, in: s) {
            let v = max(0, Valuation.companyValue(k, state: s, trades: trades))
            let hist = k.monthlyHistory.suffix(12)
            let pct = HoldingStakes.sharePercent(of: k, holdingID: h.id)
            let own = pct / 100
            let tier = HoldingStakes.tier(forPercent: pct)
            let sub = Subsidiary(id: k.id, name: k.name, trade: trades.facts(for: k.type)?.id ?? k.type, ownership: pct, value: v, share: v * own,
                                 revenueTTM: hist.reduce(0) { $0 + $1.revenue }, profitTTM: hist.reduce(0) { $0 + $1.profit }, cash: k.cash,
                                 inTaxGroup: group.contains { $0.id == k.id })
            c.subsidiaries.append(sub)
            if tier.isConsolidated { c.revenueTTM += sub.revenueTTM * own }
            if tier.isConsolidated || tier == .influence { c.profitTTM += sub.profitTTM * own }
            if tier.isConsolidated {
                c.cashInGroup += max(0, k.cash)
                c.debtInGroup += CompanyFigures.debts(k, loans: s.loans)
            }
            let gc = groupContribution(k, in: s)
            c.groupCovered += gc.out
        }
        let hh = h.monthlyHistory.suffix(12)
        c.revenueTTM += hh.reduce(0) { $0 + $1.revenue }
        c.profitTTM += hh.reduce(0) { $0 + $1.profit }
        c.cashInGroup += max(0, h.cash)
        c.debtInGroup += CompanyFigures.debts(h, loans: s.loans)
        c.dividendsThisYear = Payments.holdingDividends(h, weeks: (s.week / 52 * 52)...max(s.week / 52 * 52, s.week))
        c.rivalStakes = HoldingStakes.rivalStakesValue(h) + HoldingStartups.value(s, holdingID: h.id)
        c.holdingValue = h.cash + c.indexFund + c.otherFunds + c.companiesValue + c.rivalStakes
        return c
    }
}
