import Foundation
import GameCore

public enum JVRules {

    public static let lockUpWeeks = 26
    public static let priceBand: ClosedRange<Double> = 0.7...1.5
    public static let quarterWeeks = 13
    public static let plannedNoticeWeeks = 2
    public static let urgentWindowWeeks = 1
    public static let maxPartners = 5
    public static let quorum = 0.5
    public static let inviteWeeks = 4
    public static let smallestStakePercent = 2.0
    public static let largestInvitePercent = 49.0
    public static let lowestSaleShare = 0.8

    public enum Choice: String, Codable, Sendable { case yes, no, abstain }

    public enum Outcome: String, Codable, Equatable, Sendable {
        case passed, failed, noQuorum
        case chairPassed, chairFailed
        case statusQuo
        public var passes: Bool { self == .passed || self == .chairPassed }
        public var word: String {
            switch self {
            case .passed: return "Passed"
            case .failed: return "Voted down"
            case .noQuorum: return "Too few votes, nothing changes"
            case .chairPassed: return "Tied, the chair decided for it"
            case .chairFailed: return "Tied, the chair decided against it"
            case .statusQuo: return "Tied, nothing changes"
            }
        }
    }

    public struct Tally: Equatable, Sendable {
        public var yes: Double
        public var no: Double
        public var abstain: Double
        public var total: Double
        public var castShare: Double { total > 0 ? (yes + no) / total : 0 }
        public var yesPercent: Double { total > 0 ? yes / total * 100 : 0 }
        public var noPercent: Double { total > 0 ? no / total * 100 : 0 }
    }

    public static func tally(shares: [String: Int], votes: [String: Choice]) -> Tally {
        var y = 0.0, n = 0.0, a = 0.0
        for (k, sh) in shares.sorted(by: { $0.key < $1.key }) {
            switch votes[k] ?? .abstain {
            case .yes: y += Double(sh)
            case .no: n += Double(sh)
            case .abstain: a += Double(sh)
            }
        }
        return Tally(yes: y, no: n, abstain: a, total: y + n + a)
    }

    public static func decide(_ t: Tally, chair: Choice?, chairUsedBefore: Bool) -> Outcome {
        guard t.total > 0, t.castShare >= quorum else { return .noQuorum }
        if t.yes > t.no { return .passed }
        if t.no > t.yes { return .failed }
        if chairUsedBefore { return .statusQuo }
        switch chair {
        case .yes?: return .chairPassed
        case .no?: return .chairFailed
        default: return .statusQuo
        }
    }

    public static func isOpen(week: Int, deadline: Int) -> Bool { week <= deadline }

    public static func deadline(planned: Bool, openedWeek: Int, meetingWeek: Int) -> Int { planned ? meetingWeek : openedWeek + urgentWindowWeeks }

    public static func nextPlannedWeek(after last: Int?, now: Int) -> Int {
        max(now + plannedNoticeWeeks, (last ?? now) + quarterWeeks)
    }

    public static func fairPrice(value: Double, pct: Double) -> Double {
        guard pct > 0, pct < 100 else { return 0 }
        return max(0, value) * pct / (100 - pct)
    }
    public static func priceProblem(price: Double, fair: Double, mock: Bool = false, rules: WorldRules = WorldRules.defaults) -> String? {
        let priceBand: ClosedRange<Double> = rules.ventureBand
        guard fair > 0 else { return "The company is worth nothing yet, so shares in it cannot be priced." }
        if price < fair * priceBand.lowerBound { return "That price is too low. A partner pays at least \(Int(priceBand.lowerBound * 100))% of what the shares are worth." }
        let top = mock ? min(1, priceBand.upperBound) : priceBand.upperBound
        if price > fair * top { return "That price is too high. A partner pays at most \(Int(top * 100))% of what the shares are worth." }
        return nil
    }
    public static func linkProblem(candidate: String, mine: Set<String>, partners: Set<String>) -> String? {
        if candidate.isEmpty { return "That player cannot be checked, so they cannot be invited." }
        if mine.contains(candidate) { return "That account is linked to yours, so it cannot be a partner." }
        if partners.contains(candidate) { return "That player is a partner already." }
        return nil
    }
    public static func lockUpEnd(joined: Int) -> Int { joined + lockUpWeeks }
    public static func isLocked(lockUntil: Int, week: Int) -> Bool { week < lockUntil }
    public static func stakeProblem(pct: Double, existingPartners: Int, ownerAfterPct: Double) -> String? {
        if existingPartners >= maxPartners { return "A joint venture has at most \(maxPartners) partners besides you." }
        if pct < smallestStakePercent { return "A partner holds at least \(Int(smallestStakePercent))%." }
        if pct > largestInvitePercent { return "A partner cannot be given more than \(Int(largestInvitePercent))%: you keep control of the company." }
        if ownerAfterPct < 1 { return "That would leave you with nothing." }
        return nil
    }

