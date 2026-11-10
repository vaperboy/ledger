import Foundation
import GameCore
import Countries
import Finance

public enum UnlockRule: Equatable, Sendable {
    case always
    case week(Int), goal(Int), profitableQuarters(Int), rich
    case firstSalesWeek, firstProfitMonth, firstLossEvent
    case weeksTraded(Int), boardSeat, retainedProfit
    case anyOf([UnlockRule])
}

enum Feature: Hashable, Sendable {
    case gate(Gate)
    case unlock(String)
}

struct RuleEntry: Sendable {
    var feature: Feature
    var title: String
    var rule: UnlockRule
    var text: String
    var roadmap = true
}

public enum Gate: String, CaseIterable, Sendable {
    case hiring, marketing, ownerMoney, bank, newCompany, management, accounting, insurance, suppliers, property
    case group, rivals, ventures, luxury, atlas
    case weather, airstay, techpro, marketplace, reviews
    case ownerHours

    var rule: UnlockRule { Gates.entry(.gate(self)).rule }

    public var lockText: String? {
        let t: String = Gates.entry(.gate(self)).text
        return t.isEmpty ? nil : t
    }
}

public enum GateVisibility: Equatable, Sendable {
    case open
    case locked(String)
    case hidden
}

public struct UnlockRoadmapItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var condition: String
    public var progress: Double
    public var detail: String
    public var companyID: Int?
}

public enum Gates {
    public static let richMultiple = 50.0
    public static let earlyHoursCap = 45.0
    static let nearWeeks = 2
    static let eventNearWeek = 2

    static let table: [RuleEntry] = [
        RuleEntry(feature: .gate(.hiring), title: "Hiring", rule: .week(3), text: "Unlocks in week 3"),
        RuleEntry(feature: .gate(.marketing), title: "Marketing", rule: .anyOf([.goal(3), .week(6)]), text: "Unlocks after your first hire, or in week 6"),
        RuleEntry(feature: .gate(.reviews), title: "Reviews", rule: .anyOf([.goal(3), .week(6)]), text: "Unlocks after your first hire, or in week 6", roadmap: false),
        RuleEntry(feature: .gate(.ownerMoney), title: "Your own pay", rule: .anyOf([.goal(4), .week(8)]), text: "Unlocks after your first decision, or in week 8"),
        RuleEntry(feature: .gate(.bank), title: "Bank", rule: .anyOf([.goal(7), .firstLossEvent, .week(8)]),
                  text: "Unlocks after your first profitable month or loss, or in week 8"),
        RuleEntry(feature: .gate(.newCompany), title: "New companies", rule: .anyOf([.goal(7), .week(13)]), text: "Unlocks after your first profitable month, or in week 13"),
        RuleEntry(feature: .gate(.management), title: "Management", rule: .anyOf([.goal(7), .week(13)]), text: "Unlocks after your first profitable month, or in week 13"),
        RuleEntry(feature: .gate(.accounting), title: "Accounting", rule: .anyOf([.goal(7), .firstLossEvent, .week(8)]),
                  text: "Opens with your first profitable month or loss, or in week 8"),
        RuleEntry(feature: .gate(.techpro), title: "TechPro", rule: .anyOf([.goal(7), .week(13)]), text: "Unlocks after your first profitable month, or in week 13", roadmap: false),
        RuleEntry(feature: .gate(.insurance), title: "Insurance", rule: .anyOf([.firstProfitMonth, .firstLossEvent]),
                  text: "Unlocks with your first profitable month or your first loss"),
        RuleEntry(feature: .gate(.weather), title: "Weather", rule: .anyOf([.firstProfitMonth, .firstLossEvent]),
                  text: "Unlocks with your first profitable month or your first loss", roadmap: false),
        RuleEntry(feature: .gate(.suppliers), title: "Suppliers", rule: .firstSalesWeek, text: "Unlocks after your first week of sales"),
        RuleEntry(feature: .gate(.marketplace), title: "Marketplace", rule: .firstSalesWeek, text: "Unlocks after your first week of sales", roadmap: false),
        RuleEntry(feature: .gate(.property), title: "Property", rule: .anyOf([.goal(9), .week(17)]), text: "Unlocks after your first quarter of trading, or in week 17"),
        RuleEntry(feature: .gate(.rivals), title: "Rivals", rule: .anyOf([.goal(9), .week(17)]), text: "Unlocks after your first quarter of trading, or in week 17"),
        RuleEntry(feature: .gate(.airstay), title: "AirStay", rule: .anyOf([.goal(9), .week(17)]), text: "Unlocks after your first quarter of trading, or in week 17", roadmap: false),
        RuleEntry(feature: .gate(.group), title: "Group", rule: .anyOf([.goal(7), .week(13)]), text: "Unlocks after your first profitable month, or in week 13"),
        RuleEntry(feature: .gate(.atlas), title: "Atlas", rule: .anyOf([.firstProfitMonth, .firstLossEvent]),
                  text: "Unlocks with your first profitable month or your first loss"),
        RuleEntry(feature: .gate(.ventures), title: "Ventures", rule: .anyOf([.profitableQuarters(1), .week(26)]),
                  text: "Unlocks after your first profitable quarter, or in week 26"),
        RuleEntry(feature: .gate(.luxury), title: "Luxury", rule: .rich, text: "Unlocks when you are rich"),
        RuleEntry(feature: .gate(.ownerHours), title: "Owner hours", rule: .week(13), text: "", roadmap: false),
        RuleEntry(feature: .unlock("board"), title: "Board", rule: .boardSeat,
                  text: "Unlocks when a limited company has a manager or candidate who could take a seat, or it gets co-owners or a chain"),
        RuleEntry(feature: .unlock("research"), title: "Market research", rule: .weeksTraded(Unlocks.weeksResearch),
                  text: "Unlocks when the company is \(Unlocks.weeksResearch) weeks old"),
        RuleEntry(feature: .unlock("dividends"), title: "Dividends", rule: .retainedProfit, text: "Unlocks when the company has retained profit to pay out"),
        RuleEntry(feature: .unlock("marketplace"), title: "Marketplace", rule: .always, text: "Unlocks when the company exists", roadmap: false),
        RuleEntry(feature: .unlock("desk"), title: "Desk", rule: .weeksTraded(Unlocks.weeksDesk), text: "Unlocks when the company has traded \(Unlocks.weeksDesk) weeks and the first steps are done", roadmap: false),
        RuleEntry(feature: .unlock("focus"), title: "Weekly plan", rule: .weeksTraded(Unlocks.weeksFocus), text: "Unlocks when the company has traded \(Unlocks.weeksFocus) weeks and the first steps are done", roadmap: false),
        RuleEntry(feature: .unlock("rivals"), title: "Rivals", rule: .weeksTraded(Unlocks.weeksRivals), text: "Unlocks when the company has traded \(Unlocks.weeksRivals) weeks and the first steps are done", roadmap: false),
    ]

