import Foundation
import GameCore

public struct GovPolicy: Codable, Equatable, Sendable {
    public static let transferRange = 0.0...0.05
    public static let gainsRange = 0.05...0.40
    public static let step = 0.01
    public static let changeGapWeeks = 7

    public var transferTax = 0.02
    public var gainsTax = 0.20
    public var lastChangeWeek: Int?
    public init() {}
}

public struct GovPriceSupport: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable { case proposed, active, ended, rejected }
    public static let percentRange = 0.01...0.10
    public static let maxWeeks = 8
    public static let budgetShareOfTreasury = 0.05
    public static let maxOpen = 2
    public static let accountShare = 0.25

    public var id: Int
    public var tradeID: String
    public var percent: Double
    public var weeklyBudget: Double
    public var weeks: Int
    public var startWeek: Int
    public var status: Status
    public var proposer: String
    public var spentTotal: Double = 0
    public var budgetWeek: Int = -1
    public var spentWeek: Double = 0
    public var drawn: [String: Double] = [:]
    public var endWeek: Int { startWeek + weeks }
}

public struct GovPending: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case policy, priceSupport, promises, electionResult }
    public enum Status: String, Codable, Sendable { case open, confirmed, rejected }

    public var id: Int
    public var kind: Kind
    public var week: Int
    public var proposer: String
    public var summary: String
    public var transferTax: Double?
    public var gainsTax: Double?
    public var supportID: Int?
    public var electionID: Int?
    public var status: Status = .open
    public var decidedBy: String?
    public var decidedWeek: Int?
}

public struct GovOffice: Codable, Equatable, Sendable {
    public var holder: String
    public var name: String
    public var termStart: Int
    public var termEnd: Int
    public var promises: [CampaignPromise]
}

public struct Government: Codable, Equatable, Sendable {
    public static let termWeeks = 12
    public static let logLimit = 2_000

    public var admins: Set<String>
    public var activeRules: WorldRules?
    var rules: WorldRules { activeRules ?? WorldRules.defaults }
    public internal(set) var treasury = GovTreasury()
    public internal(set) var supply: GovMoneySupply
    public internal(set) var donations: [GovDonation] = []
    public internal(set) var policy = GovPolicy()
    public internal(set) var supports: [GovPriceSupport] = []
    public internal(set) var pending: [GovPending] = []
    public internal(set) var audit: [GovAuditEntry] = []
    public internal(set) var news: [GovNews] = []
    public internal(set) var office: GovOffice?
    public internal(set) var election: Election?
    public internal(set) var lastCycleClosedWeek: Int?
    var nextID = 1

    public init(admins: Set<String>, startingSupply: Double) {
        self.admins = admins
        supply = GovMoneySupply(base: startingSupply)
    }

    mutating func takeID() -> Int { defer { nextID += 1 }; return nextID }

    public func isAdmin(_ account: String) -> Bool { admins.contains(account) }
    public func isPresident(_ account: String, week: Int) -> Bool { office.map { $0.holder == account && week < $0.termEnd } ?? false }

    func requireAdmin(_ a: String) throws { guard isAdmin(a) else { throw GovError.notAdmin } }

    mutating func log(_ actor: String, _ action: String, _ detail: String, week: Int) {
        audit.insert(GovAuditEntry(id: takeID(), week: week, actor: actor, action: action, detail: detail), at: 0)
        if audit.count > Self.logLimit { audit.removeLast(audit.count - Self.logLimit) }
    }

    mutating func publish(_ text: String, tone: String = "n", week: Int) {
        news.insert(GovNews(id: takeID(), week: week, text: text, tone: tone), at: 0)
        if news.count > 100 { news.removeLast(news.count - 100) }
    }

    mutating func receive(_ amount: Double, kind: String, ref: String, week: Int) {
        guard amount > 0 else { return }
        try? treasury.post(amount, kind: kind, ref: ref, week: week)
    }

    mutating func payOut(_ amount: Double, kind: String, ref: String, week: Int) throws {
        try treasury.post(-abs(amount), kind: kind, ref: ref, week: week)
    }

    @discardableResult
    public mutating func printMoney(admin: String, amount: Double, reason: String, week: Int) throws -> GovMint {
        try requireAdmin(admin)
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard why.count >= 3 else { throw GovError.badAmount("Give a reason.") }
        let a = govRound(amount)
        try supply.check(a, week: week, rules: rules)
        let m = GovMint(id: takeID(), week: week, amount: a, reason: String(why.prefix(200)), admin: admin)
        supply.append(m)
        try treasury.post(a, kind: "mint", ref: String(m.id), week: week)
        log(admin, "print", "\(a) of new money added: \(m.reason)", week: week)
        publish("New money in circulation, \(Int(a)), will push up inflation: \(m.reason)", tone: "n", week: week)
        return m
    }

