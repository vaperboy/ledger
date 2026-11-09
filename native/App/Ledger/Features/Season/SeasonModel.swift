import SwiftUI
import GameCore
import Simulation

/// The player's Season Pass, kept in UserDefaults (not in a game save: seasons follow the real calendar and belong to the player).
/// The game store calls `observe` after each action and each day; the screen reads `pass`.
@MainActor
final class SeasonModel: ObservableObject {
    static let shared = SeasonModel()
    private static let key = "ledger.seasonPass"

    @Published private(set) var pass: SeasonPass

    private init() {
        let today: Int = GameStore.calendarDay()
        var loaded: SeasonPass?
        if let data = UserDefaults.standard.data(forKey: Self.key) { loaded = try? JSONDecoder().decode(SeasonPass.self, from: data) }
        var p: SeasonPass = loaded ?? SeasonPass(today: today)
        p.rollover(today: today)
        pass = p
        if loaded == nil { persist() }
    }

    var today: Int { GameStore.calendarDay() }

    /// Reads the game for XP; saves only when something changed.
    func observe(_ state: GameState) {
        var p: SeasonPass = pass
        p.observe(SeasonPass.snapshot(state), today: today)
        if p != pass { pass = p; persist() }
    }

    /// Moves to a new season when the real date has passed the end of this one (called when the screen opens).
    func refreshSeason() {
        var p: SeasonPass = pass
        if p.rollover(today: today) { pass = p; persist() }
    }

    func claim(_ track: SeasonPass.Track, tier: Int, isPlus: Bool) -> SeasonPass.ClaimResult {
        var p: SeasonPass = pass
        let r: SeasonPass.ClaimResult = p.claim(track, tier: tier, isPlus: isPlus)
        if case .claimed(let reward) = r { pass = p; persist(); StoreSession.shared.receiveSeason(reward) }
        return r
    }

    func claimAll(isPlus: Bool) -> [SeasonReward] {
        var p: SeasonPass = pass
        let got: [SeasonReward] = p.claimAll(isPlus: isPlus)
        if !got.isEmpty { pass = p; persist(); got.forEach { StoreSession.shared.receiveSeason($0) } }
        return got
    }

    /// Adds a cosmetic or comfort item that came from the store, a box or a finished collection.
    func grantOwned(_ id: String) {
        var p: SeasonPass = pass
        p.grantOwned(id)
        if p != pass { pass = p; persist() }
    }

    func equip(_ id: String) {
        var p: SeasonPass = pass
        p.equip(id)
        if p != pass { pass = p; persist() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pass) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