    public static func dissolvePayout(value: Double, shares: [String: Int]) -> [String: Double] {
        let total = shares.values.reduce(0, +)
        guard total > 0, value > 0 else { return shares.mapValues { _ in 0 } }
        var out: [String: Double] = [:]
        var paid = 0.0
        for (k, sh) in shares.sorted(by: { $0.key < $1.key }) {
            let part = (value * Double(sh) / Double(total) * 100).rounded(.down) / 100
            out[k] = part; paid += part
        }
        if let big = shares.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key { out[big, default: 0] += ((value - paid) * 100).rounded() / 100 }
        return out
    }

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case dividend, price, hire, sell, partner, dissolve
        public var title: String {
            switch self {
            case .dividend: return "Pay a dividend"
            case .price: return "Change prices"
            case .hire: return "Hire a manager"
            case .sell: return "Sell the company"
            case .partner: return "Bring in a new partner"
            case .dissolve: return "Dissolve the joint venture"
            }
        }
        public var takesMoneyOut: Bool { self == .dividend || self == .dissolve }
    }

    public static func effect(_ kind: Kind, amount: Double = 0, steps: Int = 0, name: String = "", pct: Double = 0, price: Double = 0, money: (Double) -> String) -> String {
        switch kind {
        case .dividend: return "\(money(amount)) is paid out to all owners by their shares. The company keeps two weeks of costs in the bank."
        case .price: return steps < 0 ? "Prices go down one step: more customers, less money on each sale." : "Prices go up one step: less volume, more money on each sale."
        case .hire: return "A manager is hired at the going rate and runs the company day to day. Their pay comes out of the company."
        case .sell: return "The company is listed with a broker (4% fee). Offers come in over the next weeks; you answer them for all owners, and none below \(Int(lowestSaleShare * 100))% of its value is accepted. When it sells, every owner is paid by their shares."
        case .partner: return "\(name) is invited to join for \(Int(pct.rounded()))% of the company, paying \(money(price)). New shares are made, so every owner's share becomes a little smaller."
        case .dissolve: return "The company is closed. Its real value is paid out to the owners by their shares. Nobody gets a premium."
        }
    }

    public static func mockChoice(_ kind: Kind, profitable: Bool, cashTight: Bool, seed: String) -> Choice {
        let roll = HashedRandom.first("jvvote:" + seed)
        var yes: Bool
        switch kind {
        case .dividend: yes = profitable && !cashTight
        case .price: yes = profitable
        case .hire: yes = profitable
        case .sell: yes = !profitable
        case .partner: yes = profitable
        case .dissolve: yes = !profitable && cashTight
        }
        if roll < 0.12 { return .abstain }
        if roll < 0.2 { yes.toggle() }
        return yes ? .yes : .no
    }
    public static func mockVoteWeek(opened: Int, deadline: Int, seed: String) -> Int {
        let span = max(1, deadline - opened)
        let roll = HashedRandom.first("jvwhen:" + seed)
        if roll > 0.9 { return deadline + 1 }
        return opened + Int(roll / 0.9 * Double(span))
    }
}
