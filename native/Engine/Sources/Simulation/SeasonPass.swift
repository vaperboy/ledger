import Foundation
import GameCore

public struct SeasonPass: Codable, Equatable, Sendable {

    public static let seasonDays = 56
    public static let tierCount = 30
    public static let xpPerTier = 150
    public static let dailyXPCap = 100
    public static let cashStreakWeeks = 4

    public enum Source: String, Codable, Sendable, CaseIterable {
        case weekReport, dailyGoal, cashStreak, loanRepaid, profitMonth, milestone
        public var xp: Int {
            switch self {
            case .weekReport: return 20
            case .dailyGoal: return 30
            case .cashStreak: return 25
            case .loanRepaid: return 40
            case .profitMonth: return 30
            case .milestone: return 50
            }
        }
        public var title: String {
            switch self {
            case .weekReport: return "Finish a week report"
            case .dailyGoal: return "Complete the daily goal"
            case .cashStreak: return "Keep cash positive for \(SeasonPass.cashStreakWeeks) weeks"
            case .loanRepaid: return "Repay a loan"
            case .profitMonth: return "Close a month in profit"
            case .milestone: return "Reach a career or country milestone"
            }
        }
    }

    public struct Snapshot: Codable, Equatable, Sendable {
        public static let unknownMonths = -1
        public var seed: Int, week: Int, cash: Double, profitMonths: Int, loans: Int, goals: Int
        public var dailyDone: String
        public init(seed: Int, week: Int, cash: Double, profitMonths: Int, loans: Int, goals: Int, dailyDone: String) {
            self.seed = seed; self.week = week; self.cash = cash; self.profitMonths = profitMonths; self.loans = loans; self.goals = goals; self.dailyDone = dailyDone
        }

