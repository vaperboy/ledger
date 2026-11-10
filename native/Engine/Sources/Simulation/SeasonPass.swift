import Foundation
import GameCore

public struct SeasonPass: Codable, Equatable, Sendable {

    public static let seasonDays = SeasonCatalog.days(months: SeasonCatalog.monthsPerSeason)
    public static let tierCount = 30
    public static let xpPerTier = 300
    public static let dailyXPCap = 60
    public static let cashStreakWeeks = 4

    public enum Source: String, Codable, Sendable, CaseIterable {
        case weekReport, dailyGoal, cashStreak, loanRepaid, profitMonth, milestone, decision, event
        public var xp: Int {
            switch self {
            case .weekReport: return 15
            case .dailyGoal: return 10
            case .cashStreak: return 25
            case .loanRepaid: return 40
            case .profitMonth: return 30
            case .milestone: return 50
            case .decision: return 2
            case .event: return 2
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
            case .decision: return "Answer a decision"
            case .event: return "Answer an event"
            }
        }
    }

    public struct Snapshot: Codable, Equatable, Sendable {
        public static let unknownMonths = -1
        public var seed: Int, week: Int, cash: Double, profitMonths: Int, loans: Int, goals: Int
        public var dailyDone: String
        public var counters: [String: Int]
        public init(seed: Int, week: Int, cash: Double, profitMonths: Int, loans: Int, goals: Int, dailyDone: String, counters: [String: Int] = [:]) {
            self.seed = seed; self.week = week; self.cash = cash; self.profitMonths = profitMonths; self.loans = loans; self.goals = goals; self.dailyDone = dailyDone; self.counters = counters
        }

