import Foundation
import GameCore
import Countries
import Finance
import Businesses

public struct Insight: Identifiable, Equatable, Sendable {
    public enum Tone: String, Sendable { case good, warn, bad, neutral }
    public var id: String
    public var symbol: String
    public var text: String
    public var tone: Tone

    public var section: String? {
        switch id {
        case "cap", "rivals", "repair": return "operations"
        case "slack", "mkt": return "marketing"
        case "wages": return "staff"
        case "rent", "cash", "overdrawn", "bigpay", "cashprofit", "margin": return "finances"
        case "setup": return "setup"
        case "prop", "vacancy", "cover", "worn", "carry": return "properties"
        case "regulator", "solvency", "claims", "products", "capital", "cbfacility", "hwm": return "book"
        default: return nil
        }
    }
}

public struct CompanyHealth: Equatable, Sendable {
    public var value = 0.0
    public var revenueTTM = 0.0
    public var profitTTM = 0.0
    public var debt = 0.0
    public var revenueGrowth: Double?
    public var capacityUse = 0.0
    public var demandCoverage = 0.0
    public var rating = 0.0
    public var label = "New"
    public var weeklyCost = 0.0
    public var weeksOfCash = 0.0
    public var runwayWeeks: Double?
    public var servedLastWeek = 0.0
    public var capacityLastWeek = 0.0
    public var bottleneck: String?
    public var limitedBy: String?
    public var marginTTM: Double? { revenueTTM > 0 ? profitTTM / revenueTTM : nil }
    public var revenueSeries: [Double] = []
    public var profitSeries: [Double] = []
    public var cashSeries: [Double] = []
}

public extension GameEngine {
    func companyHealth(_ co: Company) -> CompanyHealth {
        var h = CompanyHealth()
        h.value = Valuation.companyValue(co, state: state, trades: data.catalog)
        let hist = co.monthlyHistory
        h.revenueTTM = hist.suffix(12).reduce(0) { $0 + $1.revenue }
        h.profitTTM = hist.suffix(12).reduce(0) { $0 + $1.profit }
        h.debt = CompanyFigures.debts(co, loans: state.loans)
        h.revenueSeries = hist.suffix(24).map { $0.revenue }
        h.profitSeries = hist.suffix(24).map { $0.profit }
        h.cashSeries = hist.suffix(24).map { $0.cash }
        if hist.count >= 6 {
            let a = hist.suffix(3).reduce(0) { $0 + $1.revenue }, b = hist.suffix(6).prefix(3).reduce(0) { $0 + $1.revenue }
            if b > homeCurrency.scaledPrice(1000) { h.revenueGrowth = a / b - 1 }
        }
        let lw = co.value("lastW")
        if !lw.isNull {
            h.capacityUse = lw["cap"].double > 0 ? lw["units"].double / lw["cap"].double : 0
            h.demandCoverage = lw["cap"].double > 0 ? lw["D"].double / lw["cap"].double : 0
        }
        h.rating = Pricing.rating(co)
        h.weeklyCost = weeklyCost(co)
        h.weeksOfCash = CompanyFigures.weeksOfCash(cash: co.cash, weeklyCost: h.weeklyCost)
        let recent = hist.suffix(3)
        let monthlyProfit = recent.isEmpty ? 0 : recent.reduce(0) { $0 + $1.profit } / Double(recent.count)
        h.runwayWeeks = CompanyFigures.runwayWeeks(cash: co.cash, weeklyLoss: -monthlyProfit * 12 / 52)
        if !lw.isNull { h.servedLastWeek = lw["units"].double; h.capacityLastWeek = lw["cap"].double }
        if co.status == .open, let bd = data.catalog[co.type], !SpecialFamilies.handles(bd) {
            h.bottleneck = weakestLink(co, bd)
            h.limitedBy = salesLimit(co).name
        }
        let months = hist.count
        if months < 3 { h.label = co.status == .open ? "New" : "Setting up" }
        else if co.cash < 0 || h.profitTTM < 0 && co.cash < weeklyCost(co) * 4 { h.label = "Struggling" }
        else if h.profitTTM < 0 || co.cash < weeklyCost(co) * 6 { h.label = "Tight" }
        else if h.profitTTM > 0, (h.revenueGrowth ?? 0) > 0.05 { h.label = "Thriving" }
        else { h.label = "Healthy" }
        return h
    }