        enum CodingKeys: String, CodingKey { case seed, week, cash, profitMonths, loans, goals, dailyDone }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            seed = try c.decode(Int.self, forKey: .seed)
            week = try c.decode(Int.self, forKey: .week)
            cash = try c.decode(Double.self, forKey: .cash)
            profitMonths = try c.decodeIfPresent(Int.self, forKey: .profitMonths) ?? Self.unknownMonths
            loans = try c.decode(Int.self, forKey: .loans)
            goals = try c.decode(Int.self, forKey: .goals)
            dailyDone = try c.decode(String.self, forKey: .dailyDone)
        }
    }

    static func profitMonths(_ s: GameState) -> Int {
        var byMonth: [Int: Double] = [:]
        for c in s.companies where c.type != "hold" {
            for m in c.monthlyHistory { byMonth[m.monthIndex, default: 0] += m.profit }
        }
        return byMonth.values.filter { $0 > 0 }.count
    }

    public static func snapshot(_ s: GameState) -> Snapshot {
        let daily: String = (s.rest["dy59"]?["got"].int ?? 0) != 0 ? (s.rest["dy59"]?["d"].string ?? "") : ""
        return Snapshot(seed: s.seed, week: s.week, cash: s.cash, profitMonths: profitMonths(s), loans: s.loans.count, goals: Career.goalsDone(s), dailyDone: daily)
    }

    public var firstDay: Int
    public var season: Int
    public var xp: Int
    public var claimed: Set<String>
    public var owned: Set<String>
    public var equipped: [String: String]
    public var xpDay: Int
    public var xpToday: Int
    public var cashStreak: Int
    public var baseline: Snapshot?
    public var missedFree: Int?

    public init(today: Int) {
        firstDay = today; season = 0; xp = 0; claimed = []; owned = []; equipped = [:]
        xpDay = today; xpToday = 0; cashStreak = 0; baseline = nil
    }

    public static func seasonIndex(firstDay: Int, today: Int) -> Int { max(0, (today - firstDay) / seasonDays) }
    public var startDay: Int { firstDay + season * Self.seasonDays }
    public var endDay: Int { startDay + Self.seasonDays }
    public func daysLeft(today: Int) -> Int { max(0, endDay - today) }
    public var seasonNumber: Int { season + 1 }

    @discardableResult
    public mutating func rollover(today: Int) -> Bool {
        let idx: Int = Self.seasonIndex(firstDay: firstDay, today: today)
        guard idx > season else { return false }
        missedFree = unclaimedFree
        season = idx; xp = 0; claimed = []; xpDay = today; xpToday = 0; cashStreak = 0
        return true
    }

    public var unclaimedFree: Int {
        (1...Self.tierCount).filter { SeasonRewards.reward(.free, tier: $0) != nil && $0 <= tier && !isClaimed(.free, tier: $0) }.count
    }

    public func endingNote(today: Int, isPlus: Bool) -> String? {
        let left: Int = daysLeft(today: today)
        guard left <= 7 else { return nil }
        let open: Int = claimableCount(isPlus: isPlus)
        let when: String = left <= 1 ? "tomorrow" : "in \(left) days"
        if open > 0 { return "\(open) \(open == 1 ? "reward is" : "rewards are") waiting. The season ends \(when), and what you have not claimed is lost." }
        if isComplete { return nil }
        return "The season ends \(when). You are at tier \(tier) of \(Self.tierCount); the next tier is \(xpToNextTier) XP away."
    }

    public var xpToNextTier: Int { isComplete ? 0 : Self.xpPerTier - xpIntoTier }

    public var missedNote: String? {
        guard let n = missedFree, n > 0 else { return nil }
        return "Last season ended with \(n) free \(n == 1 ? "reward" : "rewards") unclaimed. Claim before the season ends to keep them."
    }

    public static func tier(forXP xp: Int) -> Int { min(tierCount, max(0, xp) / xpPerTier) }
    public var tier: Int { Self.tier(forXP: xp) }
    public var isComplete: Bool { tier >= Self.tierCount }
    public var xpIntoTier: Int { isComplete ? 0 : xp % Self.xpPerTier }
    public var tierProgress: Double { isComplete ? 1 : Double(xpIntoTier) / Double(Self.xpPerTier) }
    public func xpLeftToday(today: Int) -> Int { xpDay == today ? max(0, Self.dailyXPCap - xpToday) : Self.dailyXPCap }

    public var progressText: String {
        if isComplete { return "Season complete: all \(Self.tierCount) tiers reached" }
        return "Tier \(tier) of \(Self.tierCount). \(xpIntoTier) of \(Self.xpPerTier) XP to tier \(tier + 1)"
    }

    @discardableResult
    public mutating func award(_ source: Source, today: Int, count: Int = 1) -> Int {
        if xpDay != today { xpDay = today; xpToday = 0 }
        let room: Int = max(0, Self.dailyXPCap - xpToday)
        let top: Int = max(0, Self.tierCount * Self.xpPerTier - xp)
        let granted: Int = min(source.xp * max(0, count), room, top)
        xp += granted; xpToday += granted
        return granted
    }

    @discardableResult
    public mutating func addBonus(_ amount: Int) -> Int {
        let top: Int = max(0, Self.tierCount * Self.xpPerTier - xp)
        let granted: Int = min(max(0, amount), top)
        xp += granted
        return granted
    }

    public static let adBonusXP = 40

    @discardableResult
    public mutating func observe(_ now: Snapshot, today: Int) -> Int {
        rollover(today: today)
        defer { baseline = now }
        guard let b = baseline, b.seed == now.seed, now.week >= b.week else { cashStreak = 0; return 0 }
        var total = 0
        if now.week > b.week {
            total += award(.weekReport, today: today)
            if now.cash > 0 {
                let before: Int = cashStreak
                cashStreak += now.week - b.week
                let hits: Int = cashStreak / Self.cashStreakWeeks - before / Self.cashStreakWeeks
                if hits > 0 { total += award(.cashStreak, today: today, count: hits) }
            } else { cashStreak = 0 }
        }
        if b.profitMonths >= 0, now.profitMonths > b.profitMonths { total += award(.profitMonth, today: today, count: now.profitMonths - b.profitMonths) }
        if now.loans < b.loans { total += award(.loanRepaid, today: today, count: b.loans - now.loans) }
        if now.goals > b.goals { total += award(.milestone, today: today, count: now.goals - b.goals) }
        if !now.dailyDone.isEmpty && now.dailyDone != b.dailyDone { total += award(.dailyGoal, today: today) }
        return total
    }

    public enum Track: String, Codable, Sendable { case free = "f", premium = "p" }

    public enum ClaimResult: Equatable, Sendable {
        case claimed(SeasonReward)
        case alreadyClaimed
        case tierNotReached
        case needsPlus
        case noReward
    }

    static func key(_ track: Track, _ tier: Int) -> String { track.rawValue + String(tier) }
    public func isClaimed(_ track: Track, tier t: Int) -> Bool { claimed.contains(Self.key(track, t)) }

    public func canClaim(_ track: Track, tier t: Int, isPlus: Bool) -> Bool {
        guard SeasonRewards.reward(track, tier: t) != nil, t <= tier, !isClaimed(track, tier: t) else { return false }
        return track == .free || isPlus
    }

    public mutating func claim(_ track: Track, tier t: Int, isPlus: Bool) -> ClaimResult {
        guard let r = SeasonRewards.reward(track, tier: t) else { return .noReward }
        if isClaimed(track, tier: t) { return .alreadyClaimed }
        if t > tier { return .tierNotReached }
        if track == .premium && !isPlus { return .needsPlus }
        claimed.insert(Self.key(track, t)); owned.insert(r.id)
        if equipped[r.kind.rawValue] == nil && r.kind.isEquippable { equipped[r.kind.rawValue] = r.id }
        return .claimed(r)
    }

    public mutating func claimAll(isPlus: Bool) -> [SeasonReward] {
        var got: [SeasonReward] = []
        for t in 1...Self.tierCount {
            for track in [Track.free, .premium] {
                if case .claimed(let r) = claim(track, tier: t, isPlus: isPlus) { got.append(r) }
            }
        }
        return got
    }

    public func claimableCount(isPlus: Bool) -> Int {
        (1...Self.tierCount).reduce(0) { n, t in n + [Track.free, .premium].filter { canClaim($0, tier: t, isPlus: isPlus) }.count }
    }

    public mutating func equip(_ id: String) {
        guard owned.contains(id), let r = SeasonRewards.item(id), r.kind.isEquippable else { return }
        equipped[r.kind.rawValue] = id
    }

    public static let profileCardKey = "profileCard"

    public mutating func equipProfileCard(_ itemID: String?) {
        guard let itemID else { equipped[Self.profileCardKey] = nil; return }
        guard CardCatalog.def(forItem: itemID)?.kind == .profile else { return }
        equipped[Self.profileCardKey] = itemID
    }

    public func profileCard(cabinet: Cabinet) -> CardDef? {
        guard let id = equipped[Self.profileCardKey], cabinet.contains(id), let d = CardCatalog.def(forItem: id), d.kind == .profile else { return nil }
        return d
    }

    public mutating func grantOwned(_ id: String) {
        guard let r = SeasonRewards.item(id) else { return }
        owned.insert(id)
        if equipped[r.kind.rawValue] == nil && r.kind.isEquippable { equipped[r.kind.rawValue] = id }
    }

    public var bonusSaveSlots: Int {
        SeasonRewards.all.filter { $0.kind == .saveSlot && owned.contains($0.id) }.count
            + GoldCosmetics.all.filter { $0.item.kind == .saveSlot && owned.contains($0.id) }.count
    }
}