    public static func title(_ g: Gate) -> String { entry(.gate(g)).title }

    static func entry(_ f: Feature) -> RuleEntry {
        table.first { (e: RuleEntry) -> Bool in e.feature == f } ?? RuleEntry(feature: f, title: "", rule: .always, text: "", roadmap: false)
    }

    public static func ladderOn(_ s: GameState) -> Bool { s.rest["ldr"] != nil }

    public static func goalsDone(_ s: GameState) -> Int { s.rest["ldr"]?["done"].object.count ?? 0 }

    public static func goalDone(_ s: GameState, _ n: Int) -> Bool { !(s.rest["ldr"]?["done"]["M\(n)"] ?? .null).isNull }

    public static func companiesOwned(_ s: GameState) -> Int { s.companies.filter { $0.status.isLive && $0.type != "hold" }.count }

    public static func profitableYears(_ s: GameState) -> Int {
        let cs = s.companies.filter { $0.type != "hold" }
        let years = (cs.map { $0.monthlyHistory.count }.max() ?? 0) / 12
        var n = 0
        for b in 0..<years {
            let total = cs.reduce(0.0) { acc, c in
                let h = c.monthlyHistory
                let hi = h.count - 12 * b, lo = hi - 12
                return lo < 0 ? acc : acc + h[lo..<hi].reduce(0.0) { $0 + $1.profit }
            }
            if total > 0 { n += 1 }
        }
        return n
    }

    public static let monthsPerQuarter = 3