    public mutating func addAdmin(by admin: String, account: String, week: Int) throws {
        try requireAdmin(admin)
        admins.insert(account)
        log(admin, "admin_add", account, week: week)
    }

    public mutating func removeAdmin(by admin: String, account: String, week: Int) throws {
        try requireAdmin(admin)
        guard admins.count > 1, admins.contains(account) else { throw GovError.wrongState }
        admins.remove(account)
        log(admin, "admin_remove", account, week: week)
    }

    @discardableResult
    public mutating func donate(account: String, name: String, amount: Double, week: Int) throws -> GovDonation {
        let a = govRound(amount)
        guard a >= 1, a.isFinite else { throw GovError.badAmount("A donation must be at least 1.") }
        let d = GovDonation(id: takeID(), week: week, account: account, name: name, amount: a)
        donations.insert(d, at: 0)
        receive(a, kind: "donation", ref: String(d.id), week: week)
        log(account, "donation", "\(a)", week: week)
        return d
    }

    @discardableResult public mutating func proposePolicy(by account: String, transferTax: Double, gainsTax: Double, week: Int) throws -> Int {
        guard isPresident(account, week: week) else { throw GovError.notPresident }
        guard !pending.contains(where: { $0.kind == .policy && $0.status == .open }) else { throw GovError.alreadyPending }
        try Self.checkRates(from: policy, transferTax: transferTax, gainsTax: gainsTax, week: week, rules: rules)
        let p = GovPending(id: takeID(), kind: .policy, week: week, proposer: account,
                           summary: "Transfer tax \(pct(transferTax)), gains tax \(pct(gainsTax))", transferTax: transferTax, gainsTax: gainsTax)
        pending.insert(p, at: 0)
        log(account, "propose_policy", p.summary, week: week)
        return p.id
    }

    static func checkRates(from cur: GovPolicy, transferTax t: Double, gainsTax g: Double, week: Int, rules: WorldRules = WorldRules.defaults) throws {
        guard rules.transferTaxRange.contains(t), rules.gainsTaxRange.contains(g) else { throw GovError.overLimit("A rate is outside its limits.") }
        guard abs(t - cur.transferTax) <= rules.taxStep + 1e-9, abs(g - cur.gainsTax) <= rules.taxStep + 1e-9 else {
            throw GovError.overLimit("A rate may move by one point at a time.")
        }
        if let last = cur.lastChangeWeek, week - last < rules.taxGapWeeks { throw GovError.tooSoon(weeksLeft: rules.taxGapWeeks - (week - last)) }
    }

