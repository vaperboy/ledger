import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// A short, specific explanation of what is happening in a company, worked out from its real numbers.
public struct Insight: Identifiable, Equatable, Sendable {
    public enum Tone: String, Sendable { case good, warn, bad, neutral }
    public var id: String
    public var symbol: String
    public var text: String
    public var tone: Tone

    /// The part of the company screen where the player can act on it ("operations", "staff", "finances", "marketing", "setup"), if any.
    public var section: String? {
        switch id {
        case "cap", "rivals": return "operations"
        case "slack", "mkt": return "marketing"
        case "wages", "paper": return "staff"
        case "rent", "cash", "overdrawn", "bigpay", "cashprofit", "margin": return "finances"
        case "setup": return "setup"
        default: return nil
        }
    }
}

/// What the Company dashboard shows besides the figures: value, growth, health, and the operating measures of this kind of business.
public struct CompanyHealth: Equatable, Sendable {
    public var value = 0.0
    public var revenueTTM = 0.0
    public var profitTTM = 0.0
    public var debt = 0.0
    /// Revenue growth: last three closed months against the three before (nil with less than six months of history).
    public var revenueGrowth: Double?
    public var capacityUse = 0.0          // 0...1+
    public var demandCoverage = 0.0       // customers wanted per customer that can be served
    public var rating = 0.0               // 1...5
    public var label = "New"              // Thriving, Healthy, Tight, Struggling
    /// What the company spends in a normal week, and how many such weeks its cash covers.
    public var weeklyCost = 0.0
    public var weeksOfCash = 0.0
    /// Weeks until the cash is gone at the last three months' rate of loss; nil when the company is not losing money.
    public var runwayWeeks: Double?
    /// Customers served and the most it could serve last week, and what limits it.
    public var servedLastWeek = 0.0
    public var capacityLastWeek = 0.0
    public var bottleneck: String?
    /// Profit as a share of revenue over the last twelve months.
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
            if b > 1000 { h.revenueGrowth = a / b - 1 }
        }
        let lw = co.value("lastW")
        if !lw.isNull {
            h.capacityUse = lw["cap"].double > 0 ? lw["units"].double / lw["cap"].double : 0
            h.demandCoverage = lw["cap"].double > 0 ? lw["D"].double / lw["cap"].double : 0
        }
        h.rating = Pricing.rating(co)
        h.weeklyCost = weeklyCost(co)
        h.weeksOfCash = h.weeklyCost > 0 ? max(0, co.cash) / h.weeklyCost : 0
        let recent = hist.suffix(3)
        let monthlyProfit = recent.isEmpty ? 0 : recent.reduce(0) { $0 + $1.profit } / Double(recent.count)
        if monthlyProfit < 0 { h.runwayWeeks = max(0, co.cash) / (-monthlyProfit * 12 / 52) }
        if !lw.isNull { h.servedLastWeek = lw["units"].double; h.capacityLastWeek = lw["cap"].double }
        if co.status == .open, let bd = data.catalog[co.type] {
            h.bottleneck = CapacityModel.compute(co, bd, World(state: state, data: data)).bottleneck?.label
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

    /// Up to `limit` plain-language findings about one company, most important first.
    func insights(for co: Company, limit: Int = 4) -> [Insight] {
        var out: [Insight] = []
        let cur = currency(for: co)
        let lw = co.value("lastW")
        let w = World(state: state, data: data)
        if co.status == .setup {
            let missing = openingChecklist(companyID: co.id).filter { !$0.isDone }
            out.append(Insight(id: "setup", symbol: "checklist", text: missing.isEmpty ? "Everything is ready; the company opens as soon as the first stock can be paid for." : "Not open yet: \(missing.prefix(3).map { $0.title }.joined(separator: ", ")) still to do.", tone: .warn))
        }
        if co.status == .open, !lw.isNull {
            let cap = lw["cap"].double, D = lw["D"].double, util = lw["util"].double
            if cap > 0, D > cap * 1.12, util > 0.93 { out.append(Insight(id: "cap", symbol: "gauge.with.dots.needle.100percent", text: "Capacity is limiting sales: about \(Int(jsRound(D - cap))) customers a week are turned away. More staff or equipment would add revenue.", tone: .warn)) }
            else if cap > 0, util < 0.5 { out.append(Insight(id: "slack", symbol: "person.3", text: "Only \(Int(jsRound(util * 100)))% of capacity is used. Demand is the limit: price, marketing and reputation matter more than hiring.", tone: .neutral)) }
        }
        let rev = co.books.month["rev"] ?? 0, wages = co.books.month["wages"] ?? 0, rent = co.books.month["rent"] ?? 0
        if rev > 0, wages / rev > 0.55 { out.append(Insight(id: "wages", symbol: "banknote", text: "Wages are \(Int(jsRound(wages / rev * 100)))% of this month's revenue, which leaves little for profit.", tone: .warn)) }
        if rev > 0, rent / rev > 0.2 { out.append(Insight(id: "rent", symbol: "building", text: "Rent takes \(Int(jsRound(rent / rev * 100)))% of revenue this month.", tone: .warn)) }
        let hist = co.monthlyHistory
        if hist.count >= 3, co.cash < (hist[hist.count - 3].cash) * 0.8, co.cash > 0, hist.last!.revenue > 0 {
            out.append(Insight(id: "cash", symbol: "arrow.down.right", text: "Cash has fallen over the last three months, from \(cur.short(hist[hist.count - 3].cash)) to \(cur.short(co.cash)).", tone: .warn))
        }
        if co.cash < 0 { out.append(Insight(id: "overdrawn", symbol: "exclamationmark.triangle", text: "The account is overdrawn. Put money in before the next payday.", tone: .bad)) }
        if let g = companyHealth(co).revenueGrowth, abs(g) > 0.08 {
            out.append(Insight(id: "growth", symbol: g > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis", text: "Revenue is \(g > 0 ? "up" : "down") \(Int(jsRound(abs(g) * 100)))% on the previous three months.", tone: g > 0 ? .good : .warn))
        }
        if let bd = data.catalog[co.type], co.status == .open {
            let rival = Competition.rivalFactor(co, w)
            if rival < 0.8 { out.append(Insight(id: "rivals", symbol: "person.2", text: "Competitors are taking about \(Int(jsRound((1 - rival) * 100)))% of the customers you would otherwise have. Their prices and number matter here.", tone: .warn)) }
            _ = bd
        }
        let open = co.value("compl").array.filter { $0["st"].string == "open" }.count
        if open > 0 { out.append(Insight(id: "compl", symbol: "text.bubble", text: "\(open) customer complaint\(open == 1 ? "" : "s") waiting. Unanswered ones turn into bad reviews.", tone: .bad)) }
        let paperwork = co.staff.reduce(0) { $0 + StaffExtras.missing($1).count }
        if paperwork > 0 { out.append(Insight(id: "paper", symbol: "doc.badge.exclamationmark", text: "\(paperwork) staff paperwork item\(paperwork == 1 ? "" : "s") missing; an inspection can fine you.", tone: .warn)) }
        if co.value("flags")["mktPausedWeek"].double >= Double(state.week - 4), co.value("flags")["mktPausedWeek"].double > 0 {
            out.append(Insight(id: "mkt", symbol: "pause.circle", text: "Campaigns are paused because paying for them would break your cash reserve.", tone: .warn))
        }
        // Revenue up while the margin shrinks: costs are growing faster than sales
        if hist.count >= 6 {
            let a = Array(hist.suffix(3)), b = Array(hist.suffix(6).prefix(3))
            let ra = a.reduce(0) { $0 + $1.revenue }, rb = b.reduce(0) { $0 + $1.revenue }
            let ma = ra > 0 ? a.reduce(0) { $0 + $1.profit } / ra : 0, mb = rb > 0 ? b.reduce(0) { $0 + $1.profit } / rb : 0
            if ra > rb * 1.05, mb - ma > 0.04 {
                out.append(Insight(id: "margin", symbol: "arrow.down.forward.and.arrow.up.backward", text: "Revenue is growing, but the profit margin fell from \(Int(jsRound(mb * 100)))% to \(Int(jsRound(ma * 100)))%: costs are rising faster than sales.", tone: .warn))
            }
            // Profitable, yet cash keeps falling: money leaves through loan repayments, purchases or payouts
            let profit3 = a.reduce(0) { $0 + $1.profit }
            if profit3 > 0, let c0 = b.last?.cash, co.cash < c0 * 0.85 {
                out.append(Insight(id: "cashprofit", symbol: "arrow.left.arrow.right", text: "The company made \(cur.short(profit3)) in three months, yet its cash fell from \(cur.short(c0)) to \(cur.short(co.cash)): repayments, purchases or payouts are taking more than it earns.", tone: .warn))
            }
        }
        // A large payment soon that the account cannot comfortably carry
        if co.status.isLive, let big = financeOverview(companyID: co.id).upcoming.filter({ $0.daysAway <= 31 && $0.essential }).max(by: { $0.amount < $1.amount }),
           big.amount > max(0, co.cash) * 0.6, big.amount > weeklyCost(co) {
            out.append(Insight(id: "bigpay", symbol: "calendar.badge.exclamationmark", text: "\(big.title) of \(cur.short(big.amount)) is due \(big.daysAway <= 0 ? "today" : "in \(big.daysAway) days"); the account holds \(cur.short(max(0, co.cash))).", tone: big.amount > co.cash ? .bad : .warn))
        }
        if out.isEmpty, co.status == .open { out.append(Insight(id: "ok", symbol: "checkmark.seal", text: "Nothing unusual. The business is running as expected.", tone: .good)) }
        let order: [Insight.Tone: Int] = [.bad: 0, .warn: 1, .neutral: 2, .good: 3]
        return Array(out.sorted { (order[$0.tone] ?? 9) < (order[$1.tone] ?? 9) }.prefix(limit))
    }
}
