import Foundation
import GameCore
import Simulation

// Missions on the phone: draw and progress through the engine, claims here so gold reaches the wallet.
extension GameStore {
    /// Draws missions that are due and moves their progress. Saves only when something changed.
    func syncMissions() {
        guard let e = engine else { return }
        var probe: GameEngine = e
        probe.syncMissions()
        let changed: Bool = probe.state.rest[PlayMissions.storeKey] != e.state.rest[PlayMissions.storeKey] || probe.state.rest["dy59"] != e.state.rest["dy59"]
        guard changed else { return }
        _ = act { (x: inout GameEngine) -> Bool in x.syncMissions(); return true }
    }

    var missionsReady: [PlayMissions.Entry] { engine?.missionsReady ?? [] }

    func missionEntries(_ p: PlayMissions.Period) -> [PlayMissions.Entry] { engine?.missionEntries(p) ?? [] }

    /// Goal rewards that wait for a tap, without the retired single daily goal.
    var openGoalClaims: [GoalClaims.Claimable] { claimableGoals.filter { (c: GoalClaims.Claimable) -> Bool in c.kind != .daily } }

    var rewardsReadyCount: Int { missionsReady.count + openGoalClaims.count }

    private func payMission(_ e: PlayMissions.Entry) -> (xp: Int, cash: Double, gold: Int)? {
        guard case .claimed(_, let xp, let cash, let gold)? = act({ (x: inout GameEngine) -> PlayMissions.Result in x.claimMission(e.period, id: e.missionID) }) else { return nil }
        // The period key names the set the mission came from, so the server pays each mission once.
        let period: String = e.period.rawValue + ":" + String(TrustedClock.today() / e.period.days)
        if gold > 0 { StoreSession.shared.receiveMission(id: e.missionID, period: period, gold: gold) }
        return (xp, cash, gold)
    }

    private func rewardLine(xp: Int, cash: Double, gold: Int) -> String {
        var parts: [String] = ["+\(xp) XP"]
        if cash > 0 { parts.append("+" + short(cash)) }
        if gold > 0 { parts.append("+\(gold) gold") }
        return parts.joined(separator: "  ")
    }

    /// Claims one finished mission. Returns false when it was not ready.
    @discardableResult
    func claimMission(_ e: PlayMissions.Entry) -> Bool {
        guard let got = payMission(e) else { return false }
        Haptics.success()
        tell("Mission done", e.title + "\n" + rewardLine(xp: got.xp, cash: got.cash, gold: got.gold), tone: "good")
        return true
    }

    /// Claims everything that is ready: missions first, then goal rewards.
    func claimAllRewards() {
        var xp: Int = 0, gold: Int = 0, count: Int = 0
        var cash: Double = 0
        for e in missionsReady {
            guard let got = payMission(e) else { continue }
            xp += got.xp; cash += got.cash; gold += got.gold; count += 1
        }
        if count > 0 {
            Haptics.success()
            tell(count == 1 ? "Mission done" : "\(count) missions done", rewardLine(xp: xp, cash: cash, gold: gold), tone: "good")
        }
        for c in openGoalClaims { claimGoal(c.kind, id: c.goalID) }
    }
}