    public static func profitableQuarters(_ s: GameState) -> Int {
        let cs = s.companies.filter { $0.type != "hold" }
        let quarters = (cs.map { $0.monthlyHistory.count }.max() ?? 0) / monthsPerQuarter
        var n = 0
        for b in 0..<quarters {
            let total = cs.reduce(0.0) { acc, c in
                let h = c.monthlyHistory
                let hi = h.count - monthsPerQuarter * b, lo = hi - monthsPerQuarter
                return lo < 0 ? acc : acc + h[lo..<hi].reduce(0.0) { $0 + $1.profit }
            }
            if total > 0 { n += 1 }
        }
        return n
    }

    public static func closedMonths(_ s: GameState) -> Int {
        s.companies.filter { $0.type != "hold" }.map { $0.monthlyHistory.count }.max() ?? 0
    }

    public static func netWorthLimit(_ s: GameState, data: GameData) -> Double {
        data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode).medianMonthlyWage * richMultiple
    }

    static func trading(_ s: GameState) -> [Company] { s.companies.filter { $0.type != "hold" } }

    public static let reviewRule: UnlockRule = .week(52)
    public static func reviewOpen(_ s: GameState) -> Bool { met(reviewRule, s, data: nil, company: nil, context: nil) }

    static func met(_ r: UnlockRule, _ s: GameState, data: GameData?, company: Company?, context: FinanceContext?) -> Bool {
        switch r {
        case .always: return company?.status.isLive ?? true
        case .week(let w): return s.week >= w
        case .goal(let n): return goalDone(s, n)
        case .profitableQuarters(let n): return profitableQuarters(s) >= n
        case .rich:
            guard let data else { return false }
            return Valuation.netWorth(s, trades: data.catalog).total > netWorthLimit(s, data: data)
        case .firstSalesWeek:
            return s.week >= 1 && trading(s).contains { (c: Company) -> Bool in (c.books.total["rev"] ?? 0) > 0 }
        case .firstProfitMonth:
            return trading(s).contains { (c: Company) -> Bool in c.monthlyHistory.contains { (m: MonthRecord) -> Bool in m.profit > 0 } }
        case .firstLossEvent:
            return trading(s).contains { (c: Company) -> Bool in
                let t: [String: Double] = c.books.total
                return (t["loss"] ?? 0) + (t["fine"] ?? 0) > 0 || c.monthlyHistory.contains { (m: MonthRecord) -> Bool in m.profit < 0 }
            }
        case .weeksTraded(let n):
            guard let company else { return false }
            return Unlocks.weeksTraded(s, company) >= n
        case .boardSeat:
            guard let company else { return false }
            return Unlocks.boardPossible(s, company)
        case .retainedProfit:
            guard let company, let context else { return false }
            return (company.distributed > 0 || Payments.maximumDividend(company, state: s, context: context) > 0)
        case .anyOf(let rs):
            return rs.contains { (x: UnlockRule) -> Bool in met(x, s, data: data, company: company, context: context) }
        }
    }

    static func progress(_ r: UnlockRule, _ s: GameState, data: GameData?, company: Company?) -> (fraction: Double, detail: String) {
        func ratio(_ a: Double, _ b: Double) -> Double { b <= 0 ? 0 : min(1, max(0, a / b)) }
        switch r {
        case .always: return (1, "")
        case .week(let w): return (ratio(Double(s.week), Double(w)), "Week \(s.week) of \(w)")
        case .goal(let n): return (ratio(Double(goalsDone(s)), Double(n)), "Goal \(min(goalsDone(s), n)) of \(n)")
        case .profitableQuarters(let n):
            if profitableQuarters(s) >= n { return (1, "\(n) of \(n) profitable quarters") }
            let months: Int = min(closedMonths(s), monthsPerQuarter * n)
            return (min(0.9, ratio(Double(months), Double(monthsPerQuarter * n))), "\(months) of \(monthsPerQuarter * n) months closed, in profit overall")
        case .rich:
            guard let data else { return (0, "") }
            let limit: Double = netWorthLimit(s, data: data)
            return (min(0.99, ratio(Valuation.netWorth(s, trades: data.catalog).total, limit)), "")
        case .firstSalesWeek:
            let selling: Bool = trading(s).contains { (c: Company) -> Bool in (c.books.total["rev"] ?? 0) > 0 }
            return (selling ? 0.5 : 0, selling ? "Sales have started" : "No sales yet")
        case .firstProfitMonth:
            let closed: Bool = trading(s).contains { (c: Company) -> Bool in !c.monthlyHistory.isEmpty }
            return (closed ? 0.5 : 0, closed ? "A month has closed without a profit" : "No month closed yet")
        case .firstLossEvent: return (0, "")
        case .weeksTraded(let n):
            guard let company else { return (0, "") }
            let w: Int = Unlocks.weeksTraded(s, company)
            return (ratio(Double(w), Double(n)), "\(min(w, n)) of \(n) weeks")
        case .boardSeat, .retainedProfit: return (0, "")
        case .anyOf(let rs):
            var best: (fraction: Double, detail: String) = (0, "")
            for x in rs {
                let p = progress(x, s, data: data, company: company)
                if p.fraction > best.fraction { best = p }
            }
            return best
        }
    }

    static let openKey = "gateG"

    public static func isOpen(_ g: Gate, _ s: GameState, data: GameData) -> Bool {
        guard ladderOn(s) else { return true }
        if !(s.rest[openKey]?[g.rawValue] ?? .null).isNull { return true }
        return met(g.rule, s, data: data, company: nil, context: nil)
    }

    public static func recordOpen(_ s: inout GameState, data: GameData) {
        guard ladderOn(s) else { return }
        var rec: JSONValue = s.rest[openKey] ?? .object([:])
        var changed = false
        for g in Gate.allCases where rec[g.rawValue].isNull && met(g.rule, s, data: data, company: nil, context: nil) {
            rec[g.rawValue] = .number(Double(s.week))
            changed = true
        }
        if changed { s.rest[openKey] = rec }
    }

    static func near(_ r: UnlockRule, _ s: GameState) -> Bool {
        switch r {
        case .week(let w): return w - s.week <= nearWeeks
        case .goal(let n): return n - goalsDone(s) <= 1
        case .firstSalesWeek, .firstProfitMonth, .firstLossEvent, .profitableQuarters: return s.week >= eventNearWeek
        case .anyOf(let rs): return rs.contains { (x: UnlockRule) -> Bool in near(x, s) }
        case .rich, .always, .weeksTraded, .boardSeat, .retainedProfit: return false
        }
    }

    public static func visibility(_ g: Gate, _ s: GameState, data: GameData) -> GateVisibility {
        if isOpen(g, s, data: data) { return .open }
        guard let text = g.lockText else { return .hidden }
        return near(g.rule, s) ? .locked(text) : .hidden
    }

    public static func ownerHoursCap(_ s: GameState) -> Double {
        ladderOn(s) && s.week < 13 ? earlyHoursCap : OwnerHours.weeklyCap
    }

    public static func roadmap(_ s: GameState, data: GameData, context: FinanceContext) -> [UnlockRoadmapItem] {
        let live: [Company] = s.companies.filter { (c: Company) -> Bool in c.status.isLive && c.type != "hold" }
        var rows: [(order: Int, item: UnlockRoadmapItem)] = []
        for (i, e) in table.enumerated() where e.roadmap {
            switch e.feature {
            case .gate(let g):
                if isOpen(g, s, data: data) { continue }
                let p = progress(e.rule, s, data: data, company: nil)
                rows.append((i, UnlockRoadmapItem(id: "gate." + g.rawValue, title: e.title, condition: e.text, progress: p.fraction, detail: p.detail, companyID: nil)))
            case .unlock(let id):
                if Unlocks.playerHas(s, id) { continue }
                var open = false
                var bestFraction = 0.0
                var bestDetail = ""
                var bestID: Int? = nil
                for co in live {
                    let items: [UnlockItem] = Unlocks.state(s, companyID: co.id, context: context)
                    guard let it = items.first(where: { (u: UnlockItem) -> Bool in u.id == id }) else { continue }
                    if it.unlocked { open = true; break }
                    let p = progress(e.rule, s, data: data, company: co)
                    if bestID == nil || p.fraction > bestFraction { bestFraction = p.fraction; bestDetail = p.detail; bestID = co.id }
                }
                if open { continue }
                rows.append((i, UnlockRoadmapItem(id: "unlock." + id, title: e.title, condition: e.text, progress: bestFraction, detail: bestDetail, companyID: bestID)))
            }
        }
        let sorted = rows.sorted { (a: (order: Int, item: UnlockRoadmapItem), b: (order: Int, item: UnlockRoadmapItem)) -> Bool in
            a.item.progress != b.item.progress ? a.item.progress > b.item.progress : a.order < b.order
        }
        return sorted.map { (r: (order: Int, item: UnlockRoadmapItem)) -> UnlockRoadmapItem in r.item }
    }
}
