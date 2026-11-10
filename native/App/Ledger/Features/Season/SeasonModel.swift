import SwiftUI
import GameCore
import Simulation

@MainActor
final class SeasonModel: ObservableObject {
    static let shared = SeasonModel()
    private static let key = "ledger.seasonPass"
    private static let premiumKey = "ledger.seasonPremium"

    @Published private(set) var pass: SeasonPass
    @Published private(set) var premiumSeason: Int?

    private init() {
        let today: Int = GameStore.calendarDay()
        var loaded: SeasonPass?
        if let data = UserDefaults.standard.data(forKey: Self.key) { loaded = try? JSONDecoder().decode(SeasonPass.self, from: data) }
        var p: SeasonPass = loaded ?? SeasonPass(today: today)
        p.rollover(today: today)
        pass = p
        premiumSeason = UserDefaults.standard.object(forKey: Self.premiumKey) as? Int
        if loaded == nil { persist() }
    }

    func premiumOpen(plus: Bool) -> Bool { plus || premiumSeason == pass.season }

    func unlockPremium() {
        premiumSeason = pass.season
        UserDefaults.standard.set(pass.season, forKey: Self.premiumKey)
    }

    var today: Int { GameStore.calendarDay() }

    func observe(_ state: GameState) {
        var p: SeasonPass = pass
        p.observe(SeasonPass.snapshot(state), today: today)
        if p != pass { pass = p; persist() }
    }

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

    func equipProfileCard(_ itemID: String?) {
        var p: SeasonPass = pass
        p.equipProfileCard(itemID)
        if p != pass { pass = p; persist() }
    }

    private static let adDayKey = "ledger.seasonAdDay"

    var adBonusAvailable: Bool { UserDefaults.standard.integer(forKey: Self.adDayKey) != today }

    @discardableResult
    func grantAdBonus() -> Int {
        guard adBonusAvailable else { return 0 }
        var p: SeasonPass = pass
        let xp: Int = p.addBonus(SeasonPass.adBonusXP)
        UserDefaults.standard.set(today, forKey: Self.adDayKey)
        if xp > 0 { pass = p; persist() }
        return xp
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pass) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
