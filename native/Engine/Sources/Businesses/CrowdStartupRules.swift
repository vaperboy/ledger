import Foundation
import GameCore

public enum CrowdStartupRules {

    public static let entryCostReference: Double = 150_000
    public static let entryCostPlanShare: Double = 0.4
    public static let founderMinShare: Double = 1.0 / 3.0
    public static let stageShares: [Double] = [0.40, 0.35, 0.25]
    public static let stageNames: [String] = ["Opening", "First sales", "First profit"]
    public static let milestoneNames: [String] = ["The startup opens", "It makes its first sales", "It makes its first profit"]
    public static let stageMultiples: [Double] = [1.25, 1.4, 1.6]
    public static let perInvestorShare: Double = 0.20
    public static let minTicketShare: Double = 0.02
    public static let minAccountWeeks = 4
    public static let minFounderLevel = 2

    public struct FoundGate: Equatable, Sendable {
        public var allowed: Bool
        public var reasons: [String]
        public var lines: [String]
    }

    public static func foundGate(accountWeeks: Int, level: Int) -> FoundGate {
        var why: [String] = []
        if accountWeeks < minAccountWeeks { why.append(Refusal.newAccount(weeksLeft: minAccountWeeks - accountWeeks).message) }
        if level < minFounderLevel { why.append(Refusal.levelTooLow(needed: minFounderLevel, have: level).message) }
        let lines: [String] = [
            "A startup that raises money from other players can be opened only by an account at least \(minAccountWeeks) game weeks old and at player level \(minFounderLevel).",
            "If you open it, other players' money is held in escrow and released only when its milestones are reached; you cannot name the share price.",
            "If it fails, the money already released is lost."
        ]
        return FoundGate(allowed: why.isEmpty, reasons: why, lines: lines)
    }

    public static let lockWeeks = 12
    public static let bandLow: Double = 0.8
    public static let bandHigh: Double = 1.25
    public static let transferTax: Double = 0.02
    public static let viralInvestors = 5
    public static let viralDays = 7
    public static let stageDeadlineWeeks = 30
    public static let recentProfitWeeks = 13
    public static let planFactors: [Double] = [1.5, 2, 3]

    public struct Plan: Codable, Equatable, Sendable {
        public var cost: Double
        public var founderPutIn: Double
        public init(cost: Double, founderPutIn: Double) { self.cost = cost; self.founderPutIn = founderPutIn }
        public var valid: Bool { cost > 0 && founderPutIn >= cost * CrowdStartupRules.founderMinShare - 0.005 && founderPutIn <= cost }
        public var investorTarget: Double { max(0, cost - founderPutIn) }
    }

    public static func entryCost(scaledBy index: Double) -> Double { entryCostReference * index }

    public static func valuation(_ plan: Plan, stage: Int) -> Double { plan.cost * stageMultiples[min(max(0, stage), 2)] }
    public static func stageTarget(_ plan: Plan, stage: Int) -> Double { plan.investorTarget * stageShares[min(max(0, stage), 2)] }
    public static func pricePerPercent(_ plan: Plan, stage: Int) -> Double { valuation(plan, stage: stage) / 100 }
    public static func percent(for amount: Double, plan: Plan, stage: Int) -> Double { amount / pricePerPercent(plan, stage: stage) }
    public static func perInvestorCap(_ plan: Plan) -> Double { plan.investorTarget * perInvestorShare }
    public static func minTicket(_ plan: Plan, stage: Int) -> Double { stageTarget(plan, stage: stage) * minTicketShare }
    public static func maxInvestorPercent(_ plan: Plan) -> Double { (0..<3).reduce(0.0) { $0 + percent(for: stageTarget(plan, stage: $1), plan: plan, stage: $1) } }

    public enum Status: String, Codable, Sendable { case raising, live, failed, closed }

