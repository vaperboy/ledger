import Foundation
import GameCore
import Countries
import Finance

/// One report the company can buy.
public struct ResearchOption: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var cost: Double
    public var weeks: Int
}

/// A delivered report: a few short lines worked out from the market as it was on the day it arrived.
public struct ResearchReport: Identifiable, Equatable, Sendable {
    public var id: Int
    public var optionID: String
    public var title: String
    public var day: Int            // week * 7 + day
    public var findings: [String]
}

/// Market research: four reports a company can buy (demand forecast, competitor scan, price benchmark, best next product). The cost is paid
/// when it is ordered; the report arrives after its weeks and is kept (newest 12) in `co.res27`; an inbox message tells you. A market advisor
/// (`NewItemOptions.hasAdvisor`) halves the cost and the weeks (rounded up, at least 1). The findings use real data only and draw no random numbers.
/// Cost = scaledPrice(base) x max(1, sqrt(size)): forecast 2400, competitor scan 1600, price benchmark 1000, next product 3200.
/// Weeks: 3, 2, 1, 4..
public enum MarketResearch {
    static let key = "res27"
    static let keep = 12
    /// (id, title, detail, base cost in hundreds before scaling, weeks)
    static let catalog: [(String, String, String, Double, Int)] = [
        ("forecast", "Demand forecast", "Where demand is heading over the next 8 weeks: season, the economy and fading rival pressure.", 24, 3),
        ("rivals", "Competitor scan", "Who you compete with here, what they charge and what they are doing.", 16, 2),
        ("benchmark", "Price benchmark", "How your prices compare with the market and with each rival.", 10, 1),
        ("product", "Best next product", "Which new product or service would earn you the most.", 32, 4),
    ]

    public static func options(_ s: GameState, companyID: Int, data: GameData) -> [ResearchOption] {
        guard let co = s.company(companyID), co.status == .open, data.catalog[co.type] != nil else { return [] }
        let cur = World(state: s, data: data).currency(co)
        let advisor = NewItemOptions.hasAdvisor(co)
        let scale = max(1, co.size.squareRoot())
        return catalog.map { c in
            let cost = (cur.scaledPrice(c.3 * 100) * scale).rounded()
            return ResearchOption(id: c.0, title: c.1, detail: c.2, cost: advisor ? (cost / 2).rounded() : cost, weeks: advisor ? max(1, (c.4 + 1) / 2) : c.4)
        }
    }

    public static func reports(_ co: Company) -> [ResearchReport] {
        co.value(key)["r"].array.map { ResearchReport(id: $0["i"].int, optionID: $0["o"].string, title: $0["t"].string, day: $0["d"].int, findings: $0["f"].array.map { $0.string }) }
    }

    /// Ordered and not yet delivered: (option id, week it arrives).
    public static func pending(_ co: Company) -> [(optionID: String, dueWeek: Int)] {
        co.value(key)["o"].array.map { ($0["o"].string, $0["due"].int) }
    }

    public static func refusal(_ s: GameState, companyID: Int, optionID: String, data: GameData) -> String? {
        guard let co = s.company(companyID), co.status == .open else { return "Only an open company can order research." }
        guard let o = options(s, companyID: companyID, data: data).first(where: { $0.id == optionID }) else { return "That report is not on offer." }
        if pending(co).contains(where: { $0.optionID == optionID }) { return "That report is already on its way." }
        if co.cash < o.cost { return "The company does not have the cash for it yet." }
        return nil
    }

    public static func buy(_ s: inout GameState, companyID: Int, optionID: String, data: GameData) {
        guard let i = s.companyIndex(companyID), let o = options(s, companyID: companyID, data: data).first(where: { $0.id == optionID }) else { return }
        _ = Payments.companyPays(&s, companyID: companyID, amount: o.cost, category: "oth", label: "Market research: \(o.title)")
        var r = s.companies[i].value(key)
        if r.isNull { r = .object(["o": .array([]), "r": .array([])]) }
        var orders = r["o"].array
        orders.append(.object(["o": .string(optionID), "due": .number(Double(s.week + o.weeks))]))
        r["o"] = .array(orders)
        s.companies[i].set(key, r)
        s.note("\(s.companies[i].name) ordered a \(o.title.lowercased()); it arrives in \(o.weeks) week\(o.weeks == 1 ? "" : "s").", tone: "n", companyID: companyID)
    }

