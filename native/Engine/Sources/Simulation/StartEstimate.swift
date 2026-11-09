import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum StartBudget: String, CaseIterable, Sendable { case small, medium, large }

public enum StartTime: String, CaseIterable, Sendable { case handsOff, handsOn }

/// Where a city's start-up costs split into thirds (cheapest third, middle, dearest) over the trades that can be started there.
public struct StartCostTiers: Equatable, Sendable {
    public var lowTop: Double
    public var midTop: Double
    public func budget(for cost: Double) -> StartBudget { cost <= lowTop ? .small : cost <= midTop ? .medium : .large }
}

public extension Trade {
    /// The owner is needed for less than half a post, so the business runs mostly without them.
    var isHandsOff: Bool { ownerFTE < 0.5 }
    /// The owner fills a whole post with their own skilled work.
    var needsOwnerSkill: Bool { ownerFTE >= 1 }
}

/// Everything about starting one trade that needs no simulation: what it costs, what it costs to keep, how long the cash lasts.
public struct StartFacts: Equatable, Sendable {
    public var tradeID: String
    public var name: String
    public var family: String
    public var cityID: String
    public var cityName: String
    public var size: Double
    public var staffCount: Int
    public var startCost: Double
    public var payNow: Double
    public var cashLeft: Double
    public var companyCash: Double
    public var weeklyCosts: Double
    public var runwayWeeks: Int?
    public var costTier: StartBudget
    public var handsOff: Bool
    public var needsSkill: Bool
    public var skillName: String
    public var shortfall: Double
    public var invest: Double
}

/// The result of trial runs of one trade, played on a copy of the game with nothing else in it.
public struct StartRuns: Equatable, Sendable {
    public struct Run: Equatable, Sendable {
        public var firstMonth: Double
        public var weeklyRate: Double
        public var lostMoneyAtWeek12: Bool
        public var ranOut: Bool
    }
    public var runs: [Run]
    public var closeReturn: Double
}

/// A copy of the game's data that plays trial runs of a new company away from the main thread: the engine it makes is its own.
public struct StartSimulationJob: @unchecked Sendable {
    public static let weeks = 26
    public static let seeds = 3
    var state: GameState
    var data: GameData
    var events: EventLibrary
    var marketing: MarketingTables
    var tradeID: String
    var cityID: String
    var size: Double
    var invest: Double

    public func run() -> StartRuns {
        var out: [StartRuns.Run] = []
        var closeReturn = 0.0
        let salt: Int = tradeID.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        for k in 0..<Self.seeds {
            var e = GameEngine(state: state, data: data, events: events, marketing: marketing)
            var id = 0
            let seed: Int = state.seed &+ salt &+ 7919 &* (k + 1)
            let trade = tradeID, city = cityID, sz = size, cash = invest
            e.update { s, d, ctx in
                s.companies.removeAll()
                s.random = DeterministicRandom(seed: seed)
                Ledger.move(&s, .me, 20_000_000_000, why: "Trial run")
                guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: city, size: sz, data: d, context: ctx) else { return }
                id = i
                _ = Payments.injectCash(&s, companyID: i, amount: cash)
                _ = CompanySetup.quickSetup(&s, companyID: i, data: d)
            }
            guard id != 0, let start = e.state.company(id) else { continue }
            if k == 0 { closeReturn = e.windUpEstimate(companyID: id) }
            let cash0 = start.cash
            var path: [Double] = [cash0]
            var ranOut = false
            for _ in 0..<Self.weeks {
                for _ in 0..<7 {
                    e.nextDay()
                    for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
                }
                guard let co = e.state.company(id), co.status.isLive else { ranOut = true; break }
                path.append(co.cash)
            }
            let n = path.count - 1
            let window = min(8, n)
            let rate: Double = window > 0 ? (path[n] - path[n - window]) / Double(window) : 0
            let month: Double = (n >= 4 ? path[4] : path[n]) - cash0
            let lost: Bool = n >= 12 ? path[12] < cash0 : true
            out.append(StartRuns.Run(firstMonth: month, weeklyRate: ranOut ? min(rate, 0) : rate, lostMoneyAtWeek12: lost, ranOut: ranOut))
        }
        return StartRuns(runs: out, closeReturn: closeReturn)
    }
}

