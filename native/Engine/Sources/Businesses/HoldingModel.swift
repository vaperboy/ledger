import Foundation
import GameCore
import Countries
import Finance

/// The holding company: a limited company that owns the shares of your other limited companies and may invest its cash.
/// Original: `createHolding`, `moveToHolding`, `holdInvest`, `holdDivest`, `FAM.hold` (engine/world/deals.js), the tax group
/// (`taxGroup`, `groupContrib` in engine/money/money.js) and the holding's weekly dividend step (features/sales/trades_in_hours.js).
///
/// How it fits the rest of the game:
///  - A company owned through a holding has `hold` = the holding's id. It is then left out of your own list of holdings in net
///    worth, because the holding's value already contains it (`fm.assets` = index fund + each company's value x your share).
///  - Dividends paid by such a company go to the holding's cash (and are not taxed as yours); the holding pays dividends to you.
///  - Limited companies in one country that the holding owns 90% or more of form a tax group: one company's profit covers a sister
///    company's loss in the same year (group contribution), so less tax is paid.
public enum HoldingModel {
    public static let indexFundKey = "idx"

    public static func indexPrice(_ s: GameState) -> Double {
        s.rest["fundPx"]?[indexFundKey].isNull == false ? s.rest["fundPx"]![indexFundKey].double : 100
    }

    /// Companies under a holding that still exist (also ones still being set up).
    public static func subsidiaries(of holdingID: Int, in s: GameState) -> [Company] {
        s.companies.filter { $0.holdingID == holdingID && $0.status.isLive }
    }

    public static func holdings(in s: GameState, openOnly: Bool = true) -> [Company] {
        s.companies.filter { $0.type == "hold" && (openOnly ? $0.status == .open : $0.status.isLive) }
    }

    /// Index fund held by the holding, at today's price.
    public static func indexValue(_ h: Company, _ s: GameState) -> Double { h.value("fm")["idxU"].double * indexPrice(s) }

    // MARK: The week

    /// The holding earns interest on its cash and revalues what it owns. Original: `FAM.hold.custom`.
    static func context(_ s: inout GameState, _ i: Int, _ data: GameData) -> CompanyWeek.WeekContext {
        let h = s.companies[i]
        let kids = subsidiaries(of: h.id, in: s)
        let held = kids.reduce(0) { $0 + Valuation.companyValue($1, state: s, trades: data.catalog) * $1.ownership / 100 }
        var fm = h.value("fm")
        fm["assets"] = .number(indexValue(h, s) + held)
        s.companies[i].set("fm", fm)
        let interest = max(0, h.cash) * max(0, s.economy.policyRate - 0.01) / 52
        return CompanyWeek.WeekContext(units: 0, rev: interest, cogs: 0, D: 0, cap: 0, util: 0, price: 1, paidDuringWeek: 0)
    }

