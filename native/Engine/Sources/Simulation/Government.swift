import Foundation
import GameCore

// One country's government: administrators, treasury, printing, rates, price support, the audit log and the office of president.
// Elections are in Politics.swift. Every change a president or an election makes waits in `pending` until an administrator confirms it.

public struct GovPolicy: Codable, Equatable, Sendable {
    public static let transferRange = 0.0...0.05
    public static let gainsRange = 0.05...0.40
    /// The most a rate may move in one change, and the weeks between changes.
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
    /// One account may draw at most this share of the weekly budget, however many companies it owns.
    public static let accountShare = 0.25

    public var id: Int
    public var tradeID: String
    /// Share of the company's week of sales that the state adds.
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

    public var country: String
    public var admins: Set<String>
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

    public init(country: String, admins: Set<String>, startingSupply: Double) {
        self.country = country
        self.admins = admins
        supply = GovMoneySupply(base: startingSupply)
    }

    mutating func takeID() -> Int { defer { nextID += 1 }; return nextID }

    public func isAdmin(_ account: String) -> Bool { admins.contains(account) }
    public func isPresident(_ account: String, week: Int) -> Bool { office.map { $0.holder == account && week < $0.termEnd } ?? false }

    func requireAdmin(_ a: String) throws { guard isAdmin(a) else { throw GovError.notAdmin } }

    // MARK: Log and news

    mutating func log(_ actor: String, _ action: String, _ detail: String, week: Int) {
        audit.insert(GovAuditEntry(id: takeID(), week: week, actor: actor, action: action, detail: detail), at: 0)
        if audit.count > Self.logLimit { audit.removeLast(audit.count - Self.logLimit) }
    }

    mutating func publish(_ text: String, tone: String = "n", week: Int) {
        news.insert(GovNews(id: takeID(), week: week, text: text, tone: tone), at: 0)
        if news.count > 100 { news.removeLast(news.count - 100) }
    }

    /// Money coming in from a person or company (tax, fee, fine, donation). The caller has already taken it from them.
    mutating func receive(_ amount: Double, kind: String, ref: String, week: Int) {
        guard amount > 0 else { return }
        try? treasury.post(amount, kind: kind, ref: ref, week: week)
    }

    /// A refund or payout out of the treasury. The caller must credit the same amount to the person or company.
    mutating func payOut(_ amount: Double, kind: String, ref: String, week: Int) throws {
        try treasury.post(-abs(amount), kind: kind, ref: ref, week: week)
    }

    // MARK: Administrator: printing

    /// Prints money into the treasury. The entry is public and cannot be undone; prices follow later (`GovInflation`).
    @discardableResult
    public mutating func printMoney(admin: String, amount: Double, reason: String, week: Int) throws -> GovMint {
        try requireAdmin(admin)
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard why.count >= 3 else { throw GovError.badAmount("Give a reason.") }
        let a = govRound(amount)
        try supply.check(a, week: week)
        let m = GovMint(id: takeID(), week: week, amount: a, reason: String(why.prefix(200)), admin: admin)
        supply.append(m)
        try treasury.post(a, kind: "mint", ref: String(m.id), week: week)
        log(admin, "print", "\(a) printed: \(m.reason)", week: week)
        publish("The treasury has printed \(Int(a)) in new money: \(m.reason)", tone: "n", week: week)
        return m
    }

    public mutating func addAdmin(by admin: String, account: String, week: Int) throws {
        try requireAdmin(admin)
        admins.insert(account)
        log(admin, "admin_add", account, week: week)
    }

    /// An administrator stays; the last one cannot be removed.
    public mutating func removeAdmin(by admin: String, account: String, week: Int) throws {
        try requireAdmin(admin)
        guard admins.count > 1, admins.contains(account) else { throw GovError.wrongState }
        admins.remove(account)
        log(admin, "admin_remove", account, week: week)
    }

    // MARK: Donations

    /// A gift to the treasury. It buys nothing: no office, no support, no say. The record is public.
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

    // MARK: Rates (president proposes, administrator confirms)

    @discardableResult public mutating func proposePolicy(by account: String, transferTax: Double, gainsTax: Double, week: Int) throws -> Int {
        guard isPresident(account, week: week) else { throw GovError.notPresident }
        guard !pending.contains(where: { $0.kind == .policy && $0.status == .open }) else { throw GovError.alreadyPending }
        try Self.checkRates(from: policy, transferTax: transferTax, gainsTax: gainsTax, week: week)
        let p = GovPending(id: takeID(), kind: .policy, week: week, proposer: account,
                           summary: "Transfer tax \(pct(transferTax)), gains tax \(pct(gainsTax))", transferTax: transferTax, gainsTax: gainsTax)
        pending.insert(p, at: 0)
        log(account, "propose_policy", p.summary, week: week)
        return p.id
    }

    static func checkRates(from cur: GovPolicy, transferTax t: Double, gainsTax g: Double, week: Int) throws {
        guard GovPolicy.transferRange.contains(t), GovPolicy.gainsRange.contains(g) else { throw GovError.overLimit("A rate is outside its limits.") }
        guard abs(t - cur.transferTax) <= GovPolicy.step + 1e-9, abs(g - cur.gainsTax) <= GovPolicy.step + 1e-9 else {
            throw GovError.overLimit("A rate may move by one point at a time.")
        }
        if let last = cur.lastChangeWeek, week - last < GovPolicy.changeGapWeeks { throw GovError.tooSoon(weeksLeft: GovPolicy.changeGapWeeks - (week - last)) }
    }

