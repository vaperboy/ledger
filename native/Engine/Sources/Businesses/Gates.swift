import Foundation
import GameCore
import Countries
import Finance

/// What a feature waits for. One vocabulary for the app surfaces (gates) and the per-company unlocks; `Gates.table` is the only place
/// that says which feature waits for what, and `Gates.met` is the only place that tests it.
public enum UnlockRule: Equatable, Sendable {
    /// Nothing to wait for (a company-level feature only needs the company to exist).
    case always
    /// A game week, a ladder goal (1 to 10), a number of companies, profitable closed years, or wealth.
    case week(Int), goal(Int), companies(Int), profitableYears(Int), rich
    /// A week closed with sales, a month closed in profit, a loss or fine booked or a month closed at a loss.
    case firstSalesWeek, firstProfitMonth, firstLossEvent
    /// Company level: weeks traded, twelve closed months in profit, a proven pilot, a possible board seat, profit to pay out.
    case weeksTraded(Int), profitableYear, provenConcept, boardSeat, retainedProfit
    /// Any one of these.
    case anyOf([UnlockRule])
}

/// A feature of the table: a surface of the app or a per-company unlock (by its `Unlocks` id).
enum Feature: Hashable, Sendable {
    case gate(Gate)
    case unlock(String)
}

/// One row of the table: the rule, the plain-words condition, and whether the roadmap lists it (systems that only follow another
/// system's gate are left out so the roadmap names each thing once).
struct RuleEntry: Sendable {
    var feature: Feature
    var title: String
    var rule: UnlockRule
    var text: String
    var roadmap = true
}

/// A surface of the app that stays hidden (not greyed) until its gate. Views ask `Gates.visibility`; no screen decides this itself.
/// Systems that only serve another system share its rule: reviews follow marketing, the weather app follows insurance, AirStay follows
/// property, TechPro follows management, the marketplace follows suppliers and the ventures feed follows ventures.
public enum Gate: String, CaseIterable, Sendable {
    case hiring, marketing, ownerMoney, bank, newCompany, management, accounting, insurance, suppliers, property
    case group, rivals, ventures, luxury, atlas
    case weather, airstay, techpro, marketplace, reviews, venturesFeed
    case ownerHours

    var rule: UnlockRule { Gates.entry(.gate(self)).rule }

    /// The line shown when the gate is near; nil for owner hours (silent).
    public var lockText: String? {
        let t: String = Gates.entry(.gate(self)).text
        return t.isEmpty ? nil : t
    }
}

public enum GateVisibility: Equatable, Sendable {
    case open
    /// Closed but near: show the surface dimmed with this line.
    case locked(String)
    /// Closed and far: not on Home, not in the grid, no Inbox items, no menu entries.
    case hidden
}

/// One locked feature for the "what unlocks next" screen.
public struct UnlockRoadmapItem: Equatable, Sendable, Identifiable {
    /// "gate.<name>" for an app surface, "unlock.<id>" for a company feature.
    public var id: String
    public var title: String
    /// What it waits for, in plain words.
    public var condition: String
    /// 0 to 1, how close the player is.
    public var progress: Double
    /// A short "2 of 3 companies" style line; empty when there is nothing to count.
    public var detail: String
    /// The company that is closest, for a company feature (nil for an app surface).
    public var companyID: Int?
}

public enum Gates {
    /// Net worth above this many median monthly wages opens the luxury surfaces.
    public static let richMultiple = 50.0
    /// Owner hours are capped at this until week 13 (silently).
    public static let earlyHoursCap = 45.0
    /// A week gate is "near" within this many weeks; a goal gate within one goal.
    static let nearWeeks = 2
    /// Event gates (first sales, first profit, first loss) show dimmed from this week on.
    static let eventNearWeek = 2