    public struct Investment: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var investorID: String
        public var linkKey: String
        public var stage: Int
        public var amount: Double
        public var percent: Double
        public var day: Int
        public var released = false
        public var refunded = false
        public init(id: String, investorID: String, linkKey: String, stage: Int, amount: Double, percent: Double, day: Int) {
            self.id = id; self.investorID = investorID; self.linkKey = linkKey; self.stage = stage; self.amount = amount; self.percent = percent; self.day = day
        }
    }

    public struct Startup: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var trade: String
        public var pitch: String
        public var founderID: String
        public var founderName: String
        public var founderLinkKey: String
        public var founderExits: Int
        public var founderFails: Int
        public var plan: Plan
        public var milestones: Int
        public var stageOpenedDay: Int
        public var status: Status
        public var createdDay: Int
        public var investments: [Investment]
        public var assets: Double
        public var weeklyProfit: [Double]
        public var companyID: Int?
        public init(id: String, name: String, trade: String, pitch: String = "", founderID: String, founderName: String, founderLinkKey: String, founderExits: Int = 0, founderFails: Int = 0,
                    plan: Plan, createdDay: Int, companyID: Int? = nil) {
            self.id = id; self.name = name; self.trade = trade; self.pitch = pitch; self.founderID = founderID; self.founderName = founderName
            self.founderLinkKey = founderLinkKey; self.founderExits = founderExits; self.founderFails = founderFails; self.plan = plan
            self.milestones = 0; self.stageOpenedDay = createdDay; self.status = .raising; self.createdDay = createdDay; self.investments = []
            self.assets = plan.founderPutIn; self.weeklyProfit = []; self.companyID = companyID
        }

        public var openStage: Int? { (status == .raising || status == .live) && milestones < 3 ? milestones : nil }
        public func raised(stage: Int) -> Double { investments.filter { $0.stage == stage && !$0.refunded }.reduce(0) { $0 + $1.amount } }
        public var raisedTotal: Double { investments.filter { !$0.refunded }.reduce(0) { $0 + $1.amount } }
        public func invested(by investorID: String) -> Double { investments.filter { $0.investorID == investorID && !$0.refunded }.reduce(0) { $0 + $1.amount } }
        public var soldPercent: Double { investments.filter { !$0.refunded }.reduce(0) { $0 + $1.percent } }
        public var escrowHeld: Double { investments.filter { !$0.released && !$0.refunded }.reduce(0) { $0 + $1.amount } }
        public var releasedTotal: Double { investments.filter { $0.released }.reduce(0) { $0 + $1.amount } }
        public var viral: Bool { CrowdStartupRules.isViral(self, today: investments.map { $0.day }.max() ?? createdDay) }
        public func viral(today: Int) -> Bool { CrowdStartupRules.isViral(self, today: today) }
        public var realValue: Double { CrowdStartupRules.realValue(self) }
    }

    public enum Refusal: Equatable, Sendable {
        case newAccount(weeksLeft: Int)
        case levelTooLow(needed: Int, have: Int)
        case linkedToFounder
        case notOpen
        case stageFull(room: Double)
        case investorCap(room: Double)
        case tooSmall(minimum: Double)
        case invalidAmount

        public var message: String {
            switch self {
            case .newAccount(let w): return "New accounts cannot invest or found for their first \(minAccountWeeks) weeks. \(w) to go."
            case .levelTooLow(let n, let h): return "Opening a startup for other players needs player level \(n). You are level \(h)."
            case .linkedToFounder: return "You cannot invest in a company linked to you."
            case .notOpen: return "This startup is not taking money now."
            case .stageFull(let r): return r > 0 ? "This stage has room for only \(Int(r.rounded())) more." : "This stage is full."
            case .investorCap(let r): return r > 0 ? "One investor may put in only so much per startup: \(Int(r.rounded())) more is the limit for you." : "You have reached the most one investor may put into this startup."
            case .tooSmall(let m): return "The smallest investment is \(Int(m.rounded()))."
            case .invalidAmount: return "Choose an amount."
            }
        }
    }

    public struct Quote: Equatable, Sendable {
        public var stage: Int
        public var amount: Double
        public var percent: Double
        public var pricePerPercent: Double
        public var lockedUntilDay: Int
        public var releasedAtMilestone: String
    }

    public enum InvestResult: Equatable, Sendable { case ok(Quote), refused(Refusal) }

    public static func investCheck(_ st: Startup, investorID: String, linkKeys: Set<String>, accountWeeks: Int, amount: Double, today: Int) -> InvestResult {
        if accountWeeks < minAccountWeeks { return .refused(.newAccount(weeksLeft: minAccountWeeks - accountWeeks)) }
        if investorID == st.founderID || linkKeys.contains(st.founderLinkKey) { return .refused(.linkedToFounder) }
        guard let stage = st.openStage else { return .refused(.notOpen) }
        guard amount > 0, amount.isFinite else { return .refused(.invalidAmount) }
        let room = stageTarget(st.plan, stage: stage) - st.raised(stage: stage)
        if amount > room + 0.005 { return .refused(.stageFull(room: max(0, room))) }
        let mine = perInvestorCap(st.plan) - st.invested(by: investorID)
        if amount > mine + 0.005 { return .refused(.investorCap(room: max(0, mine))) }
        let minimum = min(minTicket(st.plan, stage: stage), max(room, 0))
        if amount < minimum - 0.005 { return .refused(.tooSmall(minimum: minimum)) }
        return .ok(Quote(stage: stage, amount: amount, percent: percent(for: amount, plan: st.plan, stage: stage), pricePerPercent: pricePerPercent(st.plan, stage: stage),
                         lockedUntilDay: today + lockWeeks * 7, releasedAtMilestone: milestoneNames[stage]))
    }

    public static func reachMilestone(_ st: inout Startup, today: Int) -> Double {
        guard st.status != .failed, st.status != .closed, st.milestones < 3 else { return 0 }
        let stage = st.milestones
        var out = 0.0
        for i in st.investments.indices where st.investments[i].stage == stage && !st.investments[i].released && !st.investments[i].refunded {
            st.investments[i].released = true
            out += st.investments[i].amount
        }
        st.milestones += 1
        st.stageOpenedDay = today
        st.assets += out
        st.status = .live
        return out
    }

    public static func fail(_ st: inout Startup) -> [(investorID: String, amount: Double)] {
        var back: [(String, Double)] = []
        for i in st.investments.indices where !st.investments[i].released && !st.investments[i].refunded {
            st.investments[i].refunded = true
            back.append((st.investments[i].investorID, st.investments[i].amount))
        }
        st.status = .failed
        st.assets = 0
        return back
    }

    public static func expire(_ st: inout Startup, today: Int) -> [(investorID: String, amount: Double)] {
        guard st.openStage != nil, today - st.stageOpenedDay > stageDeadlineWeeks * 7 else { return [] }
        let back = fail(&st)
        st.status = .closed
        return back
    }

    public static func isViral(_ st: Startup, today: Int) -> Bool {
        let recent = st.investments.filter { today - $0.day < viralDays && $0.day <= today && !$0.refunded && $0.linkKey != st.founderLinkKey && $0.investorID != st.founderID }
        return Set(recent.map { $0.investorID }).count >= viralInvestors
    }

    public static func realValue(_ st: Startup) -> Double {
        guard st.status == .live || st.status == .raising else { return 0 }
        return max(0, st.assets) + max(0, st.weeklyProfit.suffix(recentProfitWeeks).reduce(0, +))
    }
    public static func fairPrice(_ st: Startup, percent: Double) -> Double { realValue(st) * percent / 100 }
    public static func band(_ st: Startup, percent: Double, rules: WorldRules = WorldRules.defaults) -> (low: Double, high: Double) {
        let f = fairPrice(st, percent: percent)
        return (f * rules.startupBand.lowerBound, f * rules.startupBand.upperBound)
    }

    public struct Holding: Codable, Equatable, Identifiable, Sendable {
        public var id: String { startupID + ":" + ownerID }
        public var startupID: String
        public var ownerID: String
        public var linkKey: String
        public var percent: Double
        public var paid: Double
        public var boughtDay: Int
        public init(startupID: String, ownerID: String, linkKey: String, percent: Double, paid: Double, boughtDay: Int) {
            self.startupID = startupID; self.ownerID = ownerID; self.linkKey = linkKey; self.percent = percent; self.paid = paid; self.boughtDay = boughtDay
        }
        public func lockedUntil() -> Int { boughtDay + CrowdStartupRules.lockWeeks * 7 }
    }

    public enum SaleRefusal: Equatable, Sendable {
        case locked(untilDay: Int)
        case outsideBand(low: Double, high: Double)
        case linkedParties
        case buyerNotAllowed(Refusal)
        case tooMany
        case notLive

        public var message: String {
            switch self {
            case .locked: return "These shares cannot be resold yet: they are locked for \(CrowdStartupRules.lockWeeks) game weeks after the purchase."
            case .outsideBand(let l, let h): return "The price must be between \(Int(l.rounded())) and \(Int(h.rounded())), around what the shares are really worth."
            case .linkedParties: return "Seller and buyer are linked accounts."
            case .buyerNotAllowed(let r): return r.message
            case .tooMany: return "You do not hold that many shares."
            case .notLive: return "This startup is not trading."
            }
        }
    }

    public struct SaleQuote: Equatable, Sendable {
        public var percent: Double
        public var price: Double
        public var transferTax: Double
        public var gain: Double
        public var gainsTax: Double
        public var sellerReceives: Double { price - gainsTax }
        public var buyerPays: Double { price + transferTax }
    }

    public enum SaleResult: Equatable, Sendable { case ok(SaleQuote), refused(SaleRefusal) }

    public static func saleCheck(_ st: Startup, holding: Holding, percent: Double, price: Double, buyerID: String, buyerLinkKeys: Set<String>, buyerAccountWeeks: Int,
                                 gainsRate: Double, today: Int, rules: WorldRules = WorldRules.defaults) -> SaleResult {
        guard st.status == .live || st.status == .raising else { return .refused(.notLive) }
        guard percent > 0, percent <= holding.percent + 1e-9 else { return .refused(.tooMany) }
        if today < holding.lockedUntil() { return .refused(.locked(untilDay: holding.lockedUntil())) }
        if buyerID == holding.ownerID || buyerLinkKeys.contains(holding.linkKey) { return .refused(.linkedParties) }
        if buyerAccountWeeks < minAccountWeeks { return .refused(.buyerNotAllowed(.newAccount(weeksLeft: minAccountWeeks - buyerAccountWeeks))) }
        if buyerID == st.founderID || buyerLinkKeys.contains(st.founderLinkKey) { return .refused(.buyerNotAllowed(.linkedToFounder)) }
        let b = band(st, percent: percent, rules: rules)
        guard price >= b.low - 0.005, price <= b.high + 0.005 else { return .refused(.outsideBand(low: b.low, high: b.high)) }
        let basis = holding.paid * percent / max(holding.percent, 1e-9)
        let gain = price - basis
        return .ok(SaleQuote(percent: percent, price: price, transferTax: price * transferTax, gain: gain, gainsTax: max(0, gain) * gainsRate))
    }

    public static func recordWords(exits: Int, fails: Int) -> String {
        switch (exits, fails) {
        case (0, 0): return "First startup"
        case (let e, 0): return e == 1 ? "One exit, no failures" : "\(e) exits, no failures"
        case (0, let f): return f == 1 ? "One failure, no exits" : "\(f) failures, no exits"
        case (let e, let f): return "\(e) exit\(e == 1 ? "" : "s"), \(f) failure\(f == 1 ? "" : "s")"
        }
    }
}