        enum CodingKeys: String, CodingKey { case seed, week, cash, profitMonths, loans, goals, dailyDone, counters }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            seed = try c.decode(Int.self, forKey: .seed)
            week = try c.decode(Int.self, forKey: .week)
            cash = try c.decode(Double.self, forKey: .cash)
            profitMonths = try c.decodeIfPresent(Int.self, forKey: .profitMonths) ?? Self.unknownMonths
            loans = try c.decode(Int.self, forKey: .loans)
            goals = try c.decode(Int.self, forKey: .goals)
            dailyDone = try c.decode(String.self, forKey: .dailyDone)
            counters = try c.decodeIfPresent([String: Int].self, forKey: .counters) ?? [:]
        }
    }

    static func profitMonths(_ s: GameState) -> Int {
        var byMonth: [Int: Double] = [:]
        for c in s.companies {
            for m in c.monthlyHistory { byMonth[m.monthIndex, default: 0] += m.profit }
        }
        return byMonth.values.filter { $0 > 0 }.count
    }

    public static func snapshot(_ s: GameState) -> Snapshot {
        let daily: String = (s.rest["dy59"]?["got"].int ?? 0) != 0 ? (s.rest["dy59"]?["d"].string ?? "") : ""
        return Snapshot(seed: s.seed, week: s.week, cash: s.cash, profitMonths: profitMonths(s), loans: s.loans.count, goals: Career.goalsDone(s), dailyDone: daily, counters: PassMissions.counters(s))
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
    public var activeSave: String?
    public var otherLooks: [String: [String: String]]?
    public var loginDay: Int?
    public var missionProgress: [String: Int]?
    public var missionDone: Set<String>?

    public init(today: Int) {
        firstDay = today; season = 0; xp = 0; claimed = []; owned = []; equipped = [:]
        xpDay = today; xpToday = 0; cashStreak = 0; baseline = nil
    }

    public static func seasonIndex(firstDay: Int, today: Int) -> Int { max(0, (today - firstDay) / seasonDays) }
    public var startDay: Int { firstDay + season * Self.seasonDays }
    public var endDay: Int { startDay + Self.seasonDays }
    public func daysLeft(today: Int) -> Int { max(0, endDay - today) }
    public var seasonNumber: Int { season + 1 }
    public var seasonDef: SeasonDef? { SeasonCatalog.active(seasonNumber) }

    public func reward(_ track: Track, tier t: Int) -> SeasonReward? { SeasonRewards.reward(track, tier: t, season: seasonNumber) }

    @discardableResult
    public mutating func rollover(today: Int) -> Bool {
        let idx: Int = Self.seasonIndex(firstDay: firstDay, today: today)
        guard idx > season else { return false }
        missedFree = unclaimedFree
        season = idx; xp = 0; claimed = []; xpDay = today; xpToday = 0; cashStreak = 0
        return true
    }

    public var unclaimedFree: Int {
        (1...Self.tierCount).filter { reward(.free, tier: $0) != nil && $0 <= tier && !isClaimed(.free, tier: $0) }.count
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
        var total = payLogin(today: today)
        pruneMissions(today: today)
        guard let b = baseline, b.seed == now.seed, now.week >= b.week else { cashStreak = 0; return total }
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
        let decisions: Int = max(0, (now.counters["decision"] ?? 0) - (b.counters["decision"] ?? 0))
        let events: Int = max(0, (now.counters["event"] ?? 0) - (b.counters["event"] ?? 0))
        if decisions > 0 { total += award(.decision, today: today, count: decisions) }
        if events > 0 { total += award(.event, today: today, count: events) }
        for metric in ["advance", "decision", "event", "answered"] {
            total += noteMission(metric, max(0, (now.counters[metric] ?? 0) - (b.counters[metric] ?? 0)), today: today)
        }
        total += noteMission("weekReport", now.week - b.week, today: today)
        if !now.dailyDone.isEmpty && now.dailyDone != b.dailyDone { total += noteMission("dailyGoal", 1, today: today) }
        return total
    }

    @discardableResult
    mutating func addPassXP(_ amount: Int) -> Int {
        let top: Int = max(0, Self.tierCount * Self.xpPerTier - xp)
        let granted: Int = min(max(0, amount), top)
        xp += granted
        return granted
    }

    mutating func payLogin(today: Int) -> Int {
        guard loginDay != today else { return 0 }
        loginDay = today
        return addPassXP(PassMissions.loginXP)
    }

    @discardableResult
    mutating func noteMission(_ metric: String, _ amount: Int, today: Int) -> Int {
        guard amount > 0 else { return 0 }
        var prog: [String: Int] = missionProgress ?? [:]
        var done: Set<String> = missionDone ?? []
        var paid = 0
        for m in PassMissions.missions(metric: metric) {
            let k: String = m.key(today: today)
            if done.contains(k) { continue }
            let n: Int = (prog[k] ?? 0) + amount
            prog[k] = min(n, m.target)
            if n >= m.target { done.insert(k); paid += addPassXP(m.xp) }
        }
        missionProgress = prog
        missionDone = done
        return paid
    }

    mutating func pruneMissions(today: Int) {
        func live(_ k: String) -> Bool {
            guard let p = PassMissions.Period.allCases.first(where: { (x: PassMissions.Period) -> Bool in k.hasPrefix(x.prefix) }),
                  let digits = k.dropFirst().split(separator: ".").first, let n = Int(digits) else { return false }
            return n == today / p.days
        }
        if let prog = missionProgress { missionProgress = prog.filter { (e: (key: String, value: Int)) -> Bool in live(e.key) } }
        if let done = missionDone { missionDone = done.filter { (k: String) -> Bool in live(k) } }
    }

    public struct MissionRow: Equatable, Sendable, Identifiable {
        public var mission: PassMissions.Mission
        public var progress: Int
        public var done: Bool
        public var id: String { mission.id }
    }

    public func missionRows(_ period: PassMissions.Period, today: Int) -> [MissionRow] {
        PassMissions.missions(period).map { (m: PassMissions.Mission) -> MissionRow in
            let k: String = m.key(today: today)
            let isDone: Bool = missionDone?.contains(k) == true
            return MissionRow(mission: m, progress: isDone ? m.target : min(m.target, missionProgress?[k] ?? 0), done: isDone)
        }
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
        guard reward(track, tier: t) != nil, t <= tier, !isClaimed(track, tier: t) else { return false }
        return track == .free || isPlus
    }

    public mutating func claim(_ track: Track, tier t: Int, isPlus: Bool) -> ClaimResult {
        guard let r = reward(track, tier: t) else { return .noReward }
        if isClaimed(track, tier: t) { return .alreadyClaimed }
        if t > tier { return .tierNotReached }
        if track == .premium && !isPlus { return .needsPlus }
        claimed.insert(Self.key(track, t)); owned.insert(r.id)
        if r.kind == .xp { addBonus(r.amount) }
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

    public enum EquipOutcome: Equatable, Sendable {
        case equipped
        case notOwned
        case wornElsewhere(save: String)
    }

    public static let defaultSave = "current"

    public var currentSave: String { activeSave ?? Self.defaultSave }

    public mutating func activate(save: String) {
        guard activeSave != nil else { activeSave = save; return }
        let from: String = currentSave
        guard save != from else { return }
        var looks: [String: [String: String]] = otherLooks ?? [:]
        if !equipped.isEmpty { looks[from] = equipped }
        equipped = looks[save] ?? [:]
        looks[save] = nil
        otherLooks = looks.isEmpty ? nil : looks
        activeSave = save
    }

    public mutating func succeed(save old: String, with new: String) {
        guard old != new, old == currentSave else { return }
        activeSave = new
    }

    public mutating func retire(save: String) {
        if save == currentSave { equipped = [:]; return }
        otherLooks?[save] = nil
        if otherLooks?.isEmpty == true { otherLooks = nil }
    }

    public func wornElsewhere(_ itemID: String) -> String? {
        (otherLooks ?? [:]).sorted { $0.key < $1.key }.first { $0.value.values.contains(itemID) }?.key
    }

    private mutating func release(_ itemID: String, from save: String) {
        guard var look = otherLooks?[save] else { return }
        for (k, v) in look where v == itemID { look[k] = nil }
        otherLooks?[save] = look
    }

    @discardableResult
    public mutating func equip(_ id: String, replacing: Bool = false) -> EquipOutcome {
        guard owned.contains(id), let r = SeasonRewards.item(id), r.kind.isEquippable else { return .notOwned }
        if let other = wornElsewhere(id) {
            guard replacing else { return .wornElsewhere(save: other) }
            release(id, from: other)
        }
        equipped[r.kind.rawValue] = id
        return .equipped
    }

    public mutating func unequip(_ kind: SeasonReward.Kind) { equipped[kind.rawValue] = nil }

    public mutating func align(firstDay start: Int, today: Int) {
        guard start != firstDay else { return }
        firstDay = start
        let idx: Int = Self.seasonIndex(firstDay: start, today: today)
        if idx != season {
            season = idx; xp = 0; claimed = []; xpDay = today; xpToday = 0; cashStreak = 0
        }
    }

    public static let profileCardKey = "profileCard"

    @discardableResult
    public mutating func equipProfileCard(_ itemID: String?, replacing: Bool = false) -> EquipOutcome {
        guard let itemID else { equipped[Self.profileCardKey] = nil; return .equipped }
        guard CardCatalog.def(forItem: itemID)?.kind == .profile else { return .notOwned }
        if let other = wornElsewhere(itemID) {
            guard replacing else { return .wornElsewhere(save: other) }
            release(itemID, from: other)
        }
        equipped[Self.profileCardKey] = itemID
        return .equipped
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