/// What the start screens say about one trade: the facts plus ranges from trial runs. Nothing here promises a profit.
public struct StartEstimate: Equatable, Sendable {
    public enum Pill: String, Equatable, Sendable { case easier = "Easier to run", care = "Needs care", lowCost = "Low cost" }
    public enum Risk: String, Equatable, Sendable {
        case lower = "Lower", moderate = "Medium", high = "High"
        public var rank: Int { self == .lower ? 0 : self == .moderate ? 1 : 2 }
    }

    public var facts: StartFacts
    public var runsCount: Int
    public var paybackLow: Int?
    public var paybackHigh: Int?
    public var someNeverPayBack: Bool
    public var firstMonthLow: Double
    public var firstMonthHigh: Double
    public var closeReturn: Double
    public var risk: Risk
    public var pill: Pill
    public var riskLine: String

    public init(facts: StartFacts, runs: StartRuns) {
        self.facts = facts
        let rs = runs.runs
        runsCount = rs.count
        closeReturn = runs.closeReturn
        let paying = rs.filter { !$0.ranOut && $0.weeklyRate > 0 }.map { facts.payNow / $0.weeklyRate }.filter { $0.isFinite && $0 < 1_000_000 }
        paybackLow = paying.min().map { max(1, Int($0.rounded(.down))) }
        paybackHigh = paying.max().map { max(1, Int($0.rounded(.up))) }
        someNeverPayBack = paying.count < rs.count
        firstMonthLow = rs.map { $0.firstMonth }.min() ?? 0
        firstMonthHigh = rs.map { $0.firstMonth }.max() ?? 0
        let ranOut = rs.filter { $0.ranOut }.count
        let lost = rs.filter { $0.lostMoneyAtWeek12 }.count
        let never = rs.count - paying.count
        let level: Risk = rs.isEmpty || ranOut > 0 || lost * 3 >= rs.count * 2 ? .high : (lost == 0 && never == 0 ? .lower : .moderate)
        risk = level
        if rs.isEmpty {
            riskLine = "No trial run could be played for this business."
        } else if ranOut > 0 {
            riskLine = "In \(ranOut) of \(rs.count) trial runs the business ran out of money."
        } else if lost > 0 {
            riskLine = "\(lost) of \(rs.count) trial runs were still losing money after 12 weeks."
        } else if never > 0 {
            riskLine = "\(never) of \(rs.count) trial runs did not earn back the start cost."
        } else {
            riskLine = "Trial runs earned money, but your own results depend on price, place and how you run it."
        }
        if level == .lower && !facts.needsSkill { pill = .easier } else if facts.costTier == .small { pill = .lowCost } else { pill = .care }
    }

    /// The best matches first: lower risk, then the shorter payback.
    public static func ranked(_ list: [StartEstimate]) -> [StartEstimate] {
        list.sorted { a, b in
            if a.risk.rank != b.risk.rank { return a.risk.rank < b.risk.rank }
            return (a.paybackHigh ?? Int.max) < (b.paybackHigh ?? Int.max)
        }
    }
}

public extension GameEngine {
    /// The trades that can be started in this city, with their prices (cheapest first).
    func startableRows(cityID: String? = nil) -> [TradePickerRow] {
        tradePickerRows(cityID: cityID).filter { r in
            guard r.blocked == nil, r.startUpCost != nil, let bd = data.catalog[r.tradeID] else { return false }
            return SpecialFamilies.isStartable(bd)
        }.sorted { ($0.startUpCost ?? 0) < ($1.startUpCost ?? 0) }
    }

