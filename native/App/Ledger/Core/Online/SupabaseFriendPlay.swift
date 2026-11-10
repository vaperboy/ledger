import Foundation
import Simulation

private struct RaceRow: Decodable {
    var id: String
    var name: String
    var growth: Double
}

extension SupabaseOnlineService {
    func raceEntries(week: Int, day: Int, friends: [PlayerProfile]) async throws -> [RaceEntry] {
        let rows: [RaceRow] = try decode([RaceRow].self, try await rpcData("read_race", ["p_week": week]))
        return rows.map { (r: RaceRow) -> RaceEntry in RaceEntry(id: r.id, name: r.name, growth: r.growth) }
    }

    func groupContributions(week: Int, day: Int, friends: [PlayerProfile]) async throws -> [Double] {
        try decode([Double].self, try await rpcData("read_goal_units", ["p_week": week]))
    }

    func submitRaceScore(week: Int, growth: Double) async throws {
        guard growth.isFinite else { return }
        _ = try await rpcData("submit_race_score", ["p_week": week, "p_growth": growth])
    }

    func submitGoalUnits(week: Int, units: Double) async throws {
        guard units.isFinite else { return }
        _ = try await rpcData("submit_goal_units", ["p_week": week, "p_units": units])
    }

    func claimGoalReward(week: Int) async throws -> Bool {
        try decode(Bool.self, try await rpcData("claim_friend_goal", ["p_week": week]))
    }

    func sendGift(to playerID: String, item: ArtifactItem, fromName: String) async throws {
        _ = try await rpcData("send_friend_gift", ["p_to": playerID, "p_def_id": item.defID, "p_serial": item.serial])
    }

    func receivedGifts() async throws -> [GiftRecord] {
        try decode([GiftRecord].self, try await rpcData("received_friend_gifts"))
    }

    func acknowledgeGifts(_ ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        _ = try await rpcData("accept_friend_gifts", ["p_ids": ids])
    }

    func sendPassNotice(to playerIDs: [String], text: String) async throws {
        guard !playerIDs.isEmpty else { return }
        _ = try await rpcData("send_pass_notices", ["p_to": playerIDs])
    }

    func passNotices() async throws -> [String] {
        try decode([String].self, try await rpcData("take_pass_notices"))
    }
}
