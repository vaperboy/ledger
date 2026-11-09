import Foundation
import GameCore

/// The Season Pass: an 8-week real-time progression with a free and a premium (Ledger Plus) track. Rewards are cosmetic or comfort only
/// (no cash, no simulation effect) and fixed per tier, so nothing is random. It is NOT part of the game save: seasons follow the real
/// calendar and belong to the player, not to one saved game, so the app keeps it in its own small store (UserDefaults, JSON).
/// XP comes from facts seen in the game (`observe`); a per-day cap keeps heavy play from outrunning the pass.
public struct SeasonPass: Codable, Equatable, Sendable {
    // MARK: Config

    public static let seasonDays = 56
    public static let tierCount = 30
    public static let xpPerTier = 150
    public static let dailyXPCap = 100
    /// Positive-cash weeks in a row that earn the cash XP.
    public static let cashStreakWeeks = 4

    public enum Source: String, Codable, Sendable, CaseIterable {
        case weekReport, dailyGoal, cashStreak, loanRepaid, companyOpened, milestone
        public var xp: Int {
            switch self {
            case .weekReport: return 20
            case .dailyGoal: return 30
            case .cashStreak: return 25
            case .loanRepaid: return 40
            case .companyOpened: return 40
            case .milestone: return 50
            }
        }
        public var title: String {
            switch self {
            case .weekReport: return "Finish a week report"
            case .dailyGoal: return "Complete the daily goal"
            case .cashStreak: return "Keep cash positive for \(SeasonPass.cashStreakWeeks) weeks"
            case .loanRepaid: return "Repay a loan"
            case .companyOpened: return "Open a company"
            case .milestone: return "Reach a career or country milestone"
            }
        }
    }

    /// The few facts read from a game to find what happened since the last look.
    public struct Snapshot: Codable, Equatable, Sendable {
        public var seed: Int, week: Int, cash: Double, companies: Int, loans: Int, goals: Int
        /// The date key of the daily goal once its reward is claimed; empty otherwise.
        public var dailyDone: String
        public init(seed: Int, week: Int, cash: Double, companies: Int, loans: Int, goals: Int, dailyDone: String) {
            self.seed = seed; self.week = week; self.cash = cash; self.companies = companies; self.loans = loans; self.goals = goals; self.dailyDone = dailyDone
        }
    }

    public static func snapshot(_ s: GameState) -> Snapshot {
        let daily: String = (s.rest["dy59"]?["got"].int ?? 0) != 0 ? (s.rest["dy59"]?["d"].string ?? "") : ""
        return Snapshot(seed: s.seed, week: s.week, cash: s.cash, companies: s.companies.count, loans: s.loans.count, goals: Career.goalsDone(s), dailyDone: daily)
    }

    // MARK: State

    /// Real day number (days since 1970) the first season began; later seasons follow every `seasonDays`.
    public var firstDay: Int
    public var season: Int
    public var xp: Int
    /// Reward keys claimed this season, "f12" or "p12" (track letter and tier).
    public var claimed: Set<String>
    /// Every reward id ever claimed; it survives season rollover so a cosmetic stays owned.
    public var owned: Set<String>
    /// Chosen cosmetic per kind (`SeasonReward.Kind.rawValue` to reward id).
    public var equipped: [String: String]
    public var xpDay: Int
    public var xpToday: Int
    public var cashStreak: Int
    public var baseline: Snapshot?

    public init(today: Int) {
        firstDay = today; season = 0; xp = 0; claimed = []; owned = []; equipped = [:]
        xpDay = today; xpToday = 0; cashStreak = 0; baseline = nil
    }

    // MARK: Seasons

    public static func seasonIndex(firstDay: Int, today: Int) -> Int { max(0, (today - firstDay) / seasonDays) }
    public var startDay: Int { firstDay + season * Self.seasonDays }
    public var endDay: Int { startDay + Self.seasonDays }
    public func daysLeft(today: Int) -> Int { max(0, endDay - today) }
    public var seasonNumber: Int { season + 1 }

