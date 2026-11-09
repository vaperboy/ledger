import Foundation
import GameCore

/// Pure rules of a joint venture: a company several players own by shares. Nothing here reads or writes the game; `JointVenture` applies them.
/// Decisions go by shares among the votes cast; at least half of all shares must cast a for/against vote, a vote not cast by the deadline is an
/// abstention, a tie is broken once by the chair and otherwise the status quo stands.
public enum JVRules {
    // MARK: Numbers

    /// A new partner cannot sell or leave for this many weeks (same as a startup investor's lock-up).
    public static let lockUpWeeks = 26
    /// A new partner pays between these multiples of the fair price of the shares they get.
    public static let priceBand: ClosedRange<Double> = 0.7...1.5
    /// Planned meetings are quarterly; the agenda goes out this many weeks ahead, which is also the voting window.
    public static let quarterWeeks = 13
    public static let plannedNoticeWeeks = 2
    public static let urgentWindowWeeks = 1
    /// Most partners besides the owner, and the share of all shares that must cast a for/against vote.
    public static let maxPartners = 5
    public static let quorum = 0.5
    /// An invitation lapses after this many weeks.
    public static let inviteWeeks = 4
    /// A partner always keeps at least this share of the votes after a new issue is made to somebody else (no one is diluted to nothing).
    public static let smallestStakePercent = 2.0
    public static let largestInvitePercent = 49.0

    // MARK: Votes

    public enum Choice: String, Codable, Sendable { case yes, no, abstain }

    public enum Outcome: String, Codable, Equatable, Sendable {
        case passed, failed, noQuorum
        /// A tie the chair broke by voting for or against.
        case chairPassed, chairFailed
        /// A tie that stays as it was: the chair had already broken one on this item, or did not vote either way.
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
        /// Abstained, plus every share that did not vote by the deadline.
        public var abstain: Double
        public var total: Double
        public var castShare: Double { total > 0 ? (yes + no) / total : 0 }
        public var yesPercent: Double { total > 0 ? yes / total * 100 : 0 }
        public var noPercent: Double { total > 0 ? no / total * 100 : 0 }
    }

    /// Add up share counts by choice. `votes` maps a holder to the choice they cast; a holder missing from it abstains.
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

    /// The result of a count. `chair` is the chair's own choice; `chairUsedBefore` is true when the chair already broke a tie on this item.
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

    /// The vote is open on the deadline week itself and counted the week after.
    public static func isOpen(week: Int, deadline: Int) -> Bool { week <= deadline }

    /// The week the vote on a meeting closes.
    public static func deadline(planned: Bool, openedWeek: Int, meetingWeek: Int) -> Int { planned ? meetingWeek : openedWeek + urgentWindowWeeks }

    /// The next planned meeting date after `week`: the week after the last one plus a quarter, never sooner than the notice period.
    public static func nextPlannedWeek(after last: Int?, now: Int) -> Int {
        max(now + plannedNoticeWeeks, (last ?? now) + quarterWeeks)
    }

    // MARK: Guard rails

    /// What a share of `pct` percent (of the company after the issue) is worth at `value`.
    public static func fairPrice(value: Double, pct: Double) -> Double {
        guard pct > 0, pct < 100 else { return 0 }
        return max(0, value) * pct / (100 - pct)
    }
    public static func priceProblem(price: Double, fair: Double) -> String? {
        guard fair > 0 else { return "The company is worth nothing yet, so shares in it cannot be priced." }
        if price < fair * priceBand.lowerBound { return "That price is too low. A partner pays at least \(Int(priceBand.lowerBound * 100))% of what the shares are worth." }
        if price > fair * priceBand.upperBound { return "That price is too high. A partner pays at most \(Int(priceBand.upperBound * 100))% of what the shares are worth." }
        return nil
    }
    /// Players on linked accounts (the same owner) cannot be partners of each other: a joint venture would be a way to move money between your own accounts.
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

    /// Dissolving: everyone is paid by shares from the real value of the company, nothing more. The last cent of rounding goes to the biggest holder.
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

    // MARK: Agenda

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case dividend, price, hire, sell, partner, capital, dissolve
        public var title: String {
            switch self {
            case .dividend: return "Pay a dividend"
            case .price: return "Change prices"
            case .hire: return "Hire a manager"
            case .sell: return "Sell the company"
            case .partner: return "Bring in a new partner"
            case .capital: return "Call for capital"
            case .dissolve: return "Dissolve the joint venture"
            }
        }
        /// Money leaves the company for its owners.
        public var takesMoneyOut: Bool { self == .dividend || self == .dissolve }
    }

    /// What happens if the item passes, in plain words.
    public static func effect(_ kind: Kind, amount: Double = 0, steps: Int = 0, name: String = "", pct: Double = 0, price: Double = 0, money: (Double) -> String) -> String {
        switch kind {
        case .dividend: return "\(money(amount)) is paid out to all owners by their shares. The company keeps two weeks of costs in the bank."
        case .price: return steps < 0 ? "Prices go down one step: more customers, less money on each sale." : "Prices go up one step: less volume, more money on each sale."
        case .hire: return "A manager is hired at the going rate and runs the company day to day. Their pay comes out of the company."
        case .sell: return "The company is listed with a broker. Offers come in; when it sells, every owner is paid by their shares."
        case .partner: return "\(name) is invited to join for \(Int(pct.rounded()))% of the company, paying \(money(price)). New shares are made, so every owner's share becomes a little smaller."
        case .capital: return "Each owner puts in their share of \(money(amount)), by their shares. Nobody's share changes."
        case .dissolve: return "The company is closed. Its real value is paid out to the owners by their shares. Nobody gets a premium."
        }
    }

    // MARK: Mock partners

    /// How a sample partner leans on an item: from what the company is doing and what the item asks of them. Deterministic for a seed.
    public static func mockChoice(_ kind: Kind, profitable: Bool, cashTight: Bool, seed: String) -> Choice {
        let roll = HashedRandom.first("jvvote:" + seed)
        var yes: Bool
        switch kind {
        case .dividend: yes = profitable && !cashTight
        case .price: yes = profitable
        case .hire: yes = profitable
        case .sell: yes = !profitable
        case .partner: yes = profitable
        case .capital: yes = cashTight
        case .dissolve: yes = !profitable && cashTight
        }
        if roll < 0.12 { return .abstain }
        if roll < 0.2 { yes.toggle() }
        return yes ? .yes : .no
    }
    /// The week a sample partner casts their vote: inside the window, and now and then too late (which counts as an abstention).
    public static func mockVoteWeek(opened: Int, deadline: Int, seed: String) -> Int {
        let span = max(1, deadline - opened)
        let roll = HashedRandom.first("jvwhen:" + seed)
        if roll > 0.9 { return deadline + 1 }
        return opened + Int(roll / 0.9 * Double(span))
    }
}