    func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }

    @discardableResult public mutating func proposePriceSupport(by account: String, tradeID: String, percent: Double, weeklyBudget: Double, weeks: Int, week: Int) throws -> Int {
        guard isPresident(account, week: week) else { throw GovError.notPresident }
        try Self.checkSupport(percent: percent, budget: weeklyBudget, weeks: weeks, treasury: treasury.balance, rules: rules)
        guard !tradeID.isEmpty else { throw GovError.badAmount("Name the trade.") }
        guard supports.filter({ $0.status == .proposed || $0.status == .active }).count < rules.supportMaxOpen,
              !supports.contains(where: { $0.tradeID == tradeID && ($0.status == .proposed || $0.status == .active) }) else { throw GovError.alreadyPending }
        let s = GovPriceSupport(id: takeID(), tradeID: tradeID, percent: percent, weeklyBudget: govRound(weeklyBudget), weeks: weeks, startWeek: week, status: .proposed, proposer: account)
        supports.append(s)
        let p = GovPending(id: takeID(), kind: .priceSupport, week: week, proposer: account,
                           summary: "Support for \(tradeID): \(pct(percent)) of weekly sales, budget \(Int(s.weeklyBudget)) a week for \(weeks) weeks", supportID: s.id)
        pending.insert(p, at: 0)
        log(account, "propose_support", p.summary, week: week)
        return p.id
    }

    static func checkSupport(percent: Double, budget: Double, weeks: Int, treasury: Double, rules: WorldRules = WorldRules.defaults) throws {
        guard rules.supportPercentRange.contains(percent) else { throw GovError.overLimit("Support is 1% to \(Int((rules.supportPercentRange.upperBound * 100).rounded()))% of sales.") }
        guard (1...rules.supportWeeksMax).contains(weeks) else { throw GovError.overLimit("Support runs 1 to \(rules.supportWeeksMax) weeks.") }
        guard budget > 0, budget <= treasury * rules.supportBudgetShare else {
            throw GovError.unrealistic("The weekly budget may not exceed \(Int((rules.supportBudgetShare * 100).rounded()))% of what the treasury holds.")
        }
    }

    public mutating func supportPayout(account: String, tradeID: String, weekRevenue: Double, week: Int) -> Double {
        guard weekRevenue > 0, !isAdmin(account), !isPresident(account, week: week) else { return 0 }
        guard let i = supports.firstIndex(where: { $0.status == .active && $0.tradeID == tradeID && week >= $0.startWeek && week < $0.endWeek }) else { return 0 }
        if supports[i].budgetWeek != week { supports[i].budgetWeek = week; supports[i].spentWeek = 0; supports[i].drawn = [:] }
        let s = supports[i]
        let accountRoom = s.weeklyBudget * rules.supportAccountShare - (s.drawn[account] ?? 0)
        let amt = min(weekRevenue * s.percent, s.weeklyBudget - s.spentWeek, accountRoom, treasury.balance).rounded(.down)
        guard amt >= 1 else { return 0 }
        guard (try? payOut(amt, kind: "price_support", ref: String(s.id), week: week)) != nil else { return 0 }
        supports[i].spentWeek = govRound(s.spentWeek + amt)
        supports[i].spentTotal = govRound(s.spentTotal + amt)
        supports[i].drawn[account] = (s.drawn[account] ?? 0) + amt
        return amt
    }

    public mutating func confirm(admin: String, pendingID: Int, week: Int) throws {
        try requireAdmin(admin)
        guard let i = pending.firstIndex(where: { $0.id == pendingID && $0.status == .open }) else { throw GovError.notFound }
        let p = pending[i]
        switch p.kind {
        case .policy:
            guard let office, office.holder == p.proposer, week < office.termEnd else { throw GovError.notPresident }
            try Self.checkRates(from: policy, transferTax: p.transferTax ?? policy.transferTax, gainsTax: p.gainsTax ?? policy.gainsTax, week: week, rules: rules)
            policy.transferTax = p.transferTax ?? policy.transferTax
            policy.gainsTax = p.gainsTax ?? policy.gainsTax
            policy.lastChangeWeek = week
            markKept(policyKinds: true, week: week)
            publish("New rates: transfer tax \(pct(policy.transferTax)), gains tax \(pct(policy.gainsTax)).", week: week)
        case .priceSupport:
            guard let k = supports.firstIndex(where: { $0.id == p.supportID }), supports[k].status == .proposed else { throw GovError.notFound }
            guard let office, office.holder == p.proposer, week < office.termEnd else { throw GovError.notPresident }
            try Self.checkSupport(percent: supports[k].percent, budget: supports[k].weeklyBudget, weeks: supports[k].weeks, treasury: treasury.balance, rules: rules)
            supports[k].status = .active
            supports[k].startWeek = week
            markKept(support: supports[k], week: week)
            publish("Price support starts for \(supports[k].tradeID).", week: week)
        case .promises:
            try approvePromises(p, week: week)
        case .electionResult:
            try installWinner(p, week: week)
        }
        pending[i].status = .confirmed
        pending[i].decidedBy = admin
        pending[i].decidedWeek = week
        log(admin, "confirm", p.summary, week: week)
    }

    public mutating func reject(admin: String, pendingID: Int, week: Int) throws {
        try requireAdmin(admin)
        guard let i = pending.firstIndex(where: { $0.id == pendingID && $0.status == .open }) else { throw GovError.notFound }
        let p = pending[i]
        if p.kind == .priceSupport, let k = supports.firstIndex(where: { $0.id == p.supportID }) { supports[k].status = .rejected }
        if p.kind == .electionResult { rejectResult(p, week: week) }
        if p.kind == .promises { stripPromises(p) }
        pending[i].status = .rejected
        pending[i].decidedBy = admin
        pending[i].decidedWeek = week
        log(admin, "reject", p.summary, week: week)
    }

    public var openPending: [GovPending] { pending.filter { $0.status == .open } }

    mutating func expireSupports(week: Int) {
        for i in supports.indices where supports[i].status == .active && week >= supports[i].endWeek { supports[i].status = .ended }
    }
}