    /// The one rule table. Insurance opens with the first profitable month or the first loss (the two moments a business learns it needs
    /// cover) and suppliers after the first week of sales; the manager-related features stay with the ladder's manager goal and the 52-week chain.
    static let table: [RuleEntry] = [
        RuleEntry(feature: .gate(.hiring), title: "Hiring", rule: .week(3), text: "Unlocks in week 3"),
        RuleEntry(feature: .gate(.marketing), title: "Marketing", rule: .goal(3), text: "Unlocks after your first hire"),
        RuleEntry(feature: .gate(.reviews), title: "Reviews", rule: .goal(3), text: "Unlocks after your first hire", roadmap: false),
        RuleEntry(feature: .gate(.ownerMoney), title: "Your own pay", rule: .goal(4), text: "Unlocks after your first decision"),
        RuleEntry(feature: .gate(.bank), title: "Bank", rule: .goal(7), text: "Unlocks after your first profitable month"),
        RuleEntry(feature: .gate(.newCompany), title: "New companies", rule: .goal(7), text: "Unlocks after your first profitable month"),
        RuleEntry(feature: .gate(.management), title: "Management", rule: .goal(7), text: "Unlocks after your first profitable month"),
        RuleEntry(feature: .gate(.accounting), title: "Accounting", rule: .goal(7), text: "Opens with your first profitable month"),
        RuleEntry(feature: .gate(.techpro), title: "TechPro", rule: .goal(7), text: "Unlocks after your first profitable month", roadmap: false),
        RuleEntry(feature: .gate(.insurance), title: "Insurance", rule: .anyOf([.firstProfitMonth, .firstLossEvent]),
                  text: "Unlocks with your first profitable month or your first loss"),
        RuleEntry(feature: .gate(.weather), title: "Weather", rule: .anyOf([.firstProfitMonth, .firstLossEvent]),
                  text: "Unlocks with your first profitable month or your first loss", roadmap: false),
        RuleEntry(feature: .gate(.suppliers), title: "Suppliers", rule: .firstSalesWeek, text: "Unlocks after your first week of sales"),
        RuleEntry(feature: .gate(.marketplace), title: "Marketplace", rule: .firstSalesWeek, text: "Unlocks after your first week of sales", roadmap: false),
        RuleEntry(feature: .gate(.property), title: "Property", rule: .goal(9), text: "Unlocks with your second company"),
        RuleEntry(feature: .gate(.rivals), title: "Rivals", rule: .goal(9), text: "Unlocks with your second company"),
        RuleEntry(feature: .gate(.airstay), title: "AirStay", rule: .goal(9), text: "Unlocks with your second company", roadmap: false),
        RuleEntry(feature: .gate(.group), title: "Group", rule: .companies(3), text: "Unlocks with three companies"),
        RuleEntry(feature: .gate(.atlas), title: "Atlas", rule: .companies(3), text: "Unlocks with three companies"),
        RuleEntry(feature: .gate(.ventures), title: "Ventures", rule: .profitableYears(2), text: "Unlocks after two profitable years"),
        RuleEntry(feature: .gate(.venturesFeed), title: "Ventures feed", rule: .profitableYears(2), text: "Unlocks after two profitable years", roadmap: false),
        RuleEntry(feature: .gate(.luxury), title: "Luxury", rule: .rich, text: "Unlocks when you are rich"),
        RuleEntry(feature: .gate(.ownerHours), title: "Owner hours", rule: .week(13), text: "", roadmap: false),
        // Company features, announced once by `Unlocks`.
        RuleEntry(feature: .unlock("board"), title: "Board", rule: .boardSeat,
                  text: "Unlocks when a limited company has a manager or candidate who could take a seat, or it gets co-owners or a chain"),
        RuleEntry(feature: .unlock("chain"), title: "Chain", rule: .weeksTraded(Unlocks.weeksChain),
                  text: "Unlocks when the company has traded \(Unlocks.weeksChain) weeks"),
        RuleEntry(feature: .unlock("franchise"), title: "Franchising", rule: .provenConcept,
                  text: "Unlocks with a proven concept: \(Unlocks.weeksChain) weeks traded and four profitable quarters"),
        RuleEntry(feature: .unlock("abroad"), title: "Expand abroad", rule: .profitableYear, text: "Unlocks after a profitable year (twelve closed months in profit)"),
        RuleEntry(feature: .unlock("research"), title: "Market research", rule: .weeksTraded(Unlocks.weeksResearch),
                  text: "Unlocks when the company is \(Unlocks.weeksResearch) weeks old"),
        RuleEntry(feature: .unlock("dividends"), title: "Dividends", rule: .retainedProfit, text: "Unlocks when the company has retained profit to pay out"),
        RuleEntry(feature: .unlock("marketplace"), title: "Marketplace", rule: .always, text: "Unlocks when the company exists", roadmap: false),
    ]

    static func entry(_ f: Feature) -> RuleEntry {
        table.first { (e: RuleEntry) -> Bool in e.feature == f } ?? RuleEntry(feature: f, title: "", rule: .always, text: "", roadmap: false)
    }

    /// The ladder is on for games started with it (`rest["ldr"]`); an older save has no ladder and nothing is gated.
    public static func ladderOn(_ s: GameState) -> Bool { s.rest["ldr"] != nil }

    /// Goals finished on the ladder (it is linear, so also the number of the open goal minus one, 0 to 10).
    public static func goalsDone(_ s: GameState) -> Int { s.rest["ldr"]?["done"].object.count ?? 0 }

    /// Goal `n` (1 to 10) is finished.
    public static func goalDone(_ s: GameState, _ n: Int) -> Bool { !(s.rest["ldr"]?["done"]["M\(n)"] ?? .null).isNull }

    /// Companies the player owns (a holding is not counted).
    public static func companiesOwned(_ s: GameState) -> Int { s.companies.filter { $0.status.isLive && $0.type != "hold" }.count }

    /// Closed years in which the group's companies together made a profit, counted back from the latest twelve closed months.
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