    /// Delivers what is due. Called at the end of the week.
    public static func weekly(_ s: inout GameState, data: GameData) {
        for i in s.companies.indices {
            let orders = s.companies[i].value(key)["o"].array
            guard !orders.isEmpty else { continue }
            let due = orders.filter { s.week >= $0["due"].int }
            guard !due.isEmpty else { continue }
            var r = s.companies[i].value(key)
            r["o"] = .array(orders.filter { s.week < $0["due"].int })
            var list = r["r"].array
            for d in due {
                let id = d["o"].string
                guard let c = catalog.first(where: { $0.0 == id }) else { continue }
                let lines = s.companies[i].status == .open ? findings(s, s.companies[i], optionID: id, data: data) : []
                let rid = s.makeID()
                list.append(.object(["i": .number(Double(rid)), "o": .string(id), "t": .string(c.1), "d": .number(Double(s.week * 7 + s.day)), "f": .array(lines.map { .string($0) })]))
                let mid = s.addMessage(kind: "doc", from: "Market research", title: "\(c.1) ready for \(s.companies[i].name)", body: lines.joined(separator: "\n"), companyID: s.companies[i].id, tone: "good")
                if let k = s.inbox.firstIndex(where: { $0.id == mid }) { s.inbox[k].doc = document(optionID: id, title: c.1, company: s.companies[i], reportID: rid, lines: lines, state: s) }
            }
            if list.count > keep { list.removeFirst(list.count - keep) }
            r["r"] = .array(list)
            s.companies[i].set(key, r)
        }
    }

    // MARK: The report as an inbox document

    /// The findings grouped into sections: Summary (the headline), the topic of the report, and a Recommendation.
    static func document(optionID: String, title: String, company co: Company, reportID: Int, lines: [String], state s: GameState) -> InboxDocument {
        let topic = ["forecast": "Demand", "rivals": "Competitors", "benchmark": "Prices", "product": "Products"][optionID] ?? "Findings"
        let advice = [
            "forecast": "Plan stock and staffing for the demand above, and do not commit to large purchases before the season turns.",
            "rivals": "Watch the biggest rival first; answer a price cut with value, not a price war, unless your margin allows it.",
            "benchmark": "Move items that sit far from the market price back towards it, one step at a time, and watch sales for two weeks.",
            "product": "Develop the top product first if the pay-back is under a year; the second only when the first is selling.",
        ][optionID] ?? "Review the findings with your manager."
        var sections = [InboxDocument.Section(heading: "Summary", lines: Array(lines.prefix(1)))]
        if lines.count > 1 { sections.append(InboxDocument.Section(heading: topic, lines: Array(lines.dropFirst()))) }
        sections.append(InboxDocument.Section(heading: "Recommendation", lines: [advice]))
        return InboxDocument(title: "\(title): \(co.name)", issuer: "Ledger Market Research", date: GameCalendar.dateString(week: s.week, dayOffset: s.day),
                             reference: "LMR-\(String(format: "%05d", reportID))", sections: sections)
    }

    // MARK: Findings

    static func pct(_ x: Double) -> String { String(format: "%+.1f%%", x * 100) }

    static func findings(_ s: GameState, _ co: Company, optionID: String, data: GameData) -> [String] {
        guard let bd = data.catalog[co.type] else { return [] }
        let w = World(state: s, data: data)
        switch optionID {
        case "forecast": return forecast(s, co, bd, w, data)
        case "rivals": return rivalScan(s, co, bd, w)
        case "benchmark": return benchmark(s, co, bd, w)
        default: return bestProduct(s, co, bd, w, data)
        }
    }

    /// Expected change of demand 8 weeks ahead, split in its parts.
    static func forecast(_ s: GameState, _ co: Company, _ bd: Trade, _ w: World, _ data: GameData) -> [String] {
        var later = w
        later.state.week += 8
        let seasonNow = DemandModel.season(bd, w, for: co), seasonLater = DemandModel.season(bd, later, for: co)
        let season = seasonNow > 0 ? seasonLater / seasonNow - 1 : 0
        let pressure = MarketPressure.demandMultiplier(co, week: s.week + 8) / max(0.01, MarketPressure.demandMultiplier(co, week: s.week)) - 1
        let econ = (1 - s.economy.demand) * 0.4 * 0.5        // the economy drifts halfway back towards normal, and moves demand by 40 percent of its gap
        let total = (1 + season) * (1 + pressure) * (1 + econ) - 1
        var out = ["Expected demand over the next 8 weeks: \(pct(total)) against now."]
        out.append("Season: \(pct(season)). Economy: \(pct(econ)).")
        let now = MarketPressure.pressure(co, week: s.week)
        out.append(abs(now) < 0.0005 ? "No rival pressure on demand at the moment." : "Rival pressure takes \(pct(-now)) of demand now; in 8 weeks it will be \(pct(-MarketPressure.pressure(co, week: s.week + 8))).")
        return out
    }