    private func weeklyCost(_ co: Company) -> Double { context.weeklyCost(co, state) }

    // The capacity part with the least room; a week that served no one or had an outage keeps its own reason.
    private func weakestLink(_ co: Company, _ bd: Trade) -> String? {
        let lw = co.value("lastW")
        let then: String = lw["bot"].string
        if lw["cap"].double == 0 || !lw["out"].string.isEmpty, !then.isEmpty { return then }
        return CapacityModel.compute(co, bd, World(state: state, data: data)).bottleneck?.label
    }

    // What held last week's sales. Capacity is named only when demand passed it and it was used up.
    func salesLimit(_ co: Company) -> SalesLimit {
        let lw = co.value("lastW")
        let waiting = SalesLimit(kind: .unknown, name: nil, text: "Shows after the first trading week")
        guard co.status == .open, !lw.isNull, let bd = data.catalog[co.type] else { return waiting }
        let ownModel: Bool = SpecialFamilies.handles(bd)
        switch SalesLimit.reading(units: lw["units"].double, demand: lw["D"].double, capacity: lw["cap"].double) {
        case .unknown:
            return waiting
        case .stopped:
            let why: String? = ownModel ? nil : weakestLink(co, bd)
            let reason: String = why.map { (t: String) -> String in t.prefix(1).lowercased() + t.dropFirst() } ?? "staff or equipment is missing"
            return SalesLimit(kind: .stopped, name: why, text: "Served no one last week: " + reason)
        case .capacity:
            return SalesLimit(kind: .capacity, name: (ownModel ? nil : weakestLink(co, bd)) ?? "Capacity", text: "Capacity is the limit: customers are turned away")
        case .demand:
            return SalesLimit(kind: .demand, name: "Demand", text: "Demand is the limit: there is room for more customers")
        case .held:
            let why = heldBack(co, bd)
            return SalesLimit(kind: .held, name: why.name, text: why.text)
        }
    }

    // Why fewer were served than both demand and capacity allowed.
    private func heldBack(_ co: Company, _ bd: Trade) -> (name: String, text: String) {
        let start = data.balance.firstYear, lw = co.value("lastW")
        if start.untended(state), lw["units"].double <= lw["cap"].double * start.serveShare(state) + 1 { return ("Prices not set", "Held back until you set a price") }
        let soldOut = Int(saturating: co.value("dlast")["so"].double)
        if soldOut > 0 { return ("Stock", "Sold out on \(soldOut) day\(soldOut == 1 ? "" : "s") last week: the shelves ran empty") }
        if bd.hasTrait("sub") { return ("Members", "Members join over time: the place is still filling up") }
        if let target = StockHandling.policyTarget(co, bd), co.inventory < target * 0.5 { return ("Stock", "Stock ran short: there was too little to sell") }
        return ("Sales", "Fewer were served than demand and capacity allow")
    }