    public static func netWorthLimit(_ s: GameState, data: GameData) -> Double {
        data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode).medianMonthlyWage * richMultiple
    }

    /// Companies that have been trading (a holding does not trade); closed ones still count, their history is the player's.
    static func trading(_ s: GameState) -> [Company] { s.companies.filter { $0.type != "hold" } }

    /// The one test of a rule. `company` is needed for company-level rules, `data` for wealth and `context` for dividends.
    static func met(_ r: UnlockRule, _ s: GameState, data: GameData?, company: Company?, context: FinanceContext?) -> Bool {
        switch r {
        case .always: return company?.status.isLive ?? true
        case .week(let w): return s.week >= w
        case .goal(let n): return goalDone(s, n)
        case .companies(let n): return companiesOwned(s) >= n
        case .profitableYears(let n): return profitableYears(s) >= n
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
        case .profitableYear:
            guard let company else { return false }
            return (Unlocks.yearProfit(company) ?? 0) > 0
        case .provenConcept:
            guard let company else { return false }
            return Franchising.provenConcept(s, company).ok
        case .boardSeat:
            guard let company else { return false }
            return Unlocks.boardPossible(s, company)
        case .retainedProfit:
            guard let company, let context else { return false }
            return company.form == .limited && (company.distributed > 0 || Payments.maximumDividend(company, state: s, context: context) > 0)
        case .anyOf(let rs):
            return rs.contains { (x: UnlockRule) -> Bool in met(x, s, data: data, company: company, context: context) }
        }
    }

    /// How close a rule is to being met: a fraction and a short count ("2 of 3 companies"); event rules have no count and show 0 or a half.
    static func progress(_ r: UnlockRule, _ s: GameState, data: GameData?, company: Company?) -> (fraction: Double, detail: String) {
        func ratio(_ a: Double, _ b: Double) -> Double { b <= 0 ? 0 : min(1, max(0, a / b)) }
        switch r {
        case .always: return (1, "")
        case .week(let w): return (ratio(Double(s.week), Double(w)), "Week \(s.week) of \(w)")
        case .goal(let n): return (ratio(Double(goalsDone(s)), Double(n)), "Goal \(min(goalsDone(s), n)) of \(n)")
        case .companies(let n): return (ratio(Double(companiesOwned(s)), Double(n)), "\(min(companiesOwned(s), n)) of \(n) companies")
        case .profitableYears(let n): return (ratio(Double(profitableYears(s)), Double(n)), "\(min(profitableYears(s), n)) of \(n) profitable years")
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
        case .profitableYear:
            guard let company else { return (0, "") }
            let m: Int = Unlocks.monthsClosed(company)
            return (ratio(Double(m), 12), "\(m) of 12 months closed")
        case .provenConcept:
            guard let company else { return (0, "") }
            let p = Franchising.provenProgress(s, company)
            let weeks: Int = max(0, p.weeks)
            return (ratio(Double(min(weeks, 52)) / 52 + Double(p.quarters) / 4, 2), "\(weeks) of 52 weeks, \(p.quarters) of 4 profitable quarters")
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

    public static func isOpen(_ g: Gate, _ s: GameState, data: GameData) -> Bool {
        guard ladderOn(s) else { return true }
        return met(g.rule, s, data: data, company: nil, context: nil)
    }

    /// A closed rule is "near" when it is one goal, two weeks, one company or one year away (event rules from week 2).
    static func near(_ r: UnlockRule, _ s: GameState) -> Bool {
        switch r {
        case .week(let w): return w - s.week <= nearWeeks
        case .goal(let n): return n - goalsDone(s) <= 1
        case .companies(let n): return companiesOwned(s) + 1 >= n
        case .profitableYears(let n): return profitableYears(s) + 1 >= n
        case .firstSalesWeek, .firstProfitMonth, .firstLossEvent: return s.week >= eventNearWeek
        case .anyOf(let rs): return rs.contains { (x: UnlockRule) -> Bool in near(x, s) }
        case .rich, .always, .weeksTraded, .profitableYear, .provenConcept, .boardSeat, .retainedProfit: return false
        }
    }

    /// Open, locked-and-near or hidden.
    public static func visibility(_ g: Gate, _ s: GameState, data: GameData) -> GateVisibility {
        if isOpen(g, s, data: data) { return .open }
        guard let text = g.lockText else { return .hidden }
        return near(g.rule, s) ? .locked(text) : .hidden
    }

    /// Hours cap for the owner this week: 45 before week 13 in a game with the ladder, else the usual cap.
    public static func ownerHoursCap(_ s: GameState) -> Double {
        ladderOn(s) && s.week < 13 ? earlyHoursCap : OwnerHours.weeklyCap
    }

    /// Every feature still locked, closest first (ties in table order): app surfaces by the player's state, company features by the
    /// company nearest to opening them. A feature any live company has already opened is not listed.
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