    static func rivalScan(_ s: GameState, _ co: Company, _ bd: Trade, _ w: World) -> [String] {
        let rivals = Rivals.rivals(s, for: co).sorted { $0.size != $1.size ? $0.size > $1.size : $0.id < $1.id }
        guard !rivals.isEmpty else { return ["No named rivals in your market right now."] }
        var out = ["\(rivals.count) rival\(rivals.count == 1 ? "" : "s") in your market; the biggest is \(rivals[0].name)."]
        for r in rivals.prefix(3) {
            var doing: [String] = []
            if let d = r.discountPercent { doing.append("\(d)% off") }
            if r.marketing { doing.append("marketing push") }
            if r.holdingPrices { doing.append("holding prices") }
            if r.forSale { doing.append("for sale") }
            out.append("\(r.name): \(r.strategy), prices \(pct(r.priceFactor - 1)) against the market\(doing.isEmpty ? "" : ", " + doing.joined(separator: ", ")).")
        }
        let launches = MarketPressure.pressure(co, week: s.week, kind: .launch) + MarketPressure.pressure(co, week: s.week, kind: .response)
        if launches > 0.0005 { out.append("Their moves take \(pct(-launches)) of your demand right now.") }
        return out
    }

    static func benchmark(_ s: GameState, _ co: Company, _ bd: Trade, _ w: World) -> [String] {
        let mine = Pricing.priceIndex(co, w) / max(0.01, co.num("ig", 1))
        let mkt = s.rest["mk"]?[Rivals.key(co)]["pi"] ?? .null
        let market = mkt.isNull ? 1 : mkt.double
        var out = ["Your prices are \(pct(mine / max(0.01, market) - 1)) against the market average."]
        let rivals = Rivals.rivals(s, for: co)
        if let lo = rivals.map({ $0.priceFactor }).min(), let hi = rivals.map({ $0.priceFactor }).max() {
            out.append("Rivals charge from \(pct(lo - 1)) to \(pct(hi - 1)) against the market.")
        }
        for it in SalesItems.items(co, bd) where abs(it.effectiveMultiplier - 1) >= 0.05 {
            out.append("\(it.name): \(pct(it.effectiveMultiplier - 1)) against its market price.")
        }
        if out.count == (rivals.isEmpty ? 1 : 2) { out.append("Your items are all at their market prices.") }
        return out
    }

    static func bestProduct(_ s: GameState, _ co: Company, _ bd: Trade, _ w: World, _ data: GameData) -> [String] {
        var best: [(name: String, profit: Double, weeks: Int, cost: Double, net: Double)] = []
        for svc in [false, true] {
            for o in NewItemOptions.list(s, companyID: co.id, isService: svc, data: data).options {
                let lift = o.needsDevelopment ? NewItemOptions.categoryLift : NewItemOptions.variantLift
                let p = NewItemOptions.estimate(s, co, bd, lift: lift, w: w).0
                best.append((o.name, p, o.developmentWeeks, o.developmentCost, p * 52 - o.developmentCost))
            }
        }
        best.sort { $0.net != $1.net ? $0.net > $1.net : $0.name < $1.name }
        guard let top = best.first else { return ["Nothing new to add: you already sell what fits."] }
        let cur = w.currency(co)
        func line(_ b: (name: String, profit: Double, weeks: Int, cost: Double, net: Double)) -> String {
            "\(b.name): about \(cur.display(b.profit)) more profit a week\(b.weeks > 0 ? ", \(b.weeks) weeks and \(cur.display(b.cost)) to develop" : ", on sale at once")."
        }
        var out = ["Best next product: " + line(top)]
        if best.count > 1 { out.append("Next best: " + line(best[1])) }
        return out
    }
}