    /// Starts the new season when the real date has passed the end of this one. XP and claims reset; owned rewards stay. Returns true on rollover.
    @discardableResult
    public mutating func rollover(today: Int) -> Bool {
        let idx: Int = Self.seasonIndex(firstDay: firstDay, today: today)
        guard idx > season else { return false }
        season = idx; xp = 0; claimed = []; xpDay = today; xpToday = 0; cashStreak = 0
        return true
    }

    // MARK: Tiers

    public static func tier(forXP xp: Int) -> Int { min(tierCount, max(0, xp) / xpPerTier) }
    public var tier: Int { Self.tier(forXP: xp) }
    public var isComplete: Bool { tier >= Self.tierCount }
    /// XP gathered towards the next tier (0 when the pass is complete).
    public var xpIntoTier: Int { isComplete ? 0 : xp % Self.xpPerTier }
    public var tierProgress: Double { isComplete ? 1 : Double(xpIntoTier) / Double(Self.xpPerTier) }
    public func xpLeftToday(today: Int) -> Int { xpDay == today ? max(0, Self.dailyXPCap - xpToday) : Self.dailyXPCap }

    /// Progress in words: where the player stands and what is left.
    public var progressText: String {
        if isComplete { return "Season complete: all \(Self.tierCount) tiers reached" }
        return "Tier \(tier) of \(Self.tierCount). \(xpIntoTier) of \(Self.xpPerTier) XP to tier \(tier + 1)"
    }

    // MARK: XP

    /// Adds XP for `source`, trimmed to what the day's cap still allows. Returns the XP actually granted.
    @discardableResult
    public mutating func award(_ source: Source, today: Int, count: Int = 1) -> Int {
        if xpDay != today { xpDay = today; xpToday = 0 }
        let room: Int = max(0, Self.dailyXPCap - xpToday)
        let top: Int = max(0, Self.tierCount * Self.xpPerTier - xp)
        let granted: Int = min(source.xp * max(0, count), room, top)
        xp += granted; xpToday += granted
        return granted
    }

    /// Compares the game with the last look and awards XP for what happened. A different game (seed) or an earlier week only resets the
    /// baseline, so loading another save never pays. Returns the XP granted.
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
        if now.companies > b.companies { total += award(.companyOpened, today: today, count: now.companies - b.companies) }
        if now.loans < b.loans { total += award(.loanRepaid, today: today, count: b.loans - now.loans) }
        if now.goals > b.goals { total += award(.milestone, today: today, count: now.goals - b.goals) }
        if !now.dailyDone.isEmpty && now.dailyDone != b.dailyDone { total += award(.dailyGoal, today: today) }
        return total
    }

    // MARK: Claiming

    public enum Track: String, Codable, Sendable { case free = "f", premium = "p" }

    public enum ClaimResult: Equatable, Sendable {
        case claimed(SeasonReward)
        case alreadyClaimed
        case tierNotReached
        /// Premium reward without Ledger Plus.
        case needsPlus
        case noReward
    }

    static func key(_ track: Track, _ tier: Int) -> String { track.rawValue + String(tier) }
    public func isClaimed(_ track: Track, tier t: Int) -> Bool { claimed.contains(Self.key(track, t)) }

    /// A reward can be claimed once its tier is reached; premium needs Plus (`isPlus`), which is only ever an input.
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

    /// Claims everything open, tier by tier, free before premium.
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

    /// Adds a cosmetic or comfort item bought or won outside the pass (store, box, collection); the first of an equippable kind is equipped.
    public mutating func grantOwned(_ id: String) {
        guard let r = SeasonRewards.item(id) else { return }
        owned.insert(id)
        if equipped[r.kind.rawValue] == nil && r.kind.isEquippable { equipped[r.kind.rawValue] = id }
    }

    /// Save slots added by owned rewards and bought slots (comfort only).
    public var bonusSaveSlots: Int {
        SeasonRewards.all.filter { $0.kind == .saveSlot && owned.contains($0.id) }.count
            + GoldCosmetics.all.filter { $0.item.kind == .saveSlot && owned.contains($0.id) }.count
    }
}