    func startCostTiers(cityID: String? = nil) -> StartCostTiers {
        let costs: [Double] = startableRows(cityID: cityID).compactMap { $0.startUpCost }
        guard !costs.isEmpty else { return StartCostTiers(lowTop: 0, midTop: 0) }
        return StartCostTiers(lowTop: costs[(costs.count - 1) / 3], midTop: costs[(costs.count - 1) * 2 / 3])
    }

    /// The families (trade categories) on offer in this city, in the order of the list.
    func startInterests(cityID: String? = nil) -> [String] {
        var seen: [String] = []
        for r in startableRows(cityID: cityID) where !seen.contains(r.sector) { seen.append(r.sector) }
        return seen
    }

    /// Up to `limit` trades the player can pay for, the ones that fit the answers best first (budget, time, interest each count one point).
    func startCandidates(budget: StartBudget?, time: StartTime?, interest: String?, cityID: String? = nil, limit: Int = 5) -> [TradePickerRow] {
        let rows = startableRows(cityID: cityID).filter { $0.isFunded }
        let tiers = startCostTiers(cityID: cityID)
        func score(_ r: TradePickerRow) -> Int {
            var n = 0
            if let budget, let c = r.startUpCost, tiers.budget(for: c) == budget { n += 1 }
            if let time, let bd = data.catalog[r.tradeID], bd.isHandsOff == (time == .handsOff) { n += 1 }
            if let interest, r.sector == interest { n += 1 }
            return n
        }
        let scored = rows.map { ($0, score($0)) }
        return Array(scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : ($0.0.startUpCost ?? 0) < ($1.0.startUpCost ?? 0) }.prefix(limit).map { $0.0 })
    }

    /// The costs of starting one trade now in a city, at the size the player's money carries.
    func startFacts(tradeID: String, cityID: String? = nil) -> StartFacts? {
        let city = cityID ?? state.player.cityID
        guard let bd = data.catalog[tradeID], SpecialFamilies.isStartable(bd) else { return nil }
        let country = homeCountry
        let c: Country.City = country.cities.first { $0.id == city } ?? country.cities[0]
        let size = affordableStartSize(tradeID: tradeID, cityID: city) ?? CompanySetup.recommendedSize(bd, city: c)
        let choices = suggestedChoices(tradeID: tradeID, cityID: city, size: size)
        guard let plan = newCompanyPlan(tradeID: tradeID, cityID: city, size: size, choices: choices, withAlternatives: false),
              let monthly = monthlyFixedCostEstimate(tradeID: tradeID, cityID: city) else { return nil }
        let weekly = monthly.total / (52.0 / 12)
        let companyCash = max(0, plan.companyCashAfterSetup)
        let runway: Int? = weekly > 0 ? Int((companyCash / weekly).rounded(.down)) : nil
        let est = plan.estimate
        return StartFacts(tradeID: tradeID, name: bd.name, family: bd.category, cityID: city, cityName: c.name, size: size, staffCount: monthly.staffCount,
                          startCost: plan.total, payNow: plan.intoCompany + est.shareCapital + est.registration + est.abroad, cashLeft: plan.accountsAfter,
                          companyCash: companyCash, weeklyCosts: weekly, runwayWeeks: runway, costTier: startCostTiers(cityID: city).budget(for: plan.total),
                          handsOff: bd.isHandsOff, needsSkill: bd.needsOwnerSkill, skillName: bd.skillName,
                          shortfall: max(plan.shortfall, plan.registrationShortfall), invest: plan.intoCompany)
    }

    /// The trial runs for these facts, to be played with `run()` (off the main thread if the screen should stay live).
    func startJob(_ facts: StartFacts) -> StartSimulationJob {
        StartSimulationJob(state: state, data: data, events: events, marketing: marketing, tradeID: facts.tradeID, cityID: facts.cityID, size: facts.size, invest: facts.invest)
    }

    /// Facts and trial runs together, played on the calling thread.
    func startEstimate(tradeID: String, cityID: String? = nil) -> StartEstimate? {
        guard let facts = startFacts(tradeID: tradeID, cityID: cityID) else { return nil }
        return StartEstimate(facts: facts, runs: startJob(facts).run())
    }
}