    func insights(for co: Company, limit: Int = 4) -> [Insight] {
        var out: [Insight] = []
        let cur = currency(for: co)
        let lw = co.value("lastW")
        let w = World(state: state, data: data)
        if co.status == .setup {
            let missing = openingChecklist(companyID: co.id).filter { !$0.isDone }
            out.append(Insight(id: "setup", symbol: "checklist", text: missing.isEmpty ? "Everything is ready; the company opens as soon as the first stock can be paid for." : "Not open yet: \(missing.prefix(3).map { $0.title }.joined(separator: ", ")) still to do.", tone: .warn))
        }
        let special = data.catalog[co.type].map { SpecialFamilies.handles($0) } ?? false
        if special { out += specialInsights(for: co) }
        if co.status == .open, !lw.isNull, !special {
            let cap = lw["cap"].double, D = lw["D"].double, util = lw["util"].double
            if !lw["out"].string.isEmpty { out.append(Insight(id: "repair", symbol: "wrench.and.screwdriver", text: lw["out"].string, tone: .warn)) }
            if cap > 0, D > cap * 1.12, util > 0.93 { out.append(Insight(id: "cap", symbol: "gauge.with.dots.needle.100percent", text: "Capacity is limiting sales: about \(Int(saturating: jsRound(D - cap))) customers a week are turned away. More staff or equipment would add revenue.", tone: .warn)) }
            else if cap > 0, util < 0.5 {
                let limit = salesLimit(co)
                let used = "Only \(Int(saturating: jsRound(util * 100)))% of capacity is used. "
                if limit.kind == .held { out.append(Insight(id: "slack", symbol: "person.3", text: used + limit.text + ".", tone: .warn)) }
                else { out.append(Insight(id: "slack", symbol: "person.3", text: used + "Demand is the limit: price, marketing and reputation matter more than hiring.", tone: .neutral)) }
            }
        }
        let rev = co.books.month["rev"] ?? 0, wages = co.books.month["wages"] ?? 0, rent = co.books.month["rent"] ?? 0
        if rev > 0, wages / rev > 0.55 { out.append(Insight(id: "wages", symbol: "banknote", text: "Wages are \(Int(saturating: jsRound(wages / rev * 100)))% of this month's revenue, which leaves little for profit.", tone: .warn)) }
        if rev > 0, rent / rev > 0.2 { out.append(Insight(id: "rent", symbol: "building", text: "Rent takes \(Int(saturating: jsRound(rent / rev * 100)))% of revenue this month.", tone: .warn)) }
        let hist = co.monthlyHistory
        if hist.count >= 3, co.cash < (hist[hist.count - 3].cash) * 0.8, co.cash > 0, hist.last!.revenue > 0 {
            out.append(Insight(id: "cash", symbol: "arrow.down.right", text: "Cash has fallen over the last three months, from \(cur.short(hist[hist.count - 3].cash)) to \(cur.short(co.cash)).", tone: .warn))
        }
        if co.cash < 0 { out.append(Insight(id: "overdrawn", symbol: "exclamationmark.triangle", text: "The account is overdrawn. Put money in before the next payday.", tone: .bad)) }
        if let g = companyHealth(co).revenueGrowth, abs(g) > 0.08 {
            out.append(Insight(id: "growth", symbol: g > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis", text: "Revenue is \(g > 0 ? "up" : "down") \(Int(saturating: jsRound(abs(g) * 100)))% on the previous three months.", tone: g > 0 ? .good : .warn))
        }
        if let bd = data.catalog[co.type], co.status == .open, !special {
            let rival = Competition.rivalFactor(co, w)
            if rival < 0.8 { out.append(Insight(id: "rivals", symbol: "person.2", text: "Competitors are taking about \(Int(saturating: jsRound((1 - rival) * 100)))% of the customers you would otherwise have. Their prices and number matter here.", tone: .warn)) }
            _ = bd
        }
        let open = co.value("compl").array.filter { $0["st"].string == "open" }.count
        if open > 0 { out.append(Insight(id: "compl", symbol: "text.bubble", text: "\(open) customer complaint\(open == 1 ? "" : "s") waiting. Unanswered ones turn into bad reviews.", tone: .bad)) }
        if co.value("flags")["mktPausedWeek"].double >= Double(state.week - 4), co.value("flags")["mktPausedWeek"].double > 0 {
            out.append(Insight(id: "mkt", symbol: "pause.circle", text: "Campaigns are paused because paying for them would break your cash reserve.", tone: .warn))
        }
        if hist.count >= 6 {
            let a = Array(hist.suffix(3)), b = Array(hist.suffix(6).prefix(3))
            let ra = a.reduce(0) { $0 + $1.revenue }, rb = b.reduce(0) { $0 + $1.revenue }
            let ma = ra > 0 ? a.reduce(0) { $0 + $1.profit } / ra : 0, mb = rb > 0 ? b.reduce(0) { $0 + $1.profit } / rb : 0
            if ra > rb * 1.05, mb - ma > 0.04 {
                out.append(Insight(id: "margin", symbol: "arrow.down.forward.and.arrow.up.backward", text: "Revenue is growing, but the profit margin fell from \(Int(saturating: jsRound(mb * 100)))% to \(Int(saturating: jsRound(ma * 100)))%: costs are rising faster than sales.", tone: .warn))
            }
            let profit3 = a.reduce(0) { $0 + $1.profit }
            if profit3 > 0, let c0 = b.last?.cash, co.cash < c0 * 0.85 {
                out.append(Insight(id: "cashprofit", symbol: "arrow.left.arrow.right", text: "The company made \(cur.short(profit3)) in three months, yet its cash fell from \(cur.short(c0)) to \(cur.short(co.cash)): repayments, purchases or payouts are taking more than it earns.", tone: .warn))
            }
        }
        if co.status.isLive, let big = financeOverview(companyID: co.id).upcoming.filter({ $0.daysAway <= 31 && $0.essential }).max(by: { $0.amount < $1.amount }),
           big.amount > max(0, co.cash) * 0.6, big.amount > weeklyCost(co) {
            out.append(Insight(id: "bigpay", symbol: "calendar.badge.exclamationmark", text: "\(big.title) of \(cur.short(big.amount)) is due \(big.daysAway <= 0 ? "today" : "in \(big.daysAway) days"); the account holds \(cur.short(max(0, co.cash))).", tone: big.amount > co.cash ? .bad : .warn))
        }
        out += rentalFinanceInsights(for: co)
        out += projectInsights(for: co)
        if out.isEmpty, co.status == .open { out.append(Insight(id: "ok", symbol: "checkmark.seal", text: "Nothing unusual. The business is running as expected.", tone: .good)) }
        let order: [Insight.Tone: Int] = [.bad: 0, .warn: 1, .neutral: 2, .good: 3]
        return Array(out.sorted { (order[$0.tone] ?? 9) < (order[$1.tone] ?? 9) }.prefix(limit))
    }
}

public struct SalesLimit: Equatable, Sendable {
    public enum Kind: String, Sendable { case unknown, demand, capacity, stopped, held }
    public var kind: Kind
    public var name: String?
    public var text: String

    static let usedShare = 0.85
    static let servedShare = 0.7

    // Small slack keeps weekly noise from flipping the reading on low volumes.
    public static func reading(units: Double, demand: Double, capacity: Double) -> Kind {
        if capacity <= 0 { return demand > 0 ? .stopped : .unknown }
        if demand > capacity { return units >= capacity * usedShare - 1 ? .capacity : .held }
        return units >= demand * servedShare - 2 ? .demand : .held
    }
}

public struct OperationsFigures: Equatable, Sendable {
    public struct Week: Equatable, Sendable, Identifiable {
        public var week: Int
        public var demand: Double
        public var capacity: Double
        public var served: Double
        public var id: Int { week }
        public var capacityUse: Double { capacity > 0 ? served / capacity : 0 }
    }
    public var capacityUse: Double?
    public var limit: SalesLimit
    public var profitPerWeek: Double?
    public var profitChangePerWeek: Double?
    public var weeks: [Week]
}

public extension GameEngine {
    func operationsFigures(companyID: Int) -> OperationsFigures? {
        guard let co = state.company(companyID) else { return nil }
        let lw = co.value("lastW")
        let hist = co.monthlyHistory
        var f = OperationsFigures(capacityUse: nil, limit: salesLimit(co), profitPerWeek: nil, profitChangePerWeek: nil, weeks: [])
        if !lw.isNull, lw["cap"].double > 0 { f.capacityUse = lw["units"].double / lw["cap"].double }
        if let last = hist.last {
            f.profitPerWeek = last.profit / 4.33
            if hist.count >= 2 { f.profitChangePerWeek = (last.profit - hist[hist.count - 2].profit) / 4.33 }
        }
        f.weeks = co.value("wkHist").array.map { (j: JSONValue) -> OperationsFigures.Week in
            let served: Double = j["u"].isNull ? min(j["D"].double, j["cap"].double) : j["u"].double
            return OperationsFigures.Week(week: j["w"].int, demand: j["D"].double, capacity: j["cap"].double, served: served)
        }
        return f
    }
}
