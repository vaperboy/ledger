import Foundation
import Observation
import Businesses
import Simulation

@MainActor @Observable
final class FriendPlayModel {
    static let shared = FriendPlayModel()
    private static let key = "ledger.friendplay.v1"

    struct Saved: Codable, Equatable {
        var raceWeek = 0
        var base = 0.0
        var growth = 0.0
        var pendingWeek = 0
        var pendingGrowth = 0.0
        var lastGiftDay = 0
        var goalWeek = 0
        var counted: [Int] = []
        var mine = 0.0
        var claimedGoalWeek = 0
    }

    private(set) var saved: Saved
    private(set) var race: [RaceEntry] = []
    private(set) var lastPlace: Int?
    private(set) var lastReward = 0
    private(set) var goal: GoalState?
    private(set) var loaded = false

    private init() {
        if let d = UserDefaults.standard.data(forKey: Self.key), let s = try? JSONDecoder().decode(Saved.self, from: d) { saved = s } else { saved = Saved() }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    var canGift: Bool { GiftRules.canSend(lastSentDay: saved.lastGiftDay, today: GameStore.calendarDay()) }

    func markGift() {
        saved.lastGiftDay = GameStore.calendarDay()
        persist()
    }

    var goalClaimable: Bool { (goal?.met ?? false) && !(goal?.reward.isEmpty ?? true) && saved.claimedGoalWeek != goal?.week }

    func refresh(engine: GameEngine?, friends: [PlayerProfile], service: any FriendPlayService) async {
        let today: Int = GameStore.calendarDay()
        let week: Int = FriendRace.week(ofDay: today)
        var changed = false
        if let e = engine {
            let nw: Double = e.leaderboardSubmission(playerID: "me").netWorth
            if saved.raceWeek != week {
                if saved.raceWeek != 0 { saved.pendingWeek = saved.raceWeek; saved.pendingGrowth = saved.growth }
                saved.raceWeek = week
                saved.base = nw
                saved.growth = 0
                changed = true
            } else if saved.base <= 0, nw > 0 {
                saved.base = nw
                changed = true
            } else {
                let g: Double = FriendRace.growth(base: saved.base, now: nw)
                if g != saved.growth { saved.growth = g; changed = true }
            }
            if saved.goalWeek != week {
                saved.goalWeek = week
                saved.counted = []
                saved.mine = 0
                changed = true
            }
            if !saved.counted.contains(e.state.week) {
                saved.counted.append(e.state.week)
                saved.mine += SharedGoalRules.contribution(e.state)
                changed = true
            }
        }
        if changed { persist() }
        if engine != nil {
            try? await service.submitRaceScore(week: week, growth: saved.growth)
            try? await service.submitGoalUnits(week: week, units: saved.mine)
            if saved.pendingWeek != 0 { try? await service.submitRaceScore(week: saved.pendingWeek, growth: saved.pendingGrowth) }
        }
        let others: [RaceEntry] = (try? await service.raceEntries(week: week, day: today, friends: friends)) ?? []
        race = FriendRace.standings([RaceEntry(id: "me", name: "You", growth: saved.growth, isYou: true)] + others)
        if saved.pendingWeek != 0 {
            let past: [RaceEntry] = (try? await service.raceEntries(week: saved.pendingWeek, day: saved.pendingWeek * 7 + 6, friends: friends)) ?? []
            let field: [RaceEntry] = past + [RaceEntry(id: "me", name: "You", growth: saved.pendingGrowth, isYou: true)]
            lastPlace = FriendRace.place(of: "me", in: field)
            lastReward = FriendRace.reward(place: lastPlace, racers: field.count)
            if lastReward == 0 { saved.pendingWeek = 0; persist() }
        } else {
            lastPlace = nil
            lastReward = 0
        }
        let mates: [Double] = (try? await service.groupContributions(week: week, day: today, friends: friends)) ?? []
        goal = SharedGoalRules.state(week: week, members: friends.count + 1, contributions: [saved.mine] + mates, owned: SeasonModel.shared.pass.owned)
        loaded = true
    }

    func claimRace() -> Int {
        guard saved.pendingWeek != 0, lastReward > 0 else { return 0 }
        let gold: Int = lastReward
        saved.pendingWeek = 0
        persist()
        lastReward = 0
        StoreSession.shared.receiveDaily(boxes: 0, gold: gold)
        return gold
    }

    func claimGoal(service: any FriendPlayService) async -> String? {
        guard goalClaimable, let g = goal else { return nil }
        guard let granted = try? await service.claimGoalReward(week: g.week) else { return nil }
        saved.claimedGoalWeek = g.week
        persist()
        guard granted else { return nil }
        SeasonModel.shared.grantOwned(g.reward)
        return GoldCosmetics.cosmetic(g.reward)?.item.title ?? "a cosmetic"
    }
}