    func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }

    // MARK: Price support

    /// Support for one trade: the state adds `percent` of a company's week of sales, up to a weekly budget. Admin confirms before it runs.
    @discardableResult public mutating func proposePriceSupport(by account: String, tradeID: String, percent: Double, weeklyBudget: Double, weeks: Int, week: Int) throws -> Int {
        guard isPresident(account, week: week) else { throw GovError.notPresident }
        try Self.checkSupport(percent: percent, budget: weeklyBudget, weeks: weeks, treasury: treasury.balance)
        guard !tradeID.isEmpty else { throw GovError.badAmount("Name the trade.") }
        guard supports.filter({ $0.status == .proposed || $0.status == .active }).count < GovPriceSupport.maxOpen,
              !supports.contains(where: { $0.tradeID == tradeID && ($0.status == .proposed || $0.status == .active) }) else { throw GovError.alreadyPending }
        let s = GovPriceSupport(id: takeID(), tradeID: tradeID, percent: percent, weeklyBudget: govRound(weeklyBudget), weeks: weeks, startWeek: week, status: .proposed, proposer: account)
        supports.append(s)
        let p = GovPending(id: takeID(), kind: .priceSupport, week: week, proposer: account,
                           summary: "Support for \(tradeID): \(pct(percent)) of weekly sales, budget \(Int(s.weeklyBudget)) a week for \(weeks) weeks", supportID: s.id)
        pending.insert(p, at: 0)
        log(account, "propose_support", p.summary, week: week)
        return p.id
    }

    static func checkSupport(percent: Double, budget: Double, weeks: Int, treasury: Double) throws {
        guard GovPriceSupport.percentRange.contains(percent) else { throw GovError.overLimit("Support is 1% to 10% of sales.") }
        guard (1...GovPriceSupport.maxWeeks).contains(weeks) else { throw GovError.overLimit("Support runs 1 to 8 weeks.") }
        guard budget > 0, budget <= treasury * GovPriceSupport.budgetShareOfTreasury else { throw GovError.unrealistic("The weekly budget may not exceed 5% of what the treasury holds.") }
    }

    /// What the state adds to one company's week. Zero when nothing applies. The caller credits the company the returned amount.
    public mutating func supportPayout(account: String, tradeID: String, weekRevenue: Double, week: Int) -> Double {
        guard weekRevenue > 0, !isAdmin(account), !isPresident(account, week: week) else { return 0 }
        guard let i = supports.firstIndex(where: { $0.status == .active && $0.tradeID == tradeID && week >= $0.startWeek && week < $0.endWeek }) else { return 0 }
        if supports[i].budgetWeek != week { supports[i].budgetWeek = week; supports[i].spentWeek = 0; supports[i].drawn = [:] }
        let s = supports[i]
        let accountRoom = s.weeklyBudget * GovPriceSupport.accountShare - (s.drawn[account] ?? 0)
        let amt = min(weekRevenue * s.percent, s.weeklyBudget - s.spentWeek, accountRoom, treasury.balance).rounded(.down)
        guard amt >= 1 else { return 0 }
        guard (try? payOut(amt, kind: "price_support", ref: String(s.id), week: week)) != nil else { return 0 }
        supports[i].spentWeek = govRound(s.spentWeek + amt)
        supports[i].spentTotal = govRound(s.spentTotal + amt)
        supports[i].drawn[account] = (s.drawn[account] ?? 0) + amt
        return amt
    }

    // MARK: Administrator decisions

    public mutating func confirm(admin: String, pendingID: Int, week: Int) throws {
        try requireAdmin(admin)
        guard let i = pending.firstIndex(where: { $0.id == pendingID && $0.status == .open }) else { throw GovError.notFound }
        let p = pending[i]
        switch p.kind {
        case .policy:
            guard let office, office.holder == p.proposer, week < office.termEnd else { throw GovError.notPresident }
            try Self.checkRates(from: policy, transferTax: p.transferTax ?? policy.transferTax, gainsTax: p.gainsTax ?? policy.gainsTax, week: week)
            policy.transferTax = p.transferTax ?? policy.transferTax
            policy.gainsTax = p.gainsTax ?? policy.gainsTax
            policy.lastChangeWeek = week
            markKept(policyKinds: true, week: week)
            publish("New rates: transfer tax \(pct(policy.transferTax)), gains tax \(pct(policy.gainsTax)).", week: week)
        case .priceSupport:
            guard let k = supports.firstIndex(where: { $0.id == p.supportID }), supports[k].status == .proposed else { throw GovError.notFound }
            guard let office, office.holder == p.proposer, week < office.termEnd else { throw GovError.notPresident }
            try Self.checkSupport(percent: supports[k].percent, budget: supports[k].weeklyBudget, weeks: supports[k].weeks, treasury: treasury.balance)
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

    /// Ends supports that have run their weeks. Called each week.
    mutating func expireSupports(week: Int) {
        for i in supports.indices where supports[i].status == .active && week >= supports[i].endWeek { supports[i].status = .ended }
    }
}