    /// A holding pays its own small costs with dividends from its companies instead of quietly going bankrupt.
    /// Original: the 'trades_in_hours weekly' step.
    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        for hi in s.companies.indices where s.companies[hi].type == "hold" && s.companies[hi].status == .open {
            let h = s.companies[hi]
            let wc = max(fc.currency(h.countryCode, s).scaledPrice(1500), fc.weeklyCost(h, s))
            if h.cash >= wc * 4 { continue }
            let need = wc * 13 - h.cash
            let subs = s.companies.filter { $0.holdingID == h.id && $0.status == .open && $0.form == .limited }.sorted { $0.cash > $1.cash }
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

    // MARK: Creating and changing

    public enum Failure: Error, Equatable { case notEnoughCash, notAllowed }

    /// Register a holding company: the owner pays the registration fee and the share capital, which stays in the holding.
    /// Original: `createHolding` (+ the new-holding screen that moves chosen companies under it).
    public static func create(_ s: inout GameState, name: String?, accountantID: Int? = nil, companies: [Int] = [], data: GameData, context fc: FinanceContext) -> Result<Int, Failure> {
        let code = s.homeCountryCode
        guard let country = data.countries[code] else { return .failure(.notAllowed) }
        let city = s.player.cityID
        let nm = (name?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? "\(s.player.name.split(separator: " ").last.map(String.init) ?? "My") Holding"
        let r = CompanySetup.create(&s, tradeID: "hold", cityID: city, form: .limited, size: 1, name: nm, countryCode: code, accountantID: accountantID, data: data, context: fc)
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
        for c in companies { _ = move(&s, companyID: c, into: id) }
        _ = country
        s.note("\(nm) is registered.", tone: "good", companyID: id)
        return .success(id)
    }

    /// Put a limited company under a holding. Original: `moveToHolding`.
    @discardableResult
    public static func move(_ s: inout GameState, companyID: Int, into holdingID: Int) -> Bool {
        guard let ci = s.companyIndex(companyID), let hi = s.companyIndex(holdingID) else { return false }
        let h = s.companies[hi], c = s.companies[ci]
        guard h.type == "hold", h.status.isLive, c.form == .limited, c.type != "hold", c.status.isLive else { return false }
        s.companies[ci].holdingID = holdingID
        return true
    }

    /// Take a company out of the holding again (it is then yours directly). Original: `ACT.hrel`.
    @discardableResult
    public static func release(_ s: inout GameState, companyID: Int) -> Bool {
        guard let ci = s.companyIndex(companyID), s.companies[ci].holdingID != 0 else { return false }
        s.companies[ci].holdingID = 0
        return true
    }

    /// The holding buys units of the index fund with its cash. Original: `holdInvest`.
    @discardableResult
    public static func invest(_ s: inout GameState, holdingID: Int, amount: Double) -> Bool {
        guard let i = s.companyIndex(holdingID), s.companies[i].type == "hold", amount > 0, s.companies[i].cash >= amount else { return false }
        Ledger.moveRaw(&s, .company(holdingID), -amount)
        var fm = s.companies[i].value("fm")
        fm["idxU"] = .number(fm["idxU"].double + amount / indexPrice(s))
        fm["idxCost"] = .number(fm["idxCost"].double + amount)
        s.companies[i].set("fm", fm)
        return true
    }

    /// The holding sells index fund units for cash (0.66% cost). Original: `holdDivest`.
    @discardableResult
    public static func divest(_ s: inout GameState, holdingID: Int, amount: Double) -> Bool {
        guard let i = s.companyIndex(holdingID), s.companies[i].type == "hold" else { return false }
        var fm = s.companies[i].value("fm")
        let v = fm["idxU"].double * indexPrice(s)
        let amt = min(amount, v)
        if amt <= 0 { return false }
        let fr = amt / v
        fm["idxU"] = .number(fm["idxU"].double - fm["idxU"].double * fr)
        fm["idxCost"] = .number(fm["idxCost"].double * (1 - fr))
        s.companies[i].set("fm", fm)
        Ledger.moveRaw(&s, .company(holdingID), amt * 0.9934)
        return true
    }

    /// When a holding goes bankrupt its companies come back to you. Original: 'companies in a failed holding return to you'.
    public static func holdingFailed(_ s: inout GameState, holdingID: Int) {
        for j in s.companies.indices where s.companies[j].holdingID == holdingID {
            s.companies[j].holdingID = 0
            s.note("\(s.companies[j].name) is owned by you directly now.", tone: "n", companyID: s.companies[j].id)
        }
    }

    // MARK: Tax group

    /// The companies that share this year's profits and losses with `co`, or nil. Original: `taxGroup`.
    public static func taxGroup(of co: Company, in s: GameState) -> [Company]? {
        guard co.form == .limited else { return nil }
        let h: Company?
        if co.type == "hold" { h = co } else if co.holdingID != 0 { h = s.company(co.holdingID) } else { h = nil }
        guard let hold = h, hold.status.isLive else { return nil }
        let members = [hold] + s.companies.filter {
            $0.holdingID == hold.id && $0.form == .limited && $0.status.isLive && $0.status != .setup && $0.ownership >= 90 && $0.countryCode == hold.countryCode
        }
        return members.count > 1 && members.contains(where: { $0.id == co.id }) ? members : nil
    }

    /// Profit of this company that covers a sister company's loss (`out`), and loss of this company that is covered (`in`).
    /// Original: `groupContrib`.
    public static func groupContribution(_ co: Company, in s: GameState) -> (out: Double, in: Double) {
        guard let group = taxGroup(of: co, in: s) else { return (0, 0) }
        func p(_ c: Company) -> Double { max(0, c.yearProfitSoFar - (c.lossCarryAtYearStart ?? 0)) }
        func l(_ c: Company) -> Double { max(0, -c.yearProfitSoFar) }
        let tp = group.reduce(0) { $0 + p($1) }, tl = group.reduce(0) { $0 + l($1) }
        let used = min(tp, tl)
        if used <= 0 { return (0, 0) }
        return (p(co) / tp * used, l(co) / tl * used)
    }

    // MARK: Reading for screens

    public struct Subsidiary: Identifiable, Equatable {
        public var id: Int
        public var name: String, trade: String
        public var ownership: Double
        public var value: Double, share: Double
        public var revenueTTM: Double, profitTTM: Double
        public var cash: Double
        public var inTaxGroup: Bool
    }

    /// One view of the holding and everything under it. `share` figures are what the holding owns (value x ownership).
    public struct Consolidated: Equatable {
        public var holdingCash = 0.0, indexFund = 0.0, indexCost = 0.0
        public var holdingValue = 0.0
        public var subsidiaries: [Subsidiary] = []
        /// Sum over the companies of the holding's share of revenue / profit over twelve months (plus its own income)
        public var revenueTTM = 0.0, profitTTM = 0.0
        public var cashInGroup = 0.0, debtInGroup = 0.0
        public var companiesValue: Double { subsidiaries.reduce(0) { $0 + $1.share } }
        public var dividendsThisYear = 0.0
        public var taxSaved = 0.0
        public var groupCovered = 0.0
    }

    public static func consolidated(_ h: Company, _ s: GameState, trades: any TradeCatalogProviding) -> Consolidated {
        var c = Consolidated()
        c.holdingCash = h.cash
        c.indexFund = indexValue(h, s)
        c.indexCost = h.value("fm")["idxCost"].double
        let group = taxGroup(of: h, in: s) ?? []
        for k in subsidiaries(of: h.id, in: s) {
            let v = max(0, Valuation.companyValue(k, state: s, trades: trades))
            let hist = k.monthlyHistory.suffix(12)
            let own = k.ownership / 100
            let sub = Subsidiary(id: k.id, name: k.name, trade: trades.facts(for: k.type)?.id ?? k.type, ownership: k.ownership, value: v, share: v * own,
                                 revenueTTM: hist.reduce(0) { $0 + $1.revenue }, profitTTM: hist.reduce(0) { $0 + $1.profit }, cash: k.cash,
                                 inTaxGroup: group.contains { $0.id == k.id })
            c.subsidiaries.append(sub)
            c.revenueTTM += sub.revenueTTM * own
            c.profitTTM += sub.profitTTM * own
            c.cashInGroup += max(0, k.cash)
            c.debtInGroup += CompanyFigures.debts(k, loans: s.loans)
            let gc = groupContribution(k, in: s)
            c.groupCovered += gc.out
        }
        let hh = h.monthlyHistory.suffix(12)
        c.revenueTTM += hh.reduce(0) { $0 + $1.revenue }
        c.profitTTM += hh.reduce(0) { $0 + $1.profit }
        c.cashInGroup += max(0, h.cash)
        c.debtInGroup += CompanyFigures.debts(h, loans: s.loans)
        c.holdingValue = h.cash + c.indexFund + c.companiesValue
        return c
    }
}
